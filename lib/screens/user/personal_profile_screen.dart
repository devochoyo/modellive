import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../model/profile_model.dart';
import '../../service/api_service.dart';
import '../../service/auth_service.dart';
import '../../service/profile_service.dart';
import '../../widget/common_widgets.dart';
import '../colors.dart';

// The logged-in user's own profile and account options.
// Open it with: Navigator.pushNamed(context, '/personal-profile')
class PersonalProfileScreen extends StatefulWidget {
  const PersonalProfileScreen({super.key});

  @override
  State<PersonalProfileScreen> createState() => _PersonalProfileScreenState();
}

class _PersonalProfileScreenState extends State<PersonalProfileScreen> {
  ProfileModel? _profile;
  bool _isLoading = true;
  bool _isRetrying = false;
  bool _isLoggingOut = false;
  bool _isUploadingAvatar = false;
  final ImagePicker _picker = ImagePicker();
  String? _errorMessage;

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
      final profile = await ProfileService.getMyProfile();
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
      _showLoadError('Could not load your profile. Please try again.');
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

  // Camera icon: pick a picture and upload it.
  Future<void> _pickAndUploadAvatar() async {
    if (_isUploadingAvatar) return;
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (picked == null || !mounted) return; // cancelled

      setState(() => _isUploadingAvatar = true);
      final updated = await ProfileService.uploadAvatar(filePath: picked.path);
      if (!mounted) return;
      setState(() {
        _profile = updated;
        _isUploadingAvatar = false;
      });
      _snack('Profile picture updated.');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _isUploadingAvatar = false);
      if (!e.sessionExpired) _snack(e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isUploadingAvatar = false);
      _snack('Could not upload the picture. Please try again.');
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // Tapping the picture itself shows it full screen.
  void _openFullScreenPhoto(ProfileModel profile) {
    final url = profile.avatarUrl;
    if (url == null || url.isEmpty) {
      _snack('You have not added a profile picture yet.');
      return;
    }
    Navigator.of(context).push(PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black,
      pageBuilder: (_, __, ___) => _FullScreenPhoto(url: url),
      transitionsBuilder: (_, animation, __, child) =>
          FadeTransition(opacity: animation, child: child),
    ));
  }

  Future<void> _confirmLogout() async {
    if (_isLoggingOut) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text(
            'Log Out?',
            style: TextStyle(
              color: AppColors.deepPink,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: const Text(
            'Are you sure you want to log out of your ModelLive account?',
            style: TextStyle(color: AppColors.darkBackground, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text(
                'Cancel',
                style: TextStyle(color: AppColors.softGrey, fontSize: 15),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text(
                'Logout',
                style: TextStyle(
                  color: AppColors.deepPink,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;
    _logout();
  }

  // AuthService.logout() deletes the stored tokens.
  Future<void> _logout() async {
    setState(() => _isLoggingOut = true);
    try {
      await AuthService.logout();
      if (!mounted) return;
      // Removes every earlier screen so Back cannot return to logged-in pages.
      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoggingOut = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not log out. Please try again.')),
      );
    }
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
          'My Profile',
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
    final followers =
        profile.followersDisplay ?? profile.followersCount.toString();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      child: Column(
        children: [
          _buildHeader(profile, followers),
          const SizedBox(height: 24),
          _buildOptionRow(
            icon: Icons.account_balance_wallet_rounded,
            title: 'Balance',
            subtitle: 'Manage your coins, diamonds and flowers.',
            onTap: () => Navigator.pushNamed(context, '/balance'),
          ),
          const SizedBox(height: 12),
          _buildOptionRow(
            icon: Icons.account_balance_rounded,
            title: 'Payout',
            subtitle: 'Withdraw your available diamond earnings.',
            onTap: () => Navigator.pushNamed(context, '/payout'),
          ),
          const SizedBox(height: 12),
          _buildOptionRow(
            icon: Icons.card_giftcard_rounded,
            title: 'Referrals',
            subtitle: 'Invite friends and earn coins.',
            onTap: () => Navigator.pushNamed(context, '/referrals'),
          ),
          const SizedBox(height: 12),
          _buildOptionRow(
            icon: Icons.notifications_rounded,
            title: 'Notifications',
            subtitle: 'See your latest updates.',
            onTap: () => Navigator.pushNamed(context, '/notifications'),
          ),
          const SizedBox(height: 12),
          _buildOptionRow(
            icon: Icons.logout_rounded,
            title: 'Logout',
            subtitle: 'Sign out of your account on this phone.',
            onTap: _confirmLogout,
            isLogout: true,
            busy: _isLoggingOut,
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar(ProfileModel profile) {
    const double size = 124;
    final url = profile.avatarUrl;
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

    final circle = Container(
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
        child: ClipOval(
          child: Stack(
            alignment: Alignment.center,
            children: [
              picture,
              if (_isUploadingAvatar)
                Container(
                  width: size,
                  height: size,
                  color: Colors.black45,
                  child: const Center(
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                          strokeWidth: 3, color: AppColors.white),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Tap the picture: full screen.
        GestureDetector(
          onTap: () => _openFullScreenPhoto(profile),
          child: circle,
        ),
        // Tap the camera icon: choose a new picture.
        Positioned(
          right: 0,
          bottom: 4,
          child: GestureDetector(
            onTap: _pickAndUploadAvatar,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primaryPink,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.white, width: 3),
              ),
              child: const Icon(Icons.camera_alt_rounded,
                  color: AppColors.white, size: 20),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(ProfileModel profile, String followers) {
    final name = profile.fullName ?? profile.username;

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
          _buildAvatar(profile),
          const SizedBox(height: 16),
          Text(
            name,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.darkBackground,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$followers Followers',
            style: const TextStyle(color: AppColors.softGrey, fontSize: 15),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isLogout = false,
    bool busy = false,
  }) {
    final accent = isLogout ? AppColors.deepPink : AppColors.primaryPink;

    return GestureDetector(
      onTap: busy ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: isLogout ? AppColors.softPink : AppColors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: isLogout
              ? null
              : [
                  BoxShadow(
                    color: AppColors.primaryPink.withOpacity(0.10),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isLogout ? AppColors.white : AppColors.softPink,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: accent, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isLogout
                          ? AppColors.deepPink
                          : AppColors.darkBackground,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.softGrey,
                      fontSize: 13,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            busy
                ? const TypingDots(dotSize: 6)
                : Icon(Icons.chevron_right_rounded, color: accent, size: 28),
          ],
        ),
      ),
    );
  }
}

// Full-screen view of the profile picture. Pinch to zoom, tap or swipe to close.
class _FullScreenPhoto extends StatelessWidget {
  final String url;

  const _FullScreenPhoto({required this.url});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: Dismissible(
              key: const Key('full_screen_photo'),
              direction: DismissDirection.down,
              onDismissed: (_) => Navigator.of(context).pop(),
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: Center(
                    child: Image.network(
                      url,
                      fit: BoxFit.contain,
                      loadingBuilder: (context, child, progress) =>
                          progress == null
                              ? child
                              : const CircularProgressIndicator(
                                  color: AppColors.white),
                      errorBuilder: (context, error, stackTrace) =>
                          const Icon(Icons.broken_image_rounded,
                              color: AppColors.white, size: 64),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded,
                    color: AppColors.white, size: 30),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
