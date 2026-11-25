import 'dart:async';

import 'package:flutter/material.dart';

import '../../model/user_model.dart';
import '../../service/api_service.dart';
import '../../service/follow_service.dart';
import '../../service/user_service.dart';
import '../../widget/common_widgets.dart';
import '../colors.dart';

// Discover people, search them and follow / unfollow.
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  static const int _perPage = 20; // backend maximum is 50

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<UserModel> _users = [];

  // Follow state set by this screen after a successful API call.
  final Map<int, bool> _followOverride = {};
  final Map<int, int> _countOverride = {};
  final Set<int> _busyIds = {}; // users whose follow request is running

  Timer? _debounce;
  int _requestId = 0; // ignores answers of outdated searches
  int _page = 1;
  bool _isLoading = true;
  bool _isRetrying = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _errorMessage;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadUsers();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers({bool retry = false}) async {
    final myRequest = ++_requestId;
    if (retry) {
      setState(() => _isRetrying = true);
    } else {
      setState(() => _isLoading = true);
    }

    try {
      final users = await UserService.getUsers(
        search: _search,
        page: 1,
        perPage: _perPage,
      );
      if (!mounted || myRequest != _requestId) return;
      setState(() {
        _users
          ..clear()
          ..addAll(users);
        _page = 1;
        _hasMore = users.length == _perPage;
        _errorMessage = null;
        _isLoading = false;
        _isRetrying = false;
      });
    } on ApiException catch (e) {
      _showError(e.message, myRequest);
    } catch (_) {
      _showError('Could not load people. Please try again.', myRequest);
    }
  }

  void _showError(String message, int myRequest) {
    if (!mounted || myRequest != _requestId) return;
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
    final myRequest = _requestId;
    setState(() => _isLoadingMore = true);
    try {
      final users = await UserService.getUsers(
        search: _search,
        page: _page + 1,
        perPage: _perPage,
      );
      if (!mounted || myRequest != _requestId) return;
      setState(() {
        _page++;
        _users.addAll(users);
        _hasMore = users.length == _perPage;
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

  // Waits until the user stops typing before searching.
  void _onSearchChanged(String text) {
    setState(() {}); // shows or hides the clear icon
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _search = text.trim();
      _loadUsers();
    });
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchController.clear();
    _search = '';
    setState(() {});
    _loadUsers();
  }

  bool _isFollowing(UserModel user) =>
      _followOverride[user.id] ?? user.isFollowing ?? false;

  String _followersText(UserModel user) {
    final override = _countOverride[user.id];
    if (override != null) return '${_formatCount(override)} followers';
    if (user.followersDisplay != null) {
      return '${user.followersDisplay} followers';
    }
    return '${user.followersCount ?? 0} followers';
  }

  String _formatCount(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }

  // The screen changes only after the backend answered successfully.
  Future<void> _toggleFollow(UserModel user) async {
    if (_busyIds.contains(user.id)) return;
    setState(() => _busyIds.add(user.id));

    try {
      final result = _isFollowing(user)
          ? await FollowService.unfollowUser(userId: user.id)
          : await FollowService.followUser(userId: user.id);
      if (!mounted) return;
      setState(() {
        _followOverride[user.id] = result['is_following'] as bool;
        _countOverride[user.id] = result['followers_count'] as int;
        _busyIds.remove(user.id);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyIds.remove(user.id));
      final message =
          e is ApiException ? e.message : 'Could not update. Please try again.';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  void _openProfile(UserModel user) {
    Navigator.pushNamed(context, '/public-profile', arguments: user);
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Discover Friends',
            style: TextStyle(
              color: AppColors.deepPink,
              fontSize: 26,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Find interesting people and connect with them.',
            style: TextStyle(color: AppColors.softGrey, fontSize: 14),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search people',
              hintStyle:
                  const TextStyle(color: AppColors.softGrey, fontSize: 15),
              prefixIcon: const Icon(Icons.search_rounded,
                  color: AppColors.softGrey, size: 22),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded,
                          color: AppColors.softGrey, size: 20),
                      onPressed: _clearSearch,
                    ),
              filled: true,
              fillColor: AppColors.white,
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: AppColors.softPink),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide:
                    const BorderSide(color: AppColors.primaryPink, width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const LoadingView(message: 'Finding people...');
    if (_errorMessage != null) {
      return ErrorRetryView(
        message: _errorMessage!,
        retrying: _isRetrying,
        onRetry: () => _loadUsers(retry: true),
      );
    }
    if (_users.isEmpty) {
      return EmptyStateView(
        icon: Icons.people_outline_rounded,
        title: 'No People Found',
        message: _search.isEmpty
            ? 'Try another name or check back later to discover new people.'
            : 'No one matches "$_search". Try another name.',
      );
    }

    return RefreshIndicator(
      color: AppColors.primaryPink,
      onRefresh: _loadUsers,
      child: ListView.separated(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: _users.length + 1,
        separatorBuilder: (context, index) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (index == _users.length) {
            return SizedBox(
              height: 48,
              child: _isLoadingMore ? const Center(child: TypingDots()) : null,
            );
          }
          return _buildUserRow(_users[index]);
        },
      ),
    );
  }

  Widget _buildUserRow(UserModel user) {
    final name = user.fullName ?? user.username;
    final following = _isFollowing(user);
    final busy = _busyIds.contains(user.id);

    return Container(
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
          // Picture and name open the public profile.
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _openProfile(user),
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
                        const SizedBox(height: 2),
                        Text(
                          _followersText(user),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: AppColors.softGrey, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 104,
            height: 38,
            child: ElevatedButton(
              onPressed: busy ? null : () => _toggleFollow(user),
              style: ElevatedButton.styleFrom(
                elevation: 0,
                backgroundColor:
                    following ? AppColors.softPink : AppColors.primaryPink,
                disabledBackgroundColor:
                    following ? AppColors.softPink : AppColors.primaryPink,
                foregroundColor:
                    following ? AppColors.primaryPink : AppColors.white,
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(19),
                ),
              ),
              child: busy
                  ? TypingDots(
                      color: following ? AppColors.primaryPink : AppColors.white,
                      dotSize: 6,
                    )
                  : Text(
                      following ? 'Following' : 'Follow',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.bold),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
