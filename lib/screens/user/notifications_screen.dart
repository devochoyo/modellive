import 'package:flutter/material.dart';

import '../../model/notification_model.dart';
import '../../service/api_service.dart';
import '../../service/notification_service.dart';
import '../../widget/common_widgets.dart';
import '../colors.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen>
    with WidgetsBindingObserver {
  static const int _perPage = 20;

  final ScrollController _scrollController = ScrollController();
  final List<NotificationModel> _items = [];
  final Set<int> _busyIds = {}; // notifications being marked as read

  int _page = 1;
  int _unreadCount = 0;
  bool _isLoading = true;
  bool _isRetrying = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  bool _markingAll = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    _loadNotifications().then((_) => _startListening());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    NotificationService.stopListening();
    _scrollController.dispose();
    super.dispose();
  }

  // Socket events are not replayed, so reload through REST when the app
  // comes back to the foreground.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_isLoading) {
      _loadNotifications();
      _startListening();
    }
  }

  // Real-time "notification:new" events (existing NotificationService socket).
  Future<void> _startListening() async {
    try {
      await NotificationService.listenForNotifications((notification) {
        if (!mounted) return;
        // Ignore an event we already have (no duplicates).
        if (_items.any((item) => item.id == notification.id)) return;
        setState(() {
          _items.insert(0, notification);
          if (!notification.isRead) _unreadCount++;
        });
      });
    } catch (_) {
      // Live updates are optional; pull-to-refresh still works.
    }
  }

  Future<void> _loadNotifications({bool retry = false}) async {
    if (retry) setState(() => _isRetrying = true);

    try {
      final result = await NotificationService.getNotifications(
          page: 1, perPage: _perPage);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(result.notifications);
        _unreadCount = result.unreadCount;
        _page = 1;
        _hasMore = result.notifications.length == _perPage;
        _errorMessage = null;
        _isLoading = false;
        _isRetrying = false;
      });
    } on ApiException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError('Could not load notifications. Please try again.');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
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
      final result = await NotificationService.getNotifications(
          page: _page + 1, perPage: _perPage);
      if (!mounted) return;
      setState(() {
        _page++;
        for (final n in result.notifications) {
          if (!_items.any((item) => item.id == n.id)) _items.add(n);
        }
        _hasMore = result.notifications.length == _perPage;
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

  void _showMessage(Object error) {
    final message =
        error is ApiException ? error.message : 'Something went wrong.';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // Marks one notification as read after the backend confirms it, then opens
  // a destination only when the type clearly maps to an existing screen.
  // The model has no sender or target ids, so nothing else is opened.
  void _openDestination(NotificationModel item) {
    String? route;
    if (item.type == 'new_message') route = '/chat-list';
    if (item.type == 'new_follower') route = '/friends';
    if (item.type == 'post_like' || item.type == 'post_comment') route = '/home';
    if (route == null) return;
    Navigator.pushNamedAndRemoveUntil(context, route, (r) => false);
  }

  Future<void> _onTapItem(NotificationModel item) async {
    if (_busyIds.contains(item.id)) return;
    if (item.isRead) {
      _openDestination(item);
      return;
    }
    setState(() => _busyIds.add(item.id));

    try {
      final updated = await NotificationService.markNotificationAsRead(
          notificationId: item.id);
      if (!mounted) return;
      setState(() {
        final index = _items.indexWhere((n) => n.id == item.id);
        if (index != -1) _items[index] = updated;
        if (_unreadCount > 0) _unreadCount--;
        _busyIds.remove(item.id);
      });
      _openDestination(item);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyIds.remove(item.id));
      _showMessage(e);
    }
  }

  Future<void> _markAllRead() async {
    if (_markingAll) return;
    setState(() => _markingAll = true);

    try {
      final unread = await NotificationService.markAllNotificationsAsRead();
      if (!mounted) return;
      setState(() {
        for (var i = 0; i < _items.length; i++) {
          final n = _items[i];
          _items[i] = NotificationModel(
            id: n.id,
            type: n.type,
            title: n.title,
            body: n.body,
            isRead: true,
            createdAt: n.createdAt,
          );
        }
        _unreadCount = unread;
        _markingAll = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _markingAll = false);
      _showMessage(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: AppColors.deepPink),
        title: const Text(
          'Notifications',
          style: TextStyle(
            color: AppColors.deepPink,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: SizedBox(
              width: 104,
              child: TextButton(
                onPressed:
                    (_markingAll || _unreadCount == 0) ? null : _markAllRead,
                child: _markingAll
                    ? const TypingDots(dotSize: 6)
                    : Text(
                        'Mark all read',
                        style: TextStyle(
                          color: _unreadCount == 0
                              ? AppColors.softGrey
                              : AppColors.primaryPink,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const LoadingView(message: 'Loading notifications...');
    }
    if (_errorMessage != null) {
      return ErrorRetryView(
        message: _errorMessage!,
        retrying: _isRetrying,
        onRetry: () => _loadNotifications(retry: true),
      );
    }
    if (_items.isEmpty) {
      return RefreshIndicator(
        color: AppColors.primaryPink,
        onRefresh: _loadNotifications,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: SizedBox(
              height: constraints.maxHeight,
              child: const EmptyStateView(
                icon: Icons.notifications_none_rounded,
                title: "You're All Caught Up!",
                message:
                    "When something happens, you'll see your notifications here.",
              ),
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: AppColors.primaryPink,
      onRefresh: _loadNotifications,
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _items.length + 1,
        itemBuilder: (context, index) {
          if (index == _items.length) {
            return SizedBox(
              height: 56,
              child: _isLoadingMore ? const Center(child: TypingDots()) : null,
            );
          }
          return _buildRow(_items[index]);
        },
      ),
    );
  }

  // The API provides no sender picture, so an icon for the type is used.
  IconData _iconFor(String type) {
    switch (type) {
      case 'new_follower':
        return Icons.person_add_alt_1_rounded;
      case 'new_message':
        return Icons.chat_bubble_rounded;
      case 'join_request':
        return Icons.pan_tool_alt_rounded;
      case 'join_request_approved':
        return Icons.check_circle_rounded;
      case 'join_request_rejected':
        return Icons.cancel_rounded;
      case 'removed_from_stream':
        return Icons.videocam_off_rounded;
      case 'post_like':
        return Icons.favorite_rounded;
      case 'post_comment':
        return Icons.mode_comment_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  String _timeAgo(DateTime time) {
    final diff = DateTime.now().difference(time.toLocal());
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    final t = time.toLocal();
    return '${t.day}/${t.month}/${t.year}';
  }

  Widget _buildRow(NotificationModel item) {
    return InkWell(
      onTap: () => _onTapItem(item),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: item.isRead ? AppColors.white : AppColors.blushBackground,
          border: const Border(
            bottom: BorderSide(color: AppColors.softPink),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: const BoxDecoration(
                color: AppColors.softPink,
                shape: BoxShape.circle,
              ),
              child: Icon(_iconFor(item.type),
                  color: AppColors.primaryPink, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.darkBackground,
                      fontSize: 15,
                      fontWeight:
                          item.isRead ? FontWeight.w500 : FontWeight.bold,
                    ),
                  ),
                  if (item.body != null && item.body!.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      item.body!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.softGrey, fontSize: 13, height: 1.3),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    _timeAgo(item.createdAt),
                    style: const TextStyle(
                        color: AppColors.softGrey, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (!item.isRead)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: AppColors.primaryPink,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
