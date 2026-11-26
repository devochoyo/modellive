import 'dart:async';

import 'package:flutter/material.dart';

import '../../model/live_stream_model.dart';
import '../../model/notification_model.dart';
import '../../model/post_model.dart';
import '../../model/user_model.dart';
import '../../service/api_service.dart';
import '../../service/notification_service.dart';
import '../../service/post_service.dart';
import '../../service/profile_service.dart';
import '../../widget/common_widgets.dart';
import '../../widget/post_widgets.dart';
import '../colors.dart';

// Home: a social-media style feed.
//   * App bar: "ModelLive" on the left, notification bell on the right
//     (the bell is highlighted while there are unread notifications).
//   * Body: the suggested posts. The "Live now" section sits right after the
//     first post. Tap a live card to watch (the live viewer screen).
//   * Floating button: create a post.
//
// [active] is true while the Home tab is in front. The live viewer is no
// longer the Home screen: it opens from the live cards.
class HomeScreen extends StatefulWidget {
  final bool active;

  const HomeScreen({super.key, this.active = true});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ScrollController _scroll = ScrollController();
  final List<FeedItem> _items = [];
  final Map<int, PostController> _controllers = {}; // one per post id

  bool _loading = true; // first load
  bool _loadingMore = false;
  bool _hasMore = false;
  bool _retrying = false;
  String? _error;
  int _page = 1;
  DateTime? _lastLoaded;

  int _unread = 0;
  UserModel? _me;
  Timer? _unreadTimer;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _loadMe();
    _loadFeed();
    _refreshUnread();
    _listenForNotifications();
    // Safety net in case a live notification was missed.
    _unreadTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (widget.active) _refreshUnread();
    });
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.active && widget.active) {
      // The Home tab came back to the front.
      _refreshUnread();
      _listenForNotifications();
      final last = _lastLoaded;
      if (last != null &&
          DateTime.now().difference(last) > const Duration(minutes: 3)) {
        _loadFeed(silent: true);
      }
    }
  }

  @override
  void dispose() {
    _unreadTimer?.cancel();
    NotificationService.stopListening();
    _scroll.dispose();
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ---------- Who am I (shown on comments I write) ----------

  Future<void> _loadMe() async {
    try {
      final p = await ProfileService.getMyProfile();
      if (!mounted) return;
      _me = UserModel(
          id: p.id,
          username: p.username,
          fullName: p.fullName,
          avatarUrl: p.avatarUrl);
      for (final c in _controllers.values) {
        c.me = _me!;
      }
    } catch (_) {}
  }

  PostController _controllerFor(PostModel post) {
    return _controllers.putIfAbsent(
      post.id,
      () => PostController(
        post: post,
        me: _me ?? UserModel(id: 0, username: 'You'),
        onMessage: _snack,
      ),
    );
  }

  // ---------- Notifications (the bell) ----------

  Future<void> _refreshUnread() async {
    try {
      final result =
          await NotificationService.getNotifications(page: 1, perPage: 1);
      if (mounted) setState(() => _unread = result.unreadCount);
    } catch (_) {}
  }

  Future<void> _listenForNotifications() async {
    try {
      await NotificationService.listenForNotifications(
          (NotificationModel notification) {
        if (mounted && !notification.isRead) setState(() => _unread++);
      });
    } catch (_) {}
  }

  Future<void> _openNotifications() async {
    await Navigator.pushNamed(context, '/notifications');
    if (!mounted) return;
    // The notifications screen closes the live connection when it leaves.
    _listenForNotifications();
    _refreshUnread();
  }

  // ---------- Feed ----------

  Future<void> _loadFeed({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _loading = _items.isEmpty;
        _error = null;
      });
    }
    try {
      final result = await PostService.getFeed(page: 1);
      if (!mounted) return;
      final old = _controllers.values.toList();
      _controllers.clear();
      setState(() {
        _items
          ..clear()
          ..addAll(result.items);
        _hasMore = result.hasMore;
        _page = 1;
        _loading = false;
        _retrying = false;
        _error = null;
        _lastLoaded = DateTime.now();
      });
      // The old cards are gone after this frame; free their controllers.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final c in old) {
          c.dispose();
        }
      });
    } on ApiException catch (e) {
      if (!mounted || e.sessionExpired) return;
      setState(() {
        _loading = false;
        _retrying = false;
        if (_items.isEmpty) _error = e.message;
      });
      if (_items.isNotEmpty) _snack(e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _retrying = false;
        if (_items.isEmpty) _error = 'Could not load your feed.';
      });
    }
  }

  Future<void> _retry() async {
    setState(() => _retrying = true);
    await _loadFeed();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 700) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final result = await PostService.getFeed(page: _page + 1);
      if (!mounted) return;
      setState(() {
        // Skip posts that are already on the screen.
        final shown = {
          for (final item in _items)
            if (item.post != null) item.post!.id
        };
        for (final item in result.items) {
          if (item.isLiveSection) continue; // only the first page has it
          if (shown.contains(item.post!.id)) continue;
          _items.add(item);
        }
        _page += 1;
        _hasMore = result.hasMore;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  // ---------- Actions ----------

  Future<void> _createPost() async {
    final result = await Navigator.pushNamed(context, '/create-post');
    if (result is! PostModel || !mounted) return;
    setState(() {
      _items.insert(0, FeedItem.post(result));
      _loading = false;
      _error = null;
    });
    if (_scroll.hasClients) {
      _scroll.animateTo(0,
          duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
    }
  }

  void _openLive(LiveStreamModel stream) {
    Navigator.pushNamed(context, '/viewer-live', arguments: stream);
  }

  Future<void> _deletePost(PostModel post) async {
    final index = _items.indexWhere((i) => i.post?.id == post.id);
    if (index < 0) return;
    final removed = _items[index];
    setState(() => _items.removeAt(index));
    try {
      await PostService.deletePost(postId: post.id);
    } catch (e) {
      if (!mounted) return;
      setState(() => _items.insert(index.clamp(0, _items.length).toInt(), removed));
      _snack(e is ApiException ? e.message : 'Could not delete the post.');
    }
  }

  // ---------- Build ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.blushBackground,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 1,
        automaticallyImplyLeading: false,
        centerTitle: false,
        titleSpacing: 16,
        title: const _BrandTitle(),
        actions: [
          _BellButton(unread: _unread, onTap: _openNotifications),
          const SizedBox(width: 10),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createPost,
        tooltip: 'Create post',
        backgroundColor: AppColors.primaryPink,
        foregroundColor: AppColors.white,
        child: const Icon(Icons.edit_rounded),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const LoadingView(message: 'Loading your feed...');

    if (_error != null && _items.isEmpty) {
      return ErrorRetryView(
          message: _error!, retrying: _retrying, onRetry: _retry);
    }

    return RefreshIndicator(
      color: AppColors.primaryPink,
      onRefresh: () => _loadFeed(silent: true),
      child: _items.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 120),
                EmptyStateView(
                  icon: Icons.dynamic_feed_rounded,
                  title: 'Nothing here yet',
                  message:
                      'Be the first to share something. Tap the pink button to create a post.',
                ),
              ],
            )
          : ListView.builder(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(top: 8, bottom: 96),
              itemCount: _items.length + (_loadingMore ? 1 : 0),
              itemBuilder: (context, i) {
                if (i >= _items.length) {
                  return const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(
                        child: TypingDots(color: AppColors.primaryPink)),
                  );
                }
                final item = _items[i];
                if (item.isLiveSection) {
                  return LiveNowSection(
                    key: const ValueKey('live-now'),
                    streams: item.streams!,
                    onOpen: _openLive,
                  );
                }
                final post = item.post!;
                return PostCard(
                  key: ValueKey('post-${post.id}'),
                  controller: _controllerFor(post),
                  onDelete: () => _deletePost(post),
                );
              },
            ),
    );
  }
}

