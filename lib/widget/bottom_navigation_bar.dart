import 'package:flutter/material.dart';

import '../screens/colors.dart';
import '../screens/user/chat_list_screen.dart';
import '../screens/user/friends_screen.dart';
import '../screens/user/home_screen.dart';
import '../screens/user/personal_profile_screen.dart';

// The main screen after login. It keeps Home, Friends, Chat and Profile alive
// in an IndexedStack, so switching tabs does not create duplicate screens and
// keeps each tab's scroll position and data.
//
// Open it with: Navigator.pushNamed(context, '/home')
// (also '/friends', '/chat-list' and '/personal-profile' select a tab).
class MainScreen extends StatefulWidget {
  final int initialIndex; // 0 Home, 1 Friends, 2 Chat, 3 Profile

  const MainScreen({super.key, this.initialIndex = 0});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  late int _tab = widget.initialIndex; // screen index (not the bar position)
  bool _overlayOpen = false; // Go Live screen is in front of the tabs
  late final List<bool> _visited = List.generate(4, (i) => i == widget.initialIndex);

  void _selectTab(int tab) {
    setState(() {
      _tab = tab;
      _visited[tab] = true; // a tab is built the first time it is opened
    });
  }

  Widget _screenFor(int tab) {
    if (!_visited[tab]) return const SizedBox.shrink();
    switch (tab) {
      case 0:
        return HomeScreen(active: _tab == 0 && !_overlayOpen);
      case 1:
        return const FriendsScreen();
      case 2:
        return const ChatListScreen();
      default:
        return const PersonalProfileScreen();
    }
  }

  // Go Live is an action. Nothing is created here: the host screen only
  // creates the live stream after the user confirms below.
  Future<void> _onGoLive() async {
    final title = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => const _GoLiveSheet(),
    );
    if (title == null || !mounted) return; // cancelled
    // The Home feed leaves its stream while you broadcast (one video room at
    // a time), and comes back afterwards.
    setState(() => _overlayOpen = true);
    await Navigator.pushNamed(context, '/host-live',
        arguments: title.isEmpty ? null : title);
    if (mounted) setState(() => _overlayOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.blushBackground,
      body: IndexedStack(
        index: _tab,
        children: List.generate(4, _screenFor),
      ),
      bottomNavigationBar: AppBottomNavBar(
        currentIndex: _tab,
        onTabSelected: _selectTab,
        onGoLive: _onGoLive,
      ),
    );
  }
}

// Bottom sheet that asks for an optional title and confirms the broadcast.
class _GoLiveSheet extends StatefulWidget {
  const _GoLiveSheet();

  @override
  State<_GoLiveSheet> createState() => _GoLiveSheetState();
}

class _GoLiveSheetState extends State<_GoLiveSheet> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          24, 12, 24, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: AppColors.softPink,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Go Live',
              style: TextStyle(
                color: AppColors.deepPink,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Start your live broadcast now for people to join.',
              style: TextStyle(color: AppColors.softGrey, fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              maxLength: 60,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Live title (optional)',
                filled: true,
                fillColor: AppColors.blushBackground,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context, _controller.text.trim()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryPink,
                  foregroundColor: AppColors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                  ),
                ),
                child: const Text(
                  'Start Broadcasting',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel',
                    style: TextStyle(color: AppColors.softGrey)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// The five-item bar: Home, Friends, Go Live (center action), Chat, Profile.
// [currentIndex] is the screen index: 0 Home, 1 Friends, 2 Chat, 3 Profile.
class AppBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTabSelected;
  final VoidCallback onGoLive;

  const AppBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTabSelected,
    required this.onGoLive,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryPink.withOpacity(0.15),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false, // respects the phone's bottom safe area
        child: SizedBox(
          height: 72,
          child: Row(
            children: [
              _item(0, Icons.home_rounded, 'Home'),
              _item(1, Icons.people_alt_rounded, 'Friends'),
              _goLiveButton(),
              _item(2, Icons.chat_bubble_rounded, 'Chat'),
              _item(3, Icons.person_rounded, 'Profile'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _item(int tab, IconData icon, String label) {
    final selected = currentIndex == tab;
    final color = selected ? AppColors.primaryPink : AppColors.softGrey;
    return Expanded(
      child: InkWell(
        onTap: () => onTabSelected(tab),
        borderRadius: BorderRadius.circular(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
              decoration: BoxDecoration(
                color: selected ? AppColors.softPink : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: selected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _goLiveButton() {
    return Expanded(
      child: GestureDetector(
        onTap: onGoLive,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primaryPink, AppColors.deepPink],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryPink.withOpacity(0.5),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(Icons.videocam_rounded,
                  color: AppColors.white, size: 27),
            ),
            const SizedBox(height: 2),
            const Text(
              'Go Live',
              style: TextStyle(
                color: AppColors.deepPink,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
