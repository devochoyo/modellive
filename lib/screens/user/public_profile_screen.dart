import 'package:flutter/material.dart';

import '../../model/live_stream_model.dart';
import '../../model/profile_model.dart';
import '../../model/user_model.dart';
import '../../service/api_service.dart';
import '../../service/follow_service.dart';
import '../../service/profile_service.dart';
import '../../widget/common_widgets.dart';
import '../colors.dart';

// Another user's public profile.
// Open it with: Navigator.pushNamed(context, '/public-profile', arguments: user)
// where user is a UserModel (or just the user id as an int).
class PublicProfileScreen extends StatefulWidget {
  final int userId;

  const PublicProfileScreen({super.key, required this.userId});

  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  ProfileModel? _profile;
  bool _isLoading = true;
  bool _isRetrying = false;
  bool _isFollowBusy = false;
  String? _errorMessage;

  // Set only after a successful follow / unfollow response.
  bool? _followingOverride;
  int? _followersOverride;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile({bool retry = false}) async {
    setState(() {
      if (retry) {
        _isRetrying = true;
      } else {
        _isLoading = true;
      }
    });

    try {
      final profile =
          await ProfileService.getPublicProfile(userId: widget.userId);
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _errorMessage = null;
        _isLoading = false;
        _isRetrying = false;
      });
    } on ApiException catch (e) {
      _showLoadError(e.message);
    } catch (_) {
      _showLoadError('Could not load this profile. Please try again.');
    }
  }

  void _showLoadError(String message) {
    if (!mounted) return;
    setState(() {
      _errorMessage = message;
      _isLoading = false;
      _isRetrying = false;
    });
  }

  bool _isFollowing() => _followingOverride ?? _profile?.isFollowing ?? false;

  String _followersText() {
    if (_followersOverride != null) return _formatCount(_followersOverride!);
    return _profile!.followersDisplay ?? _profile!.followersCount.toString();
  }

  String _formatCount(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }

  String _nameOf(ProfileModel profile) => profile.fullName ?? profile.username;

  // The screen changes only after the backend answered successfully.
  Future<void> _toggleFollow() async {
    if (_isFollowBusy) return;
    setState(() => _isFollowBusy = true);

    try {
      final result = _isFollowing()
          ? await FollowService.unfollowUser(userId: widget.userId)
          : await FollowService.followUser(userId: widget.userId);
      if (!mounted) return;
      setState(() {
        _followingOverride = result['is_following'] as bool;
        _followersOverride = result['followers_count'] as int;
        _isFollowBusy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isFollowBusy = false);
      final message =
          e is ApiException ? e.message : 'Could not update. Please try again.';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  // The chat screen receives the other person as a UserModel.
  void _openChat() {
    final profile = _profile!;
    final user = UserModel(
      id: profile.id,
      username: profile.username,
      fullName: profile.fullName,
      avatarUrl: profile.avatarUrl,
    );
    Navigator.pushNamed(context, '/individual-chat', arguments: user);
  }

  // The viewer screen receives the LiveStreamModel. The profile's stream may
  // not include the host, so the profile owner is added as the host.
  void _openLiveStream() {
    final profile = _profile!;
    final stream = profile.liveStream!;
    final host = stream.host ??
        UserModel(
          id: profile.id,
          username: profile.username,
          fullName: profile.fullName,
          avatarUrl: profile.avatarUrl,
        );
    final streamWithHost = LiveStreamModel(
      id: stream.id,
      title: stream.title,
      status: stream.status,
      likeCount: stream.likeCount,
      viewerCount: stream.viewerCount,
      viewerCountDisplay: stream.viewerCountDisplay,
      maxParticipants: stream.maxParticipants,
      startedAt: stream.startedAt,
      host: host,
      participants: stream.participants,
    );
    Navigator.pushNamed(context, '/viewer-live', arguments: streamWithHost);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.blushBackground,
      appBar: AppBar(
        backgroundColor: AppColors.blushBackground,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: AppColors.deepPink),
        title: const Text(
          'Profile',
          style: TextStyle(
            color: AppColors.deepPink,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const LoadingView(message: 'Loading profile...');
    if (_errorMessage != null) {
      return ErrorRetryView(
        message: _errorMessage!,
        retrying: _isRetrying,
        onRetry: () => _loadProfile(retry: true),
      );
    }

    final profile = _profile!;
    if (profile.isBlocked == true) {
      return const EmptyStateView(
        icon: Icons.block_rounded,
        title: 'Profile Unavailable',
        message: 'This profile is not available.',
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(profile),
          const SizedBox(height: 28),
          _buildLiveSection(profile),
        ],
      ),
    );
  }

  Widget _buildAvatar(String? url) {
    const double size = 124;
    final fallback = Container(
      width: size,
      height: size,
      color: AppColors.softPink,
      child: const Icon(Icons.person_rounded,
          color: AppColors.primaryPink, size: 70),
    );

    Widget picture = fallback;
    if (url != null && url.isNotEmpty) {
      picture = Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => fallback,
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [AppColors.primaryPink, AppColors.purple],
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: const BoxDecoration(
          color: AppColors.white,
          shape: BoxShape.circle,
        ),
        child: ClipOval(child: picture),
      ),
    );
  }

  Widget _buildHeader(ProfileModel profile) {
    final isSelf = profile.isSelf == true;
    final following = _isFollowing();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryPink.withOpacity(0.10),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildAvatar(profile.avatarUrl),
          const SizedBox(height: 16),
          Text(
            _nameOf(profile),
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.darkBackground,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.softPink,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.people_alt_rounded,
                    color: AppColors.primaryPink, size: 18),
                const SizedBox(width: 6),
                Text(
                  '${_followersText()} Followers',
                  style: const TextStyle(
                    color: AppColors.deepPink,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          // Your own profile has no Follow / Message buttons.
          if (!isSelf) ...[
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(child: _buildMessageButton()),
                const SizedBox(width: 12),
                Expanded(child: _buildFollowButton(following)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMessageButton() {
    return SizedBox(
      height: 48,
      child: OutlinedButton.icon(
        onPressed: _openChat,
        icon: const Icon(Icons.chat_bubble_outline_rounded, size: 19),
        label: const Text(
          'Message',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primaryPink,
          backgroundColor: AppColors.white,
          side: const BorderSide(color: AppColors.primaryPink, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
      ),
    );
  }

  Widget _buildFollowButton(bool following) {
    return SizedBox(
      height: 48,
      child: ElevatedButton(
        onPressed: _isFollowBusy ? null : _toggleFollow,
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor:
              following ? AppColors.softPink : AppColors.primaryPink,
          disabledBackgroundColor:
              following ? AppColors.softPink : AppColors.primaryPink,
          foregroundColor: following ? AppColors.primaryPink : AppColors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
        child: _isFollowBusy
            ? TypingDots(
                color: following ? AppColors.primaryPink : AppColors.white,
                dotSize: 7,
              )
            : Text(
                following ? 'Following' : 'Follow',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }

  Widget _buildLiveSection(ProfileModel profile) {
    final stream = profile.liveStream;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(
                color: AppColors.softPink,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.live_tv_rounded,
                  color: AppColors.primaryPink, size: 19),
            ),
            const SizedBox(width: 10),
            const Text(
              'Live Stream',
              style: TextStyle(
                color: AppColors.darkBackground,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (stream == null) _buildOfflineCard() else _buildLiveCard(profile),
      ],
    );
  }

  Widget _buildOfflineCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.softPink, width: 1.5),
      ),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              color: AppColors.softPink,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.videocam_off_rounded,
                color: AppColors.primaryPink, size: 34),
          ),
          const SizedBox(height: 16),
          const Text(
            'No live stream. This person is not yet live.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.softGrey,
              fontSize: 15,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveCard(ProfileModel profile) {
    final stream = profile.liveStream!;
    final hostName = stream.host?.fullName ?? _nameOf(profile);
    final viewers =
        stream.viewerCountDisplay ?? stream.viewerCount.toString();
    final isLive = stream.status == null || stream.status == 'live';

    return GestureDetector(
      onTap: _openLiveStream,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.deepPink, AppColors.purple],
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.deepPink.withOpacity(0.30),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // LIVE badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: AppColors.deepPink,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isLive ? 'LIVE' : 'STARTING',
                        style: const TextStyle(
                          color: AppColors.deepPink,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                // Viewer count
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.white.withOpacity(0.22),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.remove_red_eye_rounded,
                          color: AppColors.white, size: 16),
                      const SizedBox(width: 5),
                      Text(
                        viewers,
                        style: const TextStyle(
                          color: AppColors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    color: AppColors.white,
                    shape: BoxShape.circle,
                  ),
                  child: UserAvatar(
                    url: profile.avatarUrl,
                    name: hostName,
                    radius: 26,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hostName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        (stream.title != null && stream.title!.isNotEmpty)
                            ? stream.title!
                            : 'is live right now',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.white.withOpacity(0.85),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.play_circle_fill_rounded,
                      color: AppColors.deepPink, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Watch Now',
                    style: TextStyle(
                      color: AppColors.deepPink,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
