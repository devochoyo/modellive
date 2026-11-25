import 'package:flutter/material.dart';

import 'viewer_live_screen.dart';

// Home: a vertical live-stream feed, like a short-video feed. Swipe up/down to
// move between live streams. When nobody is live it shows "No live stream yet".
//
// [active] is false while another tab or screen is in front, so the stream
// that was being watched is left (video and sound stop).
class HomeScreen extends StatelessWidget {
  final bool active;

  const HomeScreen({super.key, this.active = true});

  @override
  Widget build(BuildContext context) {
    return ViewerLiveScreen(embedded: true, active: active);
  }
}
