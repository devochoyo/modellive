import 'dart:async';

import 'package:flutter/material.dart';

import '../../model/comment_model.dart';
import '../../model/live_stream_model.dart';
import '../../model/participant_model.dart';
import '../../service/api_service.dart';
import '../../service/diagnostics_service.dart';
import '../../service/follow_service.dart';
import '../../service/live_stream_service.dart';
import '../../service/profile_service.dart';
import '../../service/user_service.dart';
import '../../service/videosdk_service.dart';
import '../../widget/common_widgets.dart';
import '../colors.dart';

// Watch a live stream. Open it with:
//   Navigator.pushNamed(context, '/viewer-live', arguments: liveStreamModel)
// The stream (with its host) comes from the Home feed or a public profile.
// Swipe up/down to move to the next live stream.
//
// Order used for every stream (see LiveStreamService):
//   joinLiveStream -> connectSocket -> listeners -> joinStreamRoom -> VideoSDK
// Viewers join VideoSDK receive-only. Camera and microphone are only turned
// on after the backend says the host approved the request (role "guest").
//
// Embedded mode (used by the Home tab): there is no starting stream, the
// screen loads the live streams itself and shows "No live stream yet" when
// nobody is live. [active] is false while another tab (or the Go Live screen)
// is in front: the stream is left so video and sound stop.
class ViewerLiveScreen extends StatefulWidget {
  final LiveStreamModel? stream;
  final bool embedded;
  final bool active;

  const ViewerLiveScreen({
    super.key,
    this.stream,
    this.embedded = false,
    this.active = true,
  });

  @override
  State<ViewerLiveScreen> createState() => _ViewerLiveScreenState();
}

class _ViewerLiveScreenState extends State<ViewerLiveScreen> {
  final List<LiveStreamModel> _streams = [];
  final PageController _pageController = PageController();
  final TextEditingController _commentController = TextEditingController();

  int _index = 0; // the stream we are connected to (or connecting to)
  int _pageTarget = 0; // the page the swipe ended on
  int? _myId;

  // Connection steps run one after another, never at the same time.
  Future<void> _lock = Future.value();
  int _generation = 0; // old socket callbacks are ignored
  int? _activeStreamId; // the stream joined on the backend right now

  bool _connecting = true;
  bool _retrying = false;
  String? _error;

  // Embedded (Home feed) state.
  bool _feedLoading = true; // loading the list of live streams
  bool _paused = false; // another tab is in front
  Timer? _emptyTimer; // looks again for live streams while the feed is empty

  // State of the current stream.
  List<ParticipantModel> _stage = [];
  final List<CommentModel> _comments = [];
  final List<FlowerEvent> _flowers = [];
  int _flowerCounter = 0;
  int _viewerCount = 0;
  int _likeCount = 0;
  String _role = 'viewer';
  bool _requesting = false;
  bool _requestPending = false;
  int? _myRequestId;
  int? _selectedId; // flower recipient; null means the host
  bool _following = false;
  bool _followBusy = false;
  bool _liking = false;
  bool _blocking = false;
  final List<DateTime> _recentComments = [];

  @override
  void initState() {
    super.initState();
    if (widget.stream != null) _streams.add(widget.stream!);
    _paused = widget.embedded && !widget.active;
    VideoSdkService.onParticipantsChanged = _redraw;
    VideoSdkService.onStreamChanged = (id, kind, enabled) => _redraw();
    VideoSdkService.onError = (message) => _snack(message);
    if (widget.embedded) {
      if (!_paused) _lock = _lock.then((_) => _loadFeed());
      _emptyTimer = Timer.periodic(const Duration(seconds: 12), (_) {
        if (_streams.isEmpty && !_paused && !_feedLoading) {
          _lock = _lock.then((_) => _loadFeed(silent: true));
        }
      });
    } else {
      _lock = _lock.then((_) => _firstEnter());
    }
  }