// "ModelLive" (one word), styled like the app icon: bold italic, "Model" in
// the dark colour and "Live" in pink.
class _BrandTitle extends StatelessWidget {
  const _BrandTitle();

  @override
  Widget build(BuildContext context) {
    return const Text.rich(
      TextSpan(
        children: [
          TextSpan(text: 'Model', style: TextStyle(color: Color(0xFF14091A))),
          TextSpan(text: 'Live', style: TextStyle(color: AppColors.primaryPink)),
        ],
      ),
      style: TextStyle(
        fontSize: 26,
        fontWeight: FontWeight.w900,
        fontStyle: FontStyle.italic,
        letterSpacing: -0.5,
      ),
    );
  }
}

// The notification bell. Plain while everything is read; highlighted (pink
// circle, filled ringing bell and a count badge) when something is unread.
class _BellButton extends StatelessWidget {
  final int unread;
  final VoidCallback onTap;

  const _BellButton({required this.unread, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final highlighted = unread > 0;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 48,
        height: 48,
        child: Stack(
          alignment: Alignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: highlighted ? AppColors.softPink : Colors.transparent,
                border: Border.all(
                  color: highlighted ? AppColors.primaryPink : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: Icon(
                  highlighted
                      ? Icons.notifications_active_rounded
                      : Icons.notifications_none_rounded,
                  key: ValueKey(highlighted),
                  size: 25,
                  color: highlighted
                      ? AppColors.primaryPink
                      : const Color(0xFF6B6270),
                ),
              ),
            ),
            Positioned(
              top: 3,
              right: 1,
              child: AnimatedScale(
                scale: highlighted ? 1 : 0,
                duration: const Duration(milliseconds: 250),
                curve: Curves.elasticOut,
                child: Container(
                  constraints:
                      const BoxConstraints(minWidth: 18, minHeight: 18),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: AppColors.deepPink,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: AppColors.white, width: 1.5),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    unread > 99 ? '99+' : unread.toString(),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
