import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../model/country_model.dart';
import '../colors.dart';

// The welcome slides shown the first time the app is opened.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  // Saved when the user finishes or skips, so main.dart can skip onboarding
  // next time.
  static const String doneKey = 'onboarding_done';

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  static const List<_SlideData> _slides = [
    _SlideData(
      image: 'asset/onboarding_1.png',
      title: 'Discover Live Moments',
      description:
          'Watch exciting live streams, meet amazing people, and enjoy real-time moments from around the world.',
    ),
    _SlideData(
      image: 'asset/onboarding_2.png',
      title: 'Connect With People',
      description:
          'Make new friends, follow your favorite creators, and enjoy meaningful conversations.',
    ),
    _SlideData(
      image: 'asset/onboarding_3.png',
      title: 'Share Love With Gifts',
      description:
          'Send beautiful flowers, support your favorite creators, and make every live moment special.',
    ),
    // Shows a globe illustration and the flag of every nation, not an image.
    _SlideData(
      title: 'Models From All Nations',
      description:
          'Meet talented hosts and models from every corner of the world, live on ModelLive.',
      showFlags: true,
    ),
  ];

  bool get _isLastPage => _currentPage == _slides.length - 1;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // Remembers that onboarding was seen, then opens the login screen.
  Future<void> _goToLogin() async {
    try {
      await const FlutterSecureStorage()
          .write(key: OnboardingScreen.doneKey, value: 'true');
    } catch (_) {
      // If saving fails the user will simply see onboarding again.
    }
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

  void _onNext() {
    if (_isLastPage) {
      _goToLogin();
    } else {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.blushBackground, AppColors.white],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildTopBar(),
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: _slides.length,
                  onPageChanged: (index) => setState(() => _currentPage = index),
                  itemBuilder: (context, index) => _slides[index].showFlags
                      ? _buildNationsSlide(_slides[index])
                      : _buildSlide(_slides[index]),
                ),
              ),
              _buildBottom(),
            ],
          ),
        ),
      ),
    );
  }

  // Skip on the right (no logo).
  Widget _buildTopBar() {
    return SizedBox(
      height: 56,
      child: Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.only(right: 12),
          child: TextButton(
            onPressed: _goToLogin,
            child: const Text(
              'Skip',
              style: TextStyle(
                color: AppColors.softGrey,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSlide(_SlideData slide) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Image.asset(slide.image!, fit: BoxFit.contain),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            slide.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.deepPink,
              fontSize: 26,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            slide.description,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.softGrey,
              fontSize: 15,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // The "all nations" slide: globe illustration, text, then every flag.
  Widget _buildNationsSlide(_SlideData slide) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const SizedBox(height: 8),
          _buildGlobeIllustration(),
          const SizedBox(height: 20),
          Text(
            slide.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.deepPink,
              fontSize: 26,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            slide.description,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.softGrey,
              fontSize: 15,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          // Tiny flags of all nations. Scrolls only on very small phones.
          Expanded(
            child: SingleChildScrollView(
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 4,
                runSpacing: 3,
                children: [
                  for (var country in CountryModel.all)
                    Text(country.flag, style: const TextStyle(fontSize: 13)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // A globe with three small badges around it (people, live video, favorites).
  Widget _buildGlobeIllustration() {
    Widget badge(IconData icon, Color color) {
      return Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryPink.withOpacity(0.25),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(icon, color: color, size: 24),
      );
    }

    return SizedBox(
      width: 190,
      height: 170,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 160,
            height: 160,
            decoration: const BoxDecoration(
              color: AppColors.softPink,
              shape: BoxShape.circle,
            ),
          ),
          Container(
            width: 112,
            height: 112,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.primaryPink, AppColors.purple],
              ),
            ),
            child: const Icon(Icons.public_rounded,
                color: AppColors.white, size: 66),
          ),
          Positioned(
            top: 4,
            left: 8,
            child: badge(Icons.person_rounded, AppColors.primaryPink),
          ),
          Positioned(
            top: 14,
            right: 2,
            child: badge(Icons.videocam_rounded, AppColors.purple),
          ),
          Positioned(
            bottom: 2,
            right: 22,
            child: badge(Icons.favorite_rounded, AppColors.deepPink),
          ),
        ],
      ),
    );
  }

  // Page indicators and the main button.
  Widget _buildBottom() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_slides.length, (index) {
              final isActive = index == _currentPage;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: isActive ? 24 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: isActive ? AppColors.primaryPink : AppColors.softPink,
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            }),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _onNext,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryPink,
                foregroundColor: AppColors.white,
                elevation: 4,
                shadowColor: AppColors.primaryPink,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
              child: Text(
                _isLastPage ? 'Get Started' : 'Next',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Text and image for one slide. The "all nations" slide has no image: it
// draws a globe and the flags instead (showFlags).
class _SlideData {
  final String? image;
  final String title;
  final String description;
  final bool showFlags;

  const _SlideData({
    this.image,
    required this.title,
    required this.description,
    this.showFlags = false,
  });
}