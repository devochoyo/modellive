import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../model/comment_model.dart';
import '../../model/join_request_model.dart';
import '../../model/participant_model.dart';
import '../../service/api_service.dart';
import '../../service/diagnostics_service.dart';
import '../../service/live_stream_service.dart';
import '../../service/profile_service.dart';
import '../../service/videosdk_service.dart';
import '../../widget/common_widgets.dart';
import '../colors.dart';

// Start and manage your own live stream. Open it with:
//   Navigator.pushNamed(context, '/host-live')                 (no title)
//   Navigator.pushNamed(context, '/host-live', arguments: 'My title')
//
// Backend flow:
//   1. createLiveStream  (room + token)
//   2. join the VideoSDK room and publish camera + microphone
//   3. startLiveStream   (the stream becomes live)
// Socket events: comments, flowers, join requests, stage changes.
class HostLiveScreen extends StatefulWidget {
  final String? title;

  const HostLiveScreen({super.key, this.title});

  @override
  State<HostLiveScreen> createState() => _HostLiveScreenState();
}

class _HostLiveScreenState extends State<HostLiveScreen> {
  final TextEditingController _commentController = TextEditingController();

  int _generation = 0; // old socket callbacks are ignored
  int? _streamId;
  int? _myId;

  bool _starting = true;
  bool _retrying = false;
  bool _isLive = false; // true after the backend confirmed "start"
  bool _ending = false;
  bool _cleanedUp = false;
  bool _fullScreen = false; // the default view is NOT full screen
  String? _error;

  List<ParticipantModel> _stage = [];
  final List<CommentModel> _comments = [];
  final List<FlowerEvent> _flowers = [];
  int _flowerCounter = 0;
  final List<JoinRequestModel> _requests = [];
  // request id -> "approve" or "reject" while that request is processing.
  final Map<int, String> _processing = {};
  int _viewerCount = 0;
  int _likeCount = 0;
  int? _selectedId; // flower recipient (a guest)
  String _myName = '';
  String? _myAvatar;
  final List<DateTime> _recentComments = [];

  @override
  void initState() {
    super.initState();
    VideoSdkService.onParticipantsChanged = _redraw;
    VideoSdkService.onStreamChanged = (id, kind, enabled) => _redraw();
    VideoSdkService.onError = (message) => _snack(message);
    _startLive();
  }

  @override
  void dispose() {
    VideoSdkService.onParticipantsChanged = null;
    VideoSdkService.onStreamChanged = null;
    VideoSdkService.onError = null;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _commentController.dispose();
    _cleanup();
    super.dispose();
  }

  // ---------- Helpers ----------

  void _set(VoidCallback change) {
    if (mounted) setState(change);
  }

  void _redraw() => _set(() {});

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  bool _isCurrent(int generation) => mounted && generation == _generation;

  String _nameOf(String? fullName, String username) =>
      (fullName != null && fullName.isNotEmpty) ? fullName : username;

  // ---------- Starting the stream ----------

