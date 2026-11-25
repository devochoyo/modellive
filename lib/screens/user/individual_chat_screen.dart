import 'package:flutter/material.dart';

import '../../model/message_model.dart';
import '../../model/user_model.dart';
import '../../service/api_service.dart';
import '../../service/message_service.dart';
import '../../widget/common_widgets.dart';
import '../colors.dart';

// A private chat with one person.
//
// Open it with:
//   Navigator.pushNamed(context, '/individual-chat', arguments: conversation)
//   (a ConversationModel from the chat list) or
//   Navigator.pushNamed(context, '/individual-chat', arguments: user)
//   (a UserModel, for example from a public profile).
//
// Messages are loaded with the REST endpoints. The one Socket.IO connection
// of MessageService brings new messages and delivered / read updates live.
class IndividualChatScreen extends StatefulWidget {
  final UserModel user; // the other person
  final int? conversationId; // null when the conversation is not known yet

  const IndividualChatScreen({
    super.key,
    required this.user,
    this.conversationId,
  });

  @override
  State<IndividualChatScreen> createState() => _IndividualChatScreenState();
}

class _IndividualChatScreenState extends State<IndividualChatScreen> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // Oldest first, as the backend sends them.
  final List<MessageModel> _messages = [];
  // Texts being sent right now (shown with a clock icon).
  final List<String> _pending = [];

  int? _conversationId;
  int? _nextBeforeId;
  bool _hasMore = false;
  bool _isLoading = true;
  bool _isRetrying = false;
  bool _isLoadingOlder = false;
  bool _isSending = false;
  bool _socketReady = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _conversationId = widget.conversationId;
    _scrollController.addListener(_onScroll);
    _connectSocket();
    _loadMessages();
  }

  // Close returns to the Chat List tab of the main screen.
  void _close() {
    Navigator.pushNamedAndRemoveUntil(context, '/chat-list', (route) => false);
  }

  @override
  void dispose() {
    // Closes the connection and removes its listeners.
    MessageService.disconnectSocket();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ---------- Socket ----------

  Future<void> _connectSocket() async {
    try {
      await MessageService.connectSocket();
    } catch (_) {
      // Without the socket the screen still works through the REST endpoints.
      return;
    }
    if (!mounted) {
      MessageService.disconnectSocket();
      return;
    }
    MessageService.onNewMessage(_onNewMessage);
    MessageService.onMessageStatus(_onMessageStatus);
    MessageService.onReconnected(_onReconnected);
    _socketReady = true;
  }

  void _onNewMessage(MessageModel message) {
    if (!mounted) return;
    final sameChat = _conversationId != null
        ? message.conversationId == _conversationId
        : message.senderId == widget.user.id;
    if (!sameChat) return;
    if (_messages.any((m) => m.id == message.id)) return;

    setState(() {
      _conversationId ??= message.conversationId;
      _messages.add(message);
    });
    _markAsRead();
  }

  // The other person received or read my messages: update the ticks.
  void _onMessageStatus(int conversationId, String status) {
    if (!mounted || conversationId != _conversationId) return;
    setState(() {
      for (int i = 0; i < _messages.length; i++) {
        final message = _messages[i];
        if (_isMine(message) && _statusRank(message.status) < _statusRank(status)) {
          _messages[i] = _withStatus(message, status);
        }
      }
    });
  }

  // Socket events are not stored, so load the messages again.
  void _onReconnected() {
    if (!mounted) return;
    _loadMessages(silent: true);
  }

  // ---------- Loading ----------

  Future<void> _loadMessages({bool retry = false, bool silent = false}) async {
    if (!silent) {
      setState(() {
        if (retry) {
          _isRetrying = true;
        } else {
          _isLoading = true;
        }
      });
    }

    try {
      _conversationId ??= await _findConversationId();

      // No conversation yet: it is created by the first message.
      if (_conversationId == null) {
        if (!mounted) return;
        setState(() {
          _errorMessage = null;
          _isLoading = false;
          _isRetrying = false;
        });
        return;
      }

      final result = await MessageService.getConversationMessages(
        conversationId: _conversationId!,
      );
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(result.messages);
        _hasMore = result.hasMore;
        _nextBeforeId = result.nextBeforeId;
        _errorMessage = null;
        _isLoading = false;
        _isRetrying = false;
      });
      _markAsRead();
    } on ApiException catch (e) {
      _showLoadError(e.message, silent);
    } catch (_) {
      _showLoadError('Could not load this chat. Please try again.', silent);
    }
  }

  void _showLoadError(String message, bool silent) {
    if (!mounted) return;
    // A silent reload that fails keeps the messages already on screen.
    if (silent && _messages.isNotEmpty) return;
    setState(() {
      _errorMessage = message;
      _isLoading = false;
      _isRetrying = false;
    });
  }

  // When the chat was opened from a profile only the person is known, so
  // look for the existing conversation with them in the chat list.
  Future<int?> _findConversationId() async {
    const perPage = 20;
    for (int page = 1; page <= 10; page++) {
      final list =
          await MessageService.getConversations(page: page, perPage: perPage);
      for (var conversation in list) {
        if (conversation.user.id == widget.user.id) {
          return conversation.conversationId;
        }
      }
      if (list.length < perPage) break;
    }
    return null;
  }

  Future<void> _loadOlder() async {
    final id = _conversationId;
    if (_isLoadingOlder || !_hasMore || id == null || _nextBeforeId == null) {
      return;
    }
    setState(() => _isLoadingOlder = true);
    try {
      final result = await MessageService.getConversationMessages(
        conversationId: id,
        beforeId: _nextBeforeId,
      );
      if (!mounted) return;
      setState(() {
        _messages.insertAll(0, result.messages);
        _hasMore = result.hasMore;
        _nextBeforeId = result.nextBeforeId;
        _isLoadingOlder = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingOlder = false);
    }
  }

  // The list is reversed, so the older messages are at the end.
  void _onScroll() {
    if (_scrollController.position.extentAfter < 200) _loadOlder();
  }

  Future<void> _markAsRead() async {
    final id = _conversationId;
    if (id == null) return;
    try {
      if (_socketReady) {
        await MessageService.markConversationAsReadRealtime(conversationId: id);
      } else {
        await MessageService.markConversationAsRead(conversationId: id);
      }
    } catch (_) {
      // Not important enough to bother the user.
    }
  }

  // ---------- Sending ----------

  Future<void> _send() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() {
      _isSending = true;
      _pending.add(text);
    });
    _scrollToLatest();

    try {
      final message = _socketReady
          ? await MessageService.sendMessageRealtime(
              receiverId: widget.user.id, body: text)
          : await MessageService.sendMessage(
              receiverId: widget.user.id, body: text);
      if (!mounted) return;
      setState(() {
        _pending.clear();
        _conversationId ??= message.conversationId;
        if (!_messages.any((m) => m.id == message.id)) {
          _messages.add(message);
        }
        _isSending = false;
      });
      // Clear the box only if nothing new was typed meanwhile.
      if (_inputController.text.trim() == text) _inputController.clear();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pending.clear();
        _isSending = false;
      });
      final message = e is ApiException
          ? e.message
          : 'Could not send the message. Please try again.';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  // The list is reversed: position 0 is the newest message.
  void _scrollToLatest() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  // ---------- Helpers ----------

  bool _isMine(MessageModel message) {
    return message.isMine ?? (message.senderId != widget.user.id);
  }

  int _statusRank(String status) {
    if (status == 'read') return 3;
    if (status == 'delivered') return 2;
    if (status == 'sent') return 1;
    return 0;
  }

  MessageModel _withStatus(MessageModel m, String status) {
    return MessageModel(
      id: m.id,
      conversationId: m.conversationId,
      senderId: m.senderId,
      receiverId: m.receiverId,
      body: m.body,
      status: status,
      isMine: m.isMine,
      createdAt: m.createdAt,
      deliveredAt: m.deliveredAt,
      readAt: m.readAt,
    );
  }

  String _formatClock(DateTime time) {
    final local = time.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  // ---------- Screen ----------

  @override
  Widget build(BuildContext context) {
    final name = widget.user.fullName ?? widget.user.username;

    return Scaffold(
      backgroundColor: AppColors.blushBackground,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 1,
        shadowColor: AppColors.softPink,
        scrolledUnderElevation: 1,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: AppColors.deepPink),
          onPressed: _close,
        ),
        title: Row(
          children: [
            UserAvatar(url: widget.user.avatarUrl, name: name, radius: 19),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.darkBackground,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: _buildMessages(name)),
            if (_errorMessage == null && !_isLoading) _buildInputBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildMessages(String name) {
    if (_isLoading) return const LoadingView(message: 'Loading messages...');
    if (_errorMessage != null) {
      return ErrorRetryView(
        message: _errorMessage!,
        retrying: _isRetrying,
        onRetry: () => _loadMessages(retry: true),
      );
    }
    if (_messages.isEmpty && _pending.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            'Send a message to start chatting with $name.',
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: AppColors.softGrey, fontSize: 15, height: 1.4),
          ),
        ),
      );
    }

    // reverse: true keeps the newest message at the bottom.
    final loaderCount = _isLoadingOlder ? 1 : 0;
    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      itemCount: _pending.length + _messages.length + loaderCount,
      itemBuilder: (context, index) {
        if (index < _pending.length) {
          final text = _pending[_pending.length - 1 - index];
          return _buildBubble(
            body: text,
            mine: true,
            time: null,
            status: null,
          );
        }

        final messageIndex = index - _pending.length;
        if (messageIndex >= _messages.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: TypingDots()),
          );
        }

        final message = _messages[_messages.length - 1 - messageIndex];
        return _buildBubble(
          body: message.body,
          mine: _isMine(message),
          time: message.createdAt,
          status: message.status,
        );
      },
    );
  }

  // [status] null on a mine message means it is still being sent.
  Widget _buildBubble({
    required String body,
    required bool mine,
    required DateTime? time,
    required String? status,
  }) {
    final maxWidth = MediaQuery.of(context).size.width * 0.75;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: mine ? AppColors.primaryPink : AppColors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(mine ? 18 : 4),
                  bottomRight: Radius.circular(mine ? 4 : 18),
                ),
                boxShadow: mine
                    ? null
                    : [
                        BoxShadow(
                          color: AppColors.primaryPink.withOpacity(0.10),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
              ),
              child: Text(
                body,
                style: TextStyle(
                  color: mine ? AppColors.white : AppColors.darkBackground,
                  fontSize: 15,
                  height: 1.35,
                ),
              ),
            ),
          ),
          const SizedBox(height: 3),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (time != null)
                Text(
                  _formatClock(time),
                  style: const TextStyle(
                      color: AppColors.softGrey, fontSize: 11),
                ),
              if (mine) ...[
                const SizedBox(width: 4),
                _buildTick(status),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // Sending: clock. Sent: one check. Delivered: two grey checks.
  // Read: two blue checks. The status comes from the backend.
  Widget _buildTick(String? status) {
    if (status == null) {
      return const Icon(Icons.access_time_rounded,
          size: 13, color: AppColors.softGrey);
    }
    if (status == 'read') {
      return const Icon(Icons.done_all_rounded,
          size: 16, color: AppColors.diamondBlue);
    }
    if (status == 'delivered') {
      return const Icon(Icons.done_all_rounded,
          size: 16, color: AppColors.softGrey);
    }
    return const Icon(Icons.check_rounded, size: 16, color: AppColors.softGrey);
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: AppColors.white,
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryPink.withOpacity(0.10),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _inputController,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Type a message',
                hintStyle:
                    const TextStyle(color: AppColors.softGrey, fontSize: 15),
                filled: true,
                fillColor: AppColors.blushBackground,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: const BorderSide(color: AppColors.softPink),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: const BorderSide(
                      color: AppColors.primaryPink, width: 1.5),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // The button keeps its size while the dots are shown.
          GestureDetector(
            onTap: _send,
            child: Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                color: AppColors.primaryPink,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: _isSending
                    ? const TypingDots(color: AppColors.white, dotSize: 5)
                    : const Icon(Icons.send_rounded,
                        color: AppColors.white, size: 22),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
