import 'package:flutter/material.dart';

import '../../model/conversation_model.dart';
import '../../service/api_service.dart';
import '../../service/message_service.dart';
import '../../widget/common_widgets.dart';
import '../colors.dart';

// The user's private conversations, newest activity first (the backend
// sorts them). Open it with: Navigator.pushNamed(context, '/chat-list')
class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  static const int _perPage = 20;

  final ScrollController _scrollController = ScrollController();
  final List<ConversationModel> _conversations = [];

  int _page = 1;
  bool _isLoading = true;
  bool _isRetrying = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadConversations();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // [silent] reloads without hiding the list (used after leaving a chat).
  Future<void> _loadConversations({
    bool retry = false,
    bool silent = false,
  }) async {
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
      final list =
          await MessageService.getConversations(page: 1, perPage: _perPage);
      if (!mounted) return;
      setState(() {
        _conversations
          ..clear()
          ..addAll(list);
        _page = 1;
        _hasMore = list.length == _perPage;
        _errorMessage = null;
        _isLoading = false;
        _isRetrying = false;
      });
    } on ApiException catch (e) {
      _showLoadError(e.message, silent);
    } catch (_) {
      _showLoadError('Could not load your messages. Please try again.', silent);
    }
  }

  void _showLoadError(String message, bool silent) {
    if (!mounted) return;
    // A silent reload that fails keeps the list already on screen.
    if (silent && _conversations.isNotEmpty) return;
    setState(() {
      _errorMessage = message;
      _isLoading = false;
      _isRetrying = false;
    });
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore || _isLoading || _errorMessage != null) {
      return;
    }
    setState(() => _isLoadingMore = true);
    try {
      final list = await MessageService.getConversations(
        page: _page + 1,
        perPage: _perPage,
      );
      if (!mounted) return;
      setState(() {
        _page++;
        _conversations.addAll(list);
        _hasMore = list.length == _perPage;
        _isLoadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
    }
  }

  void _onScroll() {
    if (_scrollController.position.extentAfter < 300) _loadMore();
  }

  Future<void> _openChat(ConversationModel conversation) async {
    await Navigator.pushNamed(context, '/individual-chat',
        arguments: conversation);
    if (!mounted) return;
    // Unread counts and previews may have changed.
    _loadConversations(silent: true);
  }

  // Today: 14:05. Yesterday: Yesterday. Older: 3/11/2026.
  String _formatTime(DateTime time) {
    final local = time.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    final daysAgo = today.difference(day).inDays;

    if (daysAgo == 0) {
      final hour = local.hour.toString().padLeft(2, '0');
      final minute = local.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    }
    if (daysAgo == 1) return 'Yesterday';
    return '${local.day}/${local.month}/${local.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.blushBackground,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return const Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Messages',
              style: TextStyle(
                color: AppColors.deepPink,
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'Your private conversations.',
              style: TextStyle(color: AppColors.softGrey, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const LoadingView(message: 'Loading messages...');
    if (_errorMessage != null) {
      return ErrorRetryView(
        message: _errorMessage!,
        retrying: _isRetrying,
        onRetry: () => _loadConversations(retry: true),
      );
    }
    if (_conversations.isEmpty) {
      return const EmptyStateView(
        icon: Icons.chat_bubble_outline_rounded,
        title: 'No messages yet.',
        message: 'Open a profile and tap Message to start chatting.',
      );
    }

    return RefreshIndicator(
      color: AppColors.primaryPink,
      onRefresh: _loadConversations,
      child: ListView.separated(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: _conversations.length + 1,
        separatorBuilder: (context, index) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (index == _conversations.length) {
            return SizedBox(
              height: 48,
              child: _isLoadingMore ? const Center(child: TypingDots()) : null,
            );
          }
          return _buildRow(_conversations[index]);
        },
      ),
    );
  }

  Widget _buildRow(ConversationModel conversation) {
    final user = conversation.user;
    final name = user.fullName ?? user.username;
    final last = conversation.lastMessage;
    final time = conversation.lastMessageAt ?? last?.createdAt;
    final hasUnread = conversation.unreadCount > 0;

    String preview = 'No messages yet.';
    if (last != null) {
      // last_message has no is_mine field, so compare the sender instead.
      preview = last.senderId != user.id ? 'You: ${last.body}' : last.body;
    }

    return GestureDetector(
      onTap: () => _openChat(conversation),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryPink.withOpacity(0.08),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            UserAvatar(url: user.avatarUrl, name: name, radius: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.darkBackground,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: hasUnread
                          ? AppColors.darkBackground
                          : AppColors.softGrey,
                      fontSize: 14,
                      fontWeight:
                          hasUnread ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (time != null)
                  Text(
                    _formatTime(time),
                    style: TextStyle(
                      color: hasUnread
                          ? AppColors.primaryPink
                          : AppColors.softGrey,
                      fontSize: 12,
                      fontWeight:
                          hasUnread ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                if (hasUnread) ...[
                  const SizedBox(height: 6),
                  Container(
                    constraints:
                        const BoxConstraints(minWidth: 22, minHeight: 22),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      color: AppColors.primaryPink,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Center(
                      child: Text(
                        conversation.unreadCount > 99
                            ? '99+'
                            : conversation.unreadCount.toString(),
                        style: const TextStyle(
                          color: AppColors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