  Future<void> _startLive() async {
    final generation = ++_generation;
    _cleanedUp = false;
    _set(() {
      _starting = true;
      _error = null;
    });

    try {
      await Diagnostics.beginSession('HOST');
      Diagnostics.log('HOST', 'step 1/7: loading my profile...');
      final me = await ProfileService.getMyProfile();
      Diagnostics.log('HOST', 'step 1/7 done: profile loaded (id=${me.id})');
      _myId = me.id;
      _myName = _nameOf(me.fullName, me.username);
      _myAvatar = me.avatarUrl;
      // The host's own camera shows right away.
      _set(() => _stage = [
            ParticipantModel(
              id: me.id,
              username: me.username,
              fullName: me.fullName,
              avatarUrl: me.avatarUrl,
              role: 'host',
            ),
          ]);

      // Camera and microphone (and Bluetooth on Android 12+) permissions.
      Diagnostics.log('HOST', 'step 2/7: asking for permissions...');
      final allowed = await VideoSdkService.ensurePermissions();
      if (!allowed) {
        Diagnostics.log('HOST', 'step 2/7 FAILED: permission refused');
        throw ApiException(VideoSdkService.permissionProblem ??
            'Camera and microphone permission are needed to go live. '
                'Please allow them in your phone settings.');
      }
      Diagnostics.log('HOST', 'step 2/7 done: permissions granted');

      // 1. Create the stream.
      Diagnostics.log('HOST', 'step 3/7: creating the stream on the backend...');
      final created =
          await LiveStreamService.createLiveStream(title: widget.title);
      _streamId = created.id;
      Diagnostics.log('HOST',
          'step 3/7 done: streamId=${created.id} roomId=${created.roomId} '
          'participantId=${created.participantId} role=${created.role} '
          'hasToken=${created.token != null}');

      if (created.roomId == null ||
          created.participantId == null ||
          created.token == null) {
        throw ApiException('The video room information is missing.');
      }

      // Socket: connect, listeners, then join the stream room.
      Diagnostics.log('HOST', 'step 4/7: connecting the chat socket...');
      await LiveStreamService.connectSocket();
      _registerListeners(generation);
      await LiveStreamService.joinStreamRoom(streamId: created.id);
      Diagnostics.log('HOST', 'step 4/7 done: socket connected, stream room joined');

      // 2. Join the video room and publish camera + microphone.
      Diagnostics.log('HOST', 'step 5/7: joining the video room...');
      await VideoSdkService.joinRoom(
        roomId: created.roomId!,
        participantId: created.participantId!,
        token: created.token!,
        role: created.role ?? 'host',
        displayName: '${me.id}',
      );

      Diagnostics.log('HOST', 'step 5/7 done: video room join requested');

      // 3. Tell the backend the host is ready.
      Diagnostics.log('HOST', 'step 6/7: telling the backend the stream started...');
      await LiveStreamService.startLiveStream(streamId: created.id);
      _isLive = true;
      Diagnostics.log('HOST', 'step 6/7 done: stream is LIVE');

      if (!_isCurrent(generation)) return;
      setState(() {
        _starting = false;
        _retrying = false;
      });

      Diagnostics.log('HOST', 'step 7/7: loading stage and join requests...');
      await _refreshStage();
      await _loadRequests();
      Diagnostics.log('HOST', 'step 7/7 done: host screen is running');
    } on ApiException catch (e) {
      Diagnostics.log('HOST', 'start FAILED (ApiException): ${e.message}');
      await _startFailed(e.message);
    } catch (e, st) {
      Diagnostics.log('HOST', 'start FAILED (unexpected error): $e\n$st');
      await _startFailed('Could not start your live stream. Please try again.');
    }
  }

  Future<void> _startFailed(String message) async {
    await Diagnostics.endSession('start failed: $message');
    // A stream that was created but never started must not stay open.
    final id = _streamId;
    if (id != null && !_isLive) {
      try {
        await LiveStreamService.endLiveStream(streamId: id);
      } catch (_) {}
    }
    _streamId = null;
    await _cleanup();
    _set(() {
      _error = message;
      _starting = false;
      _retrying = false;
    });
  }

  void _retry() {
    setState(() => _retrying = true);
    _startLive();
  }

  Future<void> _refreshStage() async {
    final id = _streamId;
    if (id == null) return;
    try {
      final details = await LiveStreamService.getLiveStreamDetails(streamId: id);
      _set(() {
        if (details.participants.isNotEmpty) _stage = details.participants;
        _viewerCount = details.viewerCount;
        _likeCount = details.likeCount ?? _likeCount;
      });
    } catch (_) {}
  }

  Future<void> _loadRequests() async {
    final id = _streamId;
    if (id == null) return;
    try {
      final list = await LiveStreamService.getJoinRequests(streamId: id);
      _set(() {
        _requests
          ..clear()
          ..addAll(list.where((r) => r.status == 'pending'));
      });
    } catch (_) {}
  }

  // ---------- Socket events ----------

  void _registerListeners(int generation) {
    LiveStreamService.onComment((comment) {
      if (!_isCurrent(generation)) return;
      setState(() {
        _comments.add(comment);
        if (_comments.length > 100) _comments.removeAt(0);
      });
    });

    LiveStreamService.onFlower((data) {
      if (!_isCurrent(generation)) return;
      setState(() {
        _flowerCounter++;
        _flowers.add(FlowerEvent.fromSocket(data, _flowerCounter));
      });
    });

    LiveStreamService.onViewerCount((count, display) {
      if (!_isCurrent(generation)) return;
      setState(() => _viewerCount = count);
    });

    LiveStreamService.onLikeCount((count) {
      if (!_isCurrent(generation)) return;
      setState(() => _likeCount = count);
    });

    LiveStreamService.onParticipants((list) {
      if (!_isCurrent(generation)) return;
      setState(() {
        _stage = list;
        if (_selectedId != null && !list.any((p) => p.id == _selectedId)) {
          _selectedId = null;
        }
      });
    });

    LiveStreamService.onJoinRequest((request) {
      if (!_isCurrent(generation)) return;
      setState(() {
        if (!_requests.any((r) => r.id == request.id)) {
          _requests.add(request);
        }
      });
    });

    // The stream was ended from somewhere else.
    LiveStreamService.onStreamEnded(() {
      if (!_isCurrent(generation) || _ending) return;
      _isLive = false;
      _finish('This live stream has ended.');
    });

    // Events are not stored, so reload the state after a reconnect.
    LiveStreamService.onReconnected(() async {
      if (!_isCurrent(generation)) return;
      final id = _streamId;
      if (id == null) return;
      try {
        await LiveStreamService.joinStreamRoom(streamId: id);
      } catch (_) {}
      await _refreshStage();
      await _loadRequests();
    });
  }

  // ---------- Join requests ----------

  Future<void> _answerRequest(JoinRequestModel request, bool approve) async {
    final id = _streamId;
    if (id == null || _processing.containsKey(request.id)) return;
    setState(() => _processing[request.id] = approve ? 'approve' : 'reject');

    try {
      if (approve) {
        await LiveStreamService.approveJoinRequest(
            streamId: id, requestId: request.id);
      } else {
        await LiveStreamService.rejectJoinRequest(
            streamId: id, requestId: request.id);
      }
      _set(() => _requests.removeWhere((r) => r.id == request.id));
      if (approve) await _refreshStage();
    } on ApiException catch (e) {
      _snack(e.message);
      // The request may already be answered or cancelled.
      if (e.statusCode == 404 || e.statusCode == 409) {
        _set(() => _requests.removeWhere((r) => r.id == request.id));
      }
    } catch (_) {
      _snack('Could not answer the request. Please try again.');
    } finally {
      _set(() => _processing.remove(request.id));
    }
  }

  // ---------- Guests ----------

  Future<void> _removeGuest(ParticipantModel guest) async {
    final id = _streamId;
    // The host can never be removed with this control.
    if (id == null || guest.role != 'guest' || guest.id == _myId) return;
    final name = _nameOf(guest.fullName, guest.username);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.darkSurface,
        title: Text('Remove $name?',
            style: const TextStyle(color: AppColors.white)),
        content: const Text(
          'They will leave the stage and go back to watching.',
          style: TextStyle(color: AppColors.softGrey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.softGrey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove',
                style: TextStyle(
                    color: AppColors.primaryPink,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await LiveStreamService.removeParticipant(streamId: id, userId: guest.id);
      _set(() {
        _stage.removeWhere((p) => p.id == guest.id);
        if (_selectedId == guest.id) _selectedId = null;
      });
      _snack('$name was removed from the stage.');
    } on ApiException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('Could not remove this guest. Please try again.');
    }
  }

  // ---------- Comments ----------

  Future<void> _sendComment() async {
    final text = _commentController.text.trim();
    final id = _streamId;
    if (text.isEmpty || id == null || !_isLive) return;
    if (text.length > 200) {
      _snack('A comment can have at most 200 characters.');
      return;
    }

    // The backend allows about 2 comments per second.
    final now = DateTime.now();
    _recentComments
        .removeWhere((t) => now.difference(t).inMilliseconds >= 1000);
    if (_recentComments.length >= 2) {
      _snack('You are commenting too fast.');
      return;
    }
    _recentComments.add(now);

    _commentController.clear();
    try {
      await LiveStreamService.sendComment(streamId: id, text: text);
    } on ApiException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('Could not send your comment.');
    }
  }

  // ---------- Flowers ----------

  List<ParticipantModel> get _guests =>
      _stage.where((p) => p.id != _myId).toList();

  // The selected guest. With exactly one guest, that guest is the default.
  ParticipantModel? _recipient() {
    final guests = _guests;
    for (var p in guests) {
      if (p.id == _selectedId) return p;
    }
    if (guests.length == 1) return guests.first;
    return null;
  }

  void _selectRecipient(ParticipantModel person) {
    if (person.id == _myId) {
      _snack('You cannot send flowers to yourself.');
      return;
    }
    setState(() => _selectedId = person.id);
  }

  Future<void> _openFlowerSheet() async {
    final id = _streamId;
    final recipient = _recipient();
    if (id == null || !_isLive) return;
    if (recipient == null) {
      _snack(_guests.isEmpty
          ? 'Flowers can be sent to guests on your stage.'
          : 'Tap a guest\'s video to choose who receives your flowers.');
      return;
    }
    await showFlowerGiftSheet(context, streamId: id, recipient: recipient);
  }

  // ---------- Full screen ----------

  void _toggleFullScreen() {
    setState(() => _fullScreen = !_fullScreen);
    SystemChrome.setEnabledSystemUIMode(
      _fullScreen ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
  }

  // ---------- Ending the stream ----------

  Future<void> _confirmEnd() async {
    if (_ending) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.darkSurface,
        title: const Text('End live?',
            style: TextStyle(color: AppColors.white)),
        content: const Text(
          'Your viewers and guests will be disconnected.',
          style: TextStyle(color: AppColors.softGrey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep Streaming',
                style: TextStyle(color: AppColors.softGrey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('End Live',
                style: TextStyle(
                    color: AppColors.primaryPink,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmed == true) _endLive();
  }

  Future<void> _endLive() async {
    final id = _streamId;
    setState(() => _ending = true);

    if (id != null) {
      try {
        await LiveStreamService.endLiveStream(streamId: id);
      } on ApiException catch (e) {
        _snack(e.message);
        _set(() => _ending = false);
        return;
      } catch (_) {
        _snack('Could not end the live. Please try again.');
        _set(() => _ending = false);
        return;
      }
    }
    // The backend confirmed: the stream is no longer active here.
    _isLive = false;
    _finish(null);
  }

  // Cleans up and returns to Home.
  Future<void> _finish(String? message) async {
    await _cleanup();
    if (!mounted) return;
    if (message != null) _snack(message);
    Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
  }

  // Leaves the socket room and the video room, then closes the socket.
  Future<void> _cleanup() async {
    if (_cleanedUp) return;
    _cleanedUp = true;
    _generation++;
    final id = _streamId;
    Diagnostics.log('HOST', 'cleanup: leaving socket and video room...');

    LiveStreamService.removeAllListeners();
    if (id != null) {
      try {
        await LiveStreamService.leaveStreamRoom(streamId: id);
      } catch (_) {}
    }
    await VideoSdkService.leaveRoom();
    LiveStreamService.disconnectSocket();
    await Diagnostics.endSession('host screen closed normally');
  }

  Future<bool> _onBackPressed() async {
    if (_fullScreen) {
      _toggleFullScreen();
      return false;
    }
    if (_starting) return false;
    // A running live must be ended on purpose.
    if (_isLive && !_ending) {
      _confirmEnd();
      return false;
    }
    return true;
  }

  // ---------- Build ----------

  @override
  Widget build(BuildContext context) {
    // ignore: deprecated_member_use
    return WillPopScope(
      onWillPop: _onBackPressed,
      child: Scaffold(
        backgroundColor: AppColors.darkBackground,
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_starting) {
      return const LoadingView(message: 'Starting your live...', dark: true);
    }

    if (_error != null) {
      return SafeArea(
        child: Stack(
          children: [
            ErrorRetryView(
                message: _error!, retrying: _retrying, onRetry: _retry),
            Positioned(
              top: 8,
              left: 12,
              child: IconButton(
                icon: const Icon(Icons.arrow_back_rounded,
                    color: AppColors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      );
    }

    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  _fullScreen ? 0 : 8, 6, _fullScreen ? 0 : 8, 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(_fullScreen ? 0 : 24),
                child: _buildVideoArea(),
              ),
            ),
          ),
          // Controls below the video (hidden in full screen).
          if (!_fullScreen) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: _controlButton(
                      icon: Icons.fullscreen_rounded,
                      label: 'Full Screen',
                      filled: false,
                      onTap: _toggleFullScreen,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _controlButton(
                      icon: Icons.stop_circle_rounded,
                      label: 'End Live',
                      filled: true,
                      loading: _ending,
                      onTap: _confirmEnd,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: LiveInputBar(
                controller: _commentController,
                onSend: _sendComment,
                onFlower: _openFlowerSheet,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _controlButton({
    required IconData icon,
    required String label,
    required bool filled,
    required VoidCallback onTap,
    bool loading = false,
  }) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        height: 46,
        decoration: BoxDecoration(
          color: filled ? AppColors.deepPink : AppColors.darkSurface,
          borderRadius: BorderRadius.circular(23),
          border: Border.all(
              color: filled ? AppColors.deepPink : AppColors.softGrey.withOpacity(0.4)),
        ),
        child: Center(
          child: loading
              ? const TypingDots(color: AppColors.white, dotSize: 6)
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, color: AppColors.white, size: 20),
                    const SizedBox(width: 6),
                    Text(label,
                        style: const TextStyle(
                            color: AppColors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildVideoArea() {
    return Container(
      color: AppColors.darkSurface,
      child: Stack(
        fit: StackFit.expand,
        children: [
          LiveStageGrid(
            stage: _stage,
            myUserId: _myId,
            selectedId: _recipient()?.id,
            onTapTile: _selectRecipient,
            onRemoveGuest: _removeGuest,
          ),
          IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.45),
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black.withOpacity(0.35),
                  ],
                  stops: const [0.0, 0.22, 0.65, 1.0],
                ),
              ),
            ),
          ),
          Positioned(top: 10, left: 10, right: 10, child: _buildHeader()),
          // Join request cards on the right side.
          if (_requests.isNotEmpty)
            Positioned(top: 58, right: 10, child: _buildRequestCards()),
          Positioned(
            left: 10,
            right: 10,
            bottom: 10,
            height: 150,
            child: Row(
              children: [
                Expanded(child: LiveCommentList(comments: _comments)),
                if (_fullScreen)
                  GestureDetector(
                    onTap: _toggleFullScreen,
                    child: Container(
                      width: 44,
                      height: 44,
                      margin: const EdgeInsets.only(left: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.fullscreen_exit_rounded,
                          color: AppColors.white),
                    ),
                  ),
              ],
            ),
          ),
          // Flower gifts floating up (from the real socket events).
          Positioned.fill(
            child: IgnorePointer(
              child: Stack(
                children: [
                  for (final flower in _flowers)
                    FlowerFloat(
                      key: ValueKey(flower.id),
                      event: flower,
                      onDone: () => _set(() => _flowers.remove(flower)),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Flexible(
          child: Container(
            padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.45),
              borderRadius: BorderRadius.circular(30),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                UserAvatar(url: _myAvatar, name: _myName, radius: 16),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    _myName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppColors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primaryPink,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text('LIVE',
                      style: TextStyle(
                          color: AppColors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w900)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        _pill(Icons.remove_red_eye_rounded, AppColors.white,
            formatCompactCount(_viewerCount)),
        const SizedBox(width: 6),
        _pill(Icons.favorite_rounded, AppColors.primaryPink,
            formatCompactCount(_likeCount)),
      ],
    );
  }

  Widget _pill(IconData icon, Color color, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.45),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 4),
          Text(text,
              style: const TextStyle(
                  color: AppColors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // At most 3 cards are shown, the rest are counted.
  Widget _buildRequestCards() {
    final visible = _requests.take(3).toList();
    final more = _requests.length - visible.length;

    return SizedBox(
      width: 176,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final request in visible)
            _buildRequestCard(request),
          if (more > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text('+$more more requests',
                  style: const TextStyle(
                      color: AppColors.white, fontSize: 11)),
            ),
        ],
      ),
    );
  }

  Widget _buildRequestCard(JoinRequestModel request) {
    final name = _nameOf(request.user.fullName, request.user.username);
    final action = _processing[request.id];
    final busy = action != null;

    return Container(
      width: 176,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.darkSurface.withOpacity(0.92),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primaryPink.withOpacity(0.7)),
        boxShadow: [
          BoxShadow(
              color: AppColors.primaryPink.withOpacity(0.25), blurRadius: 12),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              UserAvatar(url: request.user.avatarUrl, name: name, radius: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppColors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold)),
                    const Text('wants to join',
                        style: TextStyle(
                            color: AppColors.softGrey, fontSize: 10)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _miniButton(
                  text: 'Reject',
                  color: AppColors.softGrey.withOpacity(0.25),
                  loading: action == 'reject',
                  disabled: busy,
                  onTap: () => _answerRequest(request, false),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _miniButton(
                  text: 'Approve',
                  color: AppColors.primaryPink,
                  loading: action == 'approve',
                  disabled: busy,
                  onTap: () => _answerRequest(request, true),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Fixed-size button: the typing dots replace the text, size stays the same.
  Widget _miniButton({
    required String text,
    required Color color,
    required bool loading,
    required bool disabled,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: Container(
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(15),
        ),
        child: loading
            ? const TypingDots(color: AppColors.white, dotSize: 4)
            : Text(text,
                style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold)),
      ),
    );
  }
}