  @override
  void didUpdateWidget(covariant ViewerLiveScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.embedded || oldWidget.active == widget.active) return;
    if (widget.active) {
      _lock = _lock.then((_) => _resumeFeed());
    } else {
      _lock = _lock.then((_) => _pauseFeed());
    }
  }

  // ---------- Home feed (embedded mode) ----------

  // Leaves the stream so camera/audio of other people stop playing.
  Future<void> _pauseFeed() async {
    if (_paused) return;
    _paused = true;
    await _leaveCurrent();
    LiveStreamService.disconnectSocket();
    _set(() => _connecting = false);
  }

  Future<void> _resumeFeed() async {
    if (!_paused) return;
    _paused = false;
    if (!mounted) return;
    await _loadFeed();
  }

  // Loads the live streams (excluding your own) and joins the first one.
  Future<void> _loadFeed({bool silent = false}) async {
    if (!mounted || _paused) return;
    if (!silent) _set(() => _feedLoading = true);
    try {
      if (_myId == null) {
        try {
          _myId = (await ProfileService.getMyProfile()).id;
        } catch (_) {}
      }
      final list = await LiveStreamService.getLiveStreams(page: 1, perPage: 20);
      if (!mounted || _paused) return;
      final others =
          list.where((s) => s.host == null || s.host!.id != _myId).toList();

      if (others.isEmpty) {
        await _leaveCurrent();
        _set(() {
          _streams.clear();
          _index = 0;
          _pageTarget = 0;
          _feedLoading = false;
          _connecting = false;
          _error = null;
        });
        return;
      }

      // Same list as before and already watching: nothing to do.
      final sameFirst = _streams.isNotEmpty &&
          _activeStreamId != null &&
          others.any((s) => s.id == _streams[_index].id);
      if (sameFirst) {
        _set(() {
          for (var s in others) {
            if (!_streams.any((item) => item.id == s.id)) _streams.add(s);
          }
          _feedLoading = false;
        });
        return;
      }

      _set(() {
        _streams
          ..clear()
          ..addAll(others);
        _index = 0;
        _pageTarget = 0;
        _feedLoading = false;
      });
      if (_pageController.hasClients) _pageController.jumpToPage(0);
      await _enter();
    } on ApiException catch (e) {
      if (e.sessionExpired) return;
      _set(() {
        _feedLoading = false;
        if (_streams.isEmpty) _error = e.message;
      });
    } catch (_) {
      _set(() {
        _feedLoading = false;
        if (_streams.isEmpty) _error = 'Could not load live streams.';
      });
    }
  }

  @override
  void dispose() {
    _emptyTimer?.cancel();
    VideoSdkService.onParticipantsChanged = null;
    VideoSdkService.onStreamChanged = null;
    VideoSdkService.onError = null;
    _commentController.dispose();
    _pageController.dispose();
    // Leave the stream, then close the one shared socket.
    _lock = _lock
        .then((_) => _leaveCurrent())
        .whenComplete(() => LiveStreamService.disconnectSocket());
    super.dispose();
  }

  // ---------- Small helpers ----------

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

  LiveStreamModel get _stream => _streams[_index];

  String _nameOf(String? fullName, String username) =>
      (fullName != null && fullName.isNotEmpty) ? fullName : username;

  // ---------- Entering and leaving streams ----------

  Future<void> _firstEnter() async {
    try {
      final me = await ProfileService.getMyProfile();
      _myId = me.id;
    } catch (_) {
      // Without our own id the screen still works; flowers to ourselves are
      // blocked by the backend as well.
    }
    await _enter();
    _loadMoreStreams();
  }

  // Other live streams the viewer can swipe to.
  Future<void> _loadMoreStreams() async {
    try {
      final list = await LiveStreamService.getLiveStreams(page: 1, perPage: 20);
      if (!mounted) return;
      setState(() {
        for (var s in list) {
          final exists = _streams.any((item) => item.id == s.id);
          if (!exists && s.host != null && s.host!.id != _myId) {
            _streams.add(s);
          }
        }
      });
    } catch (_) {
      // Swiping simply stays unavailable.
    }
  }

  Future<void> _enter() async {
    final stream = _stream;
    final generation = ++_generation;

    _set(() {
      _connecting = true;
      _retrying = false;
      _error = null;
      _stage = [];
      _comments.clear();
      _flowers.clear();
      _viewerCount = stream.viewerCount;
      _likeCount = stream.likeCount ?? 0;
      _role = 'viewer';
      _requesting = false;
      _requestPending = false;
      _myRequestId = null;
      _selectedId = null;
      _following = stream.host?.isFollowing ?? false;
      _commentController.clear();
    });

    try {
      await Diagnostics.beginSession('VIEWER');
      Diagnostics.log('VIEWER', 'joining stream ${stream.id} on the backend...');
      final joined = await LiveStreamService.joinLiveStream(streamId: stream.id);
      _activeStreamId = stream.id;

      await LiveStreamService.connectSocket();
      _registerListeners(generation);
      final info = await LiveStreamService.joinStreamRoom(streamId: stream.id);

      final details =
          await LiveStreamService.getLiveStreamDetails(streamId: stream.id);

      final role = joined.role ?? 'viewer';
      // A user who is already a guest publishes, so ask for permissions.
      if (role != 'viewer') {
        if (!await VideoSdkService.ensurePermissions()) {
          throw ApiException(VideoSdkService.permissionProblem ??
              'Camera and microphone permission are needed.');
        }
      } else if (!await VideoSdkService.ensureBluetoothPermission()) {
        throw ApiException(VideoSdkService.permissionProblem ??
            'Please allow "Nearby devices" for ModelLive in your phone settings.');
      }

      if (joined.roomId == null ||
          joined.participantId == null ||
          joined.token == null) {
        throw ApiException('The video room information is missing.');
      }
      await VideoSdkService.joinRoom(
        roomId: joined.roomId!,
        participantId: joined.participantId!,
        token: joined.token!,
        role: role,
        displayName: '${_myId ?? 0}',
      );
      Diagnostics.log('VIEWER', 'video room join requested');

      if (!_isCurrent(generation)) return;
      setState(() {
        _role = role;
        _stage = details.participants.isNotEmpty
            ? details.participants
            : _hostOnlyStage(stream);
        _viewerCount = (info['viewer_count'] as int?) ?? details.viewerCount;
        _likeCount = (info['like_count'] as int?) ?? details.likeCount ?? 0;
        _connecting = false;
      });
    } on ApiException catch (e) {
      await _enterFailed(e.message);
    } catch (e, st) {
      Diagnostics.log('VIEWER', 'enter FAILED (unexpected error): $e\n$st');
      await _enterFailed('Could not open this live stream.');
    }
  }

  Future<void> _enterFailed(String message) async {
    await Diagnostics.endSession('viewer enter failed: $message');
    await _leaveCurrent();
    if (!mounted) return;
    setState(() {
      _error = message;
      _connecting = false;
      _retrying = false;
    });
  }

  List<ParticipantModel> _hostOnlyStage(LiveStreamModel stream) {
    final host = stream.host;
    if (host == null) return [];
    return [
      ParticipantModel(
        id: host.id,
        username: host.username,
        fullName: host.fullName,
        avatarUrl: host.avatarUrl,
        role: 'host',
      ),
    ];
  }

  // Leaves the stream properly: socket room, backend, VideoSDK room.
  Future<void> _leaveCurrent() async {
    _generation++;
    final id = _activeStreamId;
    _activeStreamId = null;
    if (id == null) return;

    LiveStreamService.removeAllListeners();
    try {
      await LiveStreamService.leaveStreamRoom(streamId: id);
    } catch (_) {}
    try {
      await LiveStreamService.leaveLiveStream(streamId: id);
    } catch (_) {}
    await VideoSdkService.leaveRoom();
    await Diagnostics.endSession('viewer left normally');
  }

  void _retry() {
    setState(() => _retrying = true);
    _lock = _lock.then((_) => _enter());
  }

  // The swipe ended on a new page.
  void _switchTo(int newIndex) {
    if (newIndex == _index) return;
    _set(() {
      _index = newIndex;
      _connecting = true;
      _error = null;
    });
    _lock = _lock.then((_) async {
      // A later swipe replaced this one.
      if (newIndex != _index) return;
      await _leaveCurrent();
      if (!mounted || newIndex != _index) return;
      await _enter();
    });
  }

  // Leaves the current stream, removes it from the list and shows the next
  // one (or closes the screen when nothing is left).
  void _dropCurrentStream(String message) {
    _lock = _lock.then((_) async {
      await _leaveCurrent();
      if (!mounted) return;
      _snack(message);
      setState(() => _streams.removeAt(_index));
      if (_streams.isEmpty) {
        if (widget.embedded) {
          setState(() {
            _connecting = false;
            _error = null;
          });
        } else {
          Navigator.pop(context);
        }
        return;
      }
      if (_index >= _streams.length) _index = _streams.length - 1;
      _pageTarget = _index;
      final target = _index;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pageController.hasClients) _pageController.jumpToPage(target);
      });
      await _enter();
    });
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

    LiveStreamService.onStreamEnded(() {
      if (!_isCurrent(generation)) return;
      _dropCurrentStream('This live stream has ended.');
    });

    LiveStreamService.onJoinRequestUpdate((requestId, status) {
      if (!_isCurrent(generation)) return;
      if (_myRequestId != null && requestId != _myRequestId) return;
      if (status == 'approved') {
        _becomeGuest(generation);
      } else if (status == 'rejected') {
        setState(() => _requestPending = false);
        _snack('The host declined your request.');
      }
    });

    // Removed from the stage: back to receive-only.
    LiveStreamService.onRemovedFromStage(() async {
      if (!_isCurrent(generation)) return;
      try {
        await VideoSdkService.updateRole('viewer');
      } catch (_) {}
      if (!_isCurrent(generation)) return;
      setState(() {
        _role = 'viewer';
        _requestPending = false;
      });
      _snack('You were removed from the stage.');
    });

    // Events are not stored, so reload the state after a reconnect.
    LiveStreamService.onReconnected(() async {
      if (!_isCurrent(generation)) return;
      try {
        final id = _stream.id;
        await LiveStreamService.joinLiveStream(streamId: id);
        await LiveStreamService.joinStreamRoom(streamId: id);
        final details =
            await LiveStreamService.getLiveStreamDetails(streamId: id);
        if (!_isCurrent(generation)) return;
        setState(() {
          if (details.participants.isNotEmpty) _stage = details.participants;
          _viewerCount = details.viewerCount;
        });
      } catch (_) {}
    });
  }

  // The host approved: ask the backend for the guest role, only then publish.
  Future<void> _becomeGuest(int generation) async {
    try {
      final joined =
          await LiveStreamService.joinLiveStream(streamId: _stream.id);
      final role = joined.role ?? 'viewer';
      if (role != 'guest' && role != 'host') {
        _set(() => _requestPending = false);
        return;
      }
      if (!await VideoSdkService.ensurePermissions()) {
        _set(() => _requestPending = false);
        _snack(VideoSdkService.permissionProblem ??
            'Camera and microphone permission are needed.');
        return;
      }
      await VideoSdkService.updateRole(role);
      if (!_isCurrent(generation)) return;
      setState(() {
        _role = role;
        _requestPending = false;
      });
      _snack('You are on stage!');
    } catch (e) {
      if (!_isCurrent(generation)) return;
      setState(() => _requestPending = false);
      _snack('Could not join the stage. Please try again.');
    }
  }

  // ---------- Actions ----------

  Future<void> _toggleFollow() async {
    final host = _stream.host;
    if (host == null || _followBusy) return;
    setState(() => _followBusy = true);
    try {
      final result = _following
          ? await FollowService.unfollowUser(userId: host.id)
          : await FollowService.followUser(userId: host.id);
      _set(() => _following = result['is_following'] == true);
    } on ApiException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('Could not update follow. Please try again.');
    } finally {
      _set(() => _followBusy = false);
    }
  }

  Future<void> _like() async {
    if (_liking) return;
    _liking = true;
    try {
      final count =
          await LiveStreamService.likeLiveStream(streamId: _stream.id);
      _set(() => _likeCount = count);
    } on ApiException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('Could not send your like.');
    } finally {
      _liking = false;
    }
  }

  Future<void> _requestToJoin() async {
    if (_role != 'viewer' || _requestPending || _requesting) return;
    setState(() => _requesting = true);
    try {
      final request =
          await LiveStreamService.requestToJoinLiveStream(streamId: _stream.id);
      _set(() {
        _myRequestId = request.id;
        _requestPending = request.status == 'pending';
      });
      _snack('Request sent. Waiting for the host.');
    } on ApiException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('Could not send your request. Please try again.');
    } finally {
      _set(() => _requesting = false);
    }
  }

  Future<void> _blockHost() async {
    final host = _stream.host;
    if (host == null || _blocking) return;
    final name = _nameOf(host.fullName, host.username);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.darkSurface,
        title: Text('Block $name?',
            style: const TextStyle(color: AppColors.white)),
        content: const Text(
          'You will leave this live and no longer see this person. '
          'You can unblock them later.',
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
            child: const Text('Block',
                style: TextStyle(
                    color: AppColors.primaryPink,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _blocking = true);
    try {
      // A real, account-wide block (not only for this stream).
      final blocked = await UserService.blockUser(userId: host.id);
      if (!blocked) {
        _snack('Could not block this user.');
        return;
      }
      _set(() => _blocking = false);
      _dropCurrentStream('$name was blocked.');
    } on ApiException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('Could not block this user. Please try again.');
    } finally {
      _set(() => _blocking = false);
    }
  }

  Future<void> _sendComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty || _activeStreamId == null) return;
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
      await LiveStreamService.sendComment(streamId: _stream.id, text: text);
    } on ApiException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('Could not send your comment.');
    }
  }

  // ---------- Flowers ----------

  int? get _hostId {
    for (var p in _stage) {
      if (p.role == 'host') return p.id;
    }
    return _stream.host?.id;
  }

  // The selected person, or the host when nobody was selected.
  ParticipantModel? _recipient() {
    final wanted = _selectedId ?? _hostId;
    for (var p in _stage) {
      if (p.id == wanted) return p;
    }
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
    final recipient = _recipient();
    if (recipient == null) {
      _snack('Tap a video to choose who receives your flowers.');
      return;
    }
    if (recipient.id == _myId) {
      _snack('You cannot send flowers to yourself.');
      return;
    }
    await showFlowerGiftSheet(context,
        streamId: _stream.id, recipient: recipient);
  }

  // ---------- Build ----------

  Widget _buildFeedMessage() {
    if (_feedLoading || _paused) {
      return Container(
        color: AppColors.darkBackground,
        child: const LoadingView(message: 'Finding live streams...', dark: true),
      );
    }
    if (_error != null) {
      return Container(
        color: AppColors.darkBackground,
        child: SafeArea(
          child: ErrorRetryView(
            message: _error!,
            retrying: _retrying,
            onRetry: () {
              setState(() {
                _retrying = true;
                _error = null;
              });
              _lock = _lock.then((_) => _loadFeed()).whenComplete(
                  () => _set(() => _retrying = false));
            },
          ),
        ),
      );
    }
    return Container(
      color: AppColors.darkBackground,
      width: double.infinity,
      child: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primaryPink,
          onRefresh: () {
            _lock = _lock.then((_) => _loadFeed(silent: true));
            return _lock;
          },
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: SizedBox(
                height: constraints.maxHeight,
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.videocam_off_rounded,
                          color: AppColors.softGrey, size: 64),
                      SizedBox(height: 16),
                      Text(
                        'No live stream yet',
                        style: TextStyle(
                          color: AppColors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded && (_streams.isEmpty || _paused || _feedLoading)) {
      return _buildFeedMessage();
    }
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: NotificationListener<ScrollEndNotification>(
        onNotification: (notification) {
          // Only the page swipe (not the comment list) changes the stream.
          if (notification.depth == 0 && _pageTarget != _index) {
            _switchTo(_pageTarget);
          }
          return false;
        },
        child: PageView.builder(
          scrollDirection: Axis.vertical,
          controller: _pageController,
          itemCount: _streams.length,
          onPageChanged: (page) => _pageTarget = page,
          itemBuilder: (context, i) => i == _index
              ? _buildCurrentPage()
              : _buildPreviewPage(_streams[i]),
        ),
      ),
    );
  }

  // A calm page shown while swiping to another stream.
  Widget _buildPreviewPage(LiveStreamModel stream) {
    final host = stream.host;
    final name = host == null ? 'Live' : _nameOf(host.fullName, host.username);
    return Container(
      color: AppColors.darkBackground,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            UserAvatar(url: host?.avatarUrl, name: name, radius: 46),
            const SizedBox(height: 14),
            Text(name,
                style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 18),
            const TypingDots(color: AppColors.primaryPink),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentPage() {
    if (_connecting) {
      return Container(
        color: AppColors.darkBackground,
        child: const LoadingView(message: 'Joining live...', dark: true),
      );
    }

    if (_error != null) {
      return Container(
        color: AppColors.darkBackground,
        child: SafeArea(
          child: Stack(
            children: [
              ErrorRetryView(
                message: _error!,
                retrying: _retrying,
                onRetry: _retry,
              ),
              if (!widget.embedded)
                Positioned(
                  top: 8,
                  right: 12,
                  child: _roundIconButton(
                      Icons.close_rounded, () => Navigator.pop(context)),
                ),
            ],
          ),
        ),
      );
    }

    return Container(
      color: AppColors.darkBackground,
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: _buildVideoArea(),
                ),
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
          ),
          // Soft shade so the header stays readable on bright video.
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
          // Comments: bottom-left, leaving room for the action buttons.
          Positioned(
            left: 10,
            right: 76,
            bottom: 10,
            height: 150,
            child: LiveCommentList(comments: _comments),
          ),
          Positioned(right: 10, bottom: 10, child: _buildActions()),
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
    final host = _stream.host;
    final name = host == null ? 'Live' : _nameOf(host.fullName, host.username);

    return Row(
      children: [
        Flexible(
          child: Container(
            padding: const EdgeInsets.fromLTRB(4, 4, 6, 4),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.45),
              borderRadius: BorderRadius.circular(30),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                UserAvatar(url: host?.avatarUrl, name: name, radius: 16),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppColors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 6),
                _buildFollowButton(),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.45),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.remove_red_eye_rounded,
                  color: AppColors.white, size: 15),
              const SizedBox(width: 4),
              Text(
                formatCompactCount(_viewerCount),
                style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        if (!widget.embedded) ...[
          const SizedBox(width: 8),
          _roundIconButton(Icons.close_rounded, () => Navigator.pop(context)),
        ],
      ],
    );
  }

  Widget _buildFollowButton() {
    return GestureDetector(
      onTap: _followBusy ? null : _toggleFollow,
      child: Container(
        height: 28,
        constraints: const BoxConstraints(minWidth: 62),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _following ? Colors.transparent : AppColors.primaryPink,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.primaryPink, width: 1.2),
        ),
        child: _followBusy
            ? const TypingDots(color: AppColors.white, dotSize: 4)
            : Text(
                _following ? 'Following' : 'Follow',
                style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold),
              ),
      ),
    );
  }

  Widget _roundIconButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.45),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: AppColors.white, size: 20),
      ),
    );
  }

  // Like, Request to Join, Block User.
  Widget _buildActions() {
    final isGuest = _role == 'guest';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LiveActionButton(
          icon: const Icon(Icons.favorite_rounded,
              color: AppColors.primaryPink, size: 26),
          label: formatCompactCount(_likeCount),
          onTap: _like,
        ),
        const SizedBox(height: 14),
        if (!isGuest) ...[
          LiveActionButton(
            icon: Icon(
              _requestPending
                  ? Icons.hourglass_top_rounded
                  : Icons.person_add_alt_1_rounded,
              color: _requestPending ? AppColors.gold : AppColors.white,
              size: 24,
            ),
            label: _requestPending ? 'Pending' : 'Join',
            busy: _requesting,
            onTap: _requestPending ? null : _requestToJoin,
          ),
          const SizedBox(height: 14),
        ],
        LiveActionButton(
          icon: const Icon(Icons.block_rounded,
              color: AppColors.white, size: 24),
          label: 'Block',
          busy: _blocking,
          onTap: _blockHost,
        ),
      ],
    );
  }
}
