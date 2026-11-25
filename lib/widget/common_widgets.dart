import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:videosdk/videosdk.dart'
    show Participant, RTCVideoRenderer, RTCVideoView, RTCVideoViewObjectFit;

import '../model/comment_model.dart';
import '../model/participant_model.dart';
import '../model/wallet_model.dart';
import '../screens/colors.dart';
import '../service/api_service.dart';
import '../service/diagnostics_service.dart';
import '../service/gift_service.dart';
import '../service/videosdk_service.dart';
import '../service/wallet_service.dart';

// Three rounded dots that bounce one after another (typing effect).
// Used instead of circular spinners everywhere in ModelLive.
class TypingDots extends StatefulWidget {
  final Color color;
  final double dotSize;

  const TypingDots({
    super.key,
    this.color = AppColors.primaryPink,
    this.dotSize = 9,
  });

  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            // Each dot is a little behind the one before it.
            final phase = (_controller.value - index * 0.15) % 1.0;
            final wave = phase < 0.5 ? math.sin(phase * 2 * math.pi) : 0.0;
            return Container(
              margin: EdgeInsets.symmetric(horizontal: widget.dotSize * 0.3),
              child: Transform.translate(
                offset: Offset(0, -wave * widget.dotSize * 0.8),
                child: Opacity(
                  opacity: 0.45 + wave * 0.55,
                  child: Container(
                    width: widget.dotSize,
                    height: widget.dotSize,
                    decoration: BoxDecoration(
                      color: widget.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

// Full-screen loading: dots in the center with a short message.
class LoadingView extends StatelessWidget {
  final String message;
  final bool dark;

  const LoadingView({super.key, required this.message, this.dark = false});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TypingDots(color: dark ? AppColors.white : AppColors.primaryPink),
          const SizedBox(height: 16),
          Text(
            message,
            style: const TextStyle(color: AppColors.softGrey, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

// A pink rounded button that shows the typing dots while [loading].
class PinkButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool loading;
  final double height;
  final double? width;

  const PinkButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.loading = false,
    this.height = 56,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: width,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryPink,
          disabledBackgroundColor: AppColors.primaryPink,
          foregroundColor: AppColors.white,
          elevation: 4,
          shadowColor: AppColors.primaryPink,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(height / 2),
          ),
        ),
        child: loading
            ? const TypingDots(color: AppColors.white)
            : Text(
                text,
                style: const TextStyle(
                  color: AppColors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }
}

// Friendly error message with a Retry button (dots while retrying).
class ErrorRetryView extends StatelessWidget {
  final String message;
  final bool retrying;
  final VoidCallback onRetry;

  const ErrorRetryView({
    super.key,
    required this.message,
    required this.retrying,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircleAvatar(
              radius: 36,
              backgroundColor: AppColors.softPink,
              child: Icon(Icons.wifi_off_rounded,
                  color: AppColors.primaryPink, size: 34),
            ),
            const SizedBox(height: 20),
            const Text(
              'Something went wrong',
              style: TextStyle(
                color: AppColors.deepPink,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppColors.softGrey, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 24),
            PinkButton(
              text: 'Retry',
              loading: retrying,
              onPressed: onRetry,
              height: 48,
              width: 160,
            ),
          ],
        ),
      ),
    );
  }
}

// Icon in a soft pink circle + title + description, for empty states.
class EmptyStateView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const EmptyStateView({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 112,
              height: 112,
              decoration: const BoxDecoration(
                color: AppColors.softPink,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: const BoxDecoration(
                    color: AppColors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: AppColors.primaryPink, size: 40),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.deepPink,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppColors.softGrey, fontSize: 15, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

// Round profile picture. Falls back to the first letter of the name.
class UserAvatar extends StatelessWidget {
  final String? url;
  final String name;
  final double radius;

  const UserAvatar({
    super.key,
    required this.url,
    required this.name,
    this.radius = 24,
  });

  @override
  Widget build(BuildContext context) {
    final letter = name.isEmpty ? '?' : name[0].toUpperCase();
    final fallback = CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.softPink,
      child: Text(
        letter,
        style: TextStyle(
          color: AppColors.deepPink,
          fontWeight: FontWeight.bold,
          fontSize: radius * 0.8,
        ),
      ),
    );

    if (url == null || url!.isEmpty) return fallback;

    return ClipOval(
      child: Image.network(
        url!,
        width: radius * 2,
        height: radius * 2,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => fallback,
      ),
    );
  }
}


// =========================================================================
// Live-stream widgets (shared by the Viewer and Host live screens)
// =========================================================================

// 999 -> 999, 1000 -> 1K, 10000 -> 10K, 1200000 -> 1.2M
String formatCompactCount(int n) {
  String shorten(double value, String suffix) {
    // Cut (not round) to one decimal so 1999 shows 1.9K, never 2K.
    final cut = (value * 10).floor() / 10;
    final text = cut == cut.roundToDouble()
        ? cut.toInt().toString()
        : cut.toStringAsFixed(1);
    return '$text$suffix';
  }

  if (n >= 1000000) return shorten(n / 1000000, 'M');
  if (n >= 1000) return shorten(n / 1000, 'K');
  return n.toString();
}

// Finds the real VideoSDK participant for a person on stage.
// Both live screens join the video room with the user's id as the display
// name, so the stage list from the backend can be matched to the video feeds.
Participant? findVideoParticipant(int userId, int? myUserId) {
  if (userId == myUserId) return VideoSdkService.localParticipant;
  for (final p in VideoSdkService.remoteParticipants) {
    if (p.displayName == userId.toString()) return p;
  }
  return null;
}

// Small circular dark button with an icon and a label (right-side actions).
class LiveActionButton extends StatelessWidget {
  final Widget icon;
  final String label;
  final VoidCallback? onTap;
  final bool busy;

  const LiveActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: busy ? null : onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.45),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: busy ? const TypingDots(color: AppColors.white, dotSize: 5) : icon,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// The people on stage as real video. 1 person fills the area, 2 sit side by
// side, 3 or more use a grid (up to 9 including the host).
class LiveStageGrid extends StatelessWidget {
  final List<ParticipantModel> stage;
  final int? myUserId;
  final int? selectedId; // the flower recipient (pink outline)
  final void Function(ParticipantModel person) onTapTile;
  // Host only: shows a remove button on guest tiles.
  final void Function(ParticipantModel guest)? onRemoveGuest;

  const LiveStageGrid({
    super.key,
    required this.stage,
    required this.myUserId,
    required this.selectedId,
    required this.onTapTile,
    this.onRemoveGuest,
  });

  @override
  Widget build(BuildContext context) {
    final people = stage.take(9).toList();
    if (people.isEmpty) return const SizedBox.shrink();

    if (people.length == 1) return _tile(people[0]);

    // Two people: two portrait 9:16 tiles side by side (like TikTok live),
    // centred in the area instead of two thin full-height strips.
    if (people.length == 2) {
      return LayoutBuilder(builder: (context, c) {
        const gap = 4.0;
        double w = (c.maxWidth - gap) / 2;
        double h = w * 16 / 9;
        if (h > c.maxHeight) {
          h = c.maxHeight;
          w = h * 9 / 16;
        }
        return Center(
          child: SizedBox(
            width: w * 2 + gap,
            height: h,
            child: Row(
              children: [
                SizedBox(width: w, height: h, child: _tile(people[0])),
                const SizedBox(width: gap),
                SizedBox(width: w, height: h, child: _tile(people[1])),
              ],
            ),
          ),
        );
      });
    }

    final columns = people.length <= 4 ? 2 : 3;
    final rows = <Widget>[];
    for (int start = 0; start < people.length; start += columns) {
      final cells = <Widget>[];
      for (int i = 0; i < columns; i++) {
        if (i > 0) cells.add(const SizedBox(width: 4));
        final index = start + i;
        cells.add(Expanded(
          child: index < people.length
              ? _tile(people[index])
              : const SizedBox.shrink(),
        ));
      }
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 4));
      rows.add(Expanded(child: Row(children: cells)));
    }
    return Column(children: rows);
  }

  Widget _tile(ParticipantModel person) {
    final isMe = person.id == myUserId;
    return _LiveTile(
      person: person,
      myUserId: myUserId,
      isMe: isMe,
      selected: person.id == selectedId,
      onTap: () => onTapTile(person),
      onRemove: (onRemoveGuest != null && person.role == 'guest' && !isMe)
          ? () => onRemoveGuest!(person)
          : null,
    );
  }
}

// Finds the camera feed of a person on stage and redraws when it appears or
// changes. It checks a few times a second because the VideoSDK stream can
// arrive after the tile was first drawn (which left "Camera off" showing).
class _LiveTile extends StatefulWidget {
  final ParticipantModel person;
  final int? myUserId;
  final bool isMe;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  const _LiveTile({
    required this.person,
    required this.myUserId,
    required this.isMe,
    required this.selected,
    required this.onTap,
    required this.onRemove,
  });

  @override
  State<_LiveTile> createState() => _LiveTileState();
}

class _LiveTileState extends State<_LiveTile> {
  Timer? _timer;
  RTCVideoRenderer? _renderer;
  bool _ready = false; // the renderer is really delivering frames
  String _info = 'no renderer';
  String _lastLogged = '';

  @override
  void initState() {
    super.initState();
    _scan(redraw: false);
    _timer = Timer.periodic(
        const Duration(milliseconds: 500), (_) => _scan(redraw: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // (frames are arriving, short description) for one renderer.
  // A closed renderer has no texture and no source, even though it can still
  // remember an old frame size, so those are checked too.
  (bool, String) _probe(RTCVideoRenderer? r) {
    if (r == null) return (false, 'null');
    try {
      final d = r as dynamic;
      final tex = d.textureId;
      final src = d.srcObject != null;
      final w = d.value.width;
      final h = d.value.height;
      // In this VideoSDK build the picture is drawn by a native view, so
      // textureId/srcObject stay null even when it works. A real frame size
      // is the reliable sign that frames are arriving.
      final ready = w is num && w > 0 && h is num && h > 0;
      return (ready, 'tex=$tex src=$src size=${w}x$h');
    } catch (e) {
      // Cannot inspect it: assume it works and let it draw.
      return (true, 'unreadable ($e)');
    }
  }

  // Looks at EVERY video stream of this person and keeps the one that is
  // really alive (a person can briefly have an old, closed stream too).
  void _scan({required bool redraw}) {
    final p = findVideoParticipant(widget.person.id, widget.myUserId);
    RTCVideoRenderer? best; // a live one, or else the first one found
    bool bestReady = false;
    final parts = <String>[];
    if (p != null) {
      for (final st in p.streams.values) {
        final kind = st.kind.toString().toLowerCase();
        if (!kind.contains('video')) {
          parts.add(kind);
          continue;
        }
        final r = st.renderer;
        final probe = _probe(r);
        parts.add('video(${probe.$2})');
        if (r == null) continue;
        if (probe.$1 && !bestReady) {
          best = r;
          bestReady = true;
        } else if (best == null) {
          best = r;
        }
      }
    }
    final info =
        p == null ? 'participant NOT FOUND' : (parts.isEmpty ? 'no streams' : parts.join(' | '));

    if (info != _lastLogged) {
      _lastLogged = info;
      Diagnostics.log('TILE', 'user=${widget.person.id} me=${widget.isMe} $info');
    }

    final changed = !identical(best, _renderer) ||
        bestReady != _ready ||
        (kDebugMode && info != _info);
    if (!changed) return;
    _renderer = best;
    _ready = bestReady;
    _info = info;
    if (redraw && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return _LiveTileView(
      person: widget.person,
      renderer: _renderer,
      ready: _ready,
      info: _info,
      isMe: widget.isMe,
      selected: widget.selected,
      onTap: widget.onTap,
      onRemove: widget.onRemove,
    );
  }
}

class _LiveTileView extends StatelessWidget {
  final ParticipantModel person;
  final RTCVideoRenderer? renderer;
  final bool ready; // frames are arriving
  final String info; // debug text
  final bool isMe;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  const _LiveTileView({
    required this.person,
    required this.renderer,
    required this.ready,
    required this.info,
    required this.isMe,
    required this.selected,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final name = (person.fullName != null && person.fullName!.isNotEmpty)
        ? person.fullName!
        : person.username;
    final renderer = this.renderer;

    return LayoutBuilder(builder: (context, constraints) {
      final tileHeight = constraints.maxHeight;
      return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              color: AppColors.darkSurface,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (renderer != null)
                    RTCVideoView(
                      renderer!,
                      key: ValueKey(renderer.hashCode),
                      mirror: isMe,
                      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    ),
                  // No camera yet, or the camera is connected but no picture
                  // has arrived: show the avatar instead of a black box.
                  if (!ready)
                    Container(
                      color: AppColors.darkSurface,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            UserAvatar(
                                url: person.avatarUrl, name: name, radius: 30),
                            const SizedBox(height: 8),
                            Text(
                              renderer == null
                                  ? 'Camera off'
                                  : 'Connecting camera...',
                              style: const TextStyle(
                                  color: AppColors.softGrey, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // Name label.
          Positioned(
            left: 8,
            bottom: 8,
            right: 8,
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  person.role == 'host' ? '$name · Host' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: AppColors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
          // Above the comment area and below the header / request cards.
          if (onRemove != null)
            Positioned(
              bottom: tileHeight > 230 ? 160 : 44,
              right: 6,
              child: GestureDetector(
                onTap: onRemove,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close_rounded,
                      color: AppColors.white, size: 18),
                ),
              ),
            ),
          // Rounded pink outline on the selected flower recipient.
          if (selected)
            IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.primaryPink, width: 3),
                ),
              ),
            ),
          if (selected)
            Positioned(
              top: 56, // below the header row
              left: 6,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: AppColors.primaryPink,
                  shape: BoxShape.circle,
                ),
                child:
                    Image.asset('asset/flower.png', width: 16, height: 16),
              ),
            ),
        ],
      ),
    );
    });
  }
}

// Transparent scrolling comments. The newest comment is at the bottom.
class LiveCommentList extends StatelessWidget {
  final List<CommentModel> comments;

  const LiveCommentList({super.key, required this.comments});

  @override
  Widget build(BuildContext context) {
    if (comments.isEmpty) return const SizedBox.shrink();

    return ShaderMask(
      // Older comments fade out at the top.
      shaderCallback: (rect) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.transparent, Colors.white],
        stops: [0.0, 0.25],
      ).createShader(rect),
      blendMode: BlendMode.dstIn,
      child: ListView.builder(
        reverse: true,
        padding: EdgeInsets.zero,
        itemCount: comments.length,
        itemBuilder: (context, index) {
          final comment = comments[comments.length - 1 - index];
          final name = (comment.user.fullName != null &&
                  comment.user.fullName!.isNotEmpty)
              ? comment.user.fullName!
              : comment.user.username;
          return Align(
            alignment: Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.fromLTRB(6, 5, 12, 5),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.35),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  UserAvatar(
                      url: comment.user.avatarUrl, name: name, radius: 13),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: AppColors.softPink,
                              fontSize: 12,
                              fontWeight: FontWeight.bold),
                        ),
                        Text(
                          comment.text,
                          style: const TextStyle(
                              color: AppColors.white, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// Comment text field + flower button + send button.
class LiveInputBar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onFlower;

  const LiveInputBar({
    super.key,
    required this.controller,
    required this.onSend,
    required this.onFlower,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            maxLength: 200,
            maxLines: 1,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => onSend(),
            style: const TextStyle(color: AppColors.white, fontSize: 14),
            buildCounter: (context,
                    {required currentLength,
                    required isFocused,
                    required maxLength}) =>
                null,
            decoration: InputDecoration(
              hintText: 'Say something...',
              hintStyle:
                  const TextStyle(color: AppColors.softGrey, fontSize: 14),
              filled: true,
              fillColor: AppColors.darkSurface,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(26),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: onFlower,
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppColors.darkSurface,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.primaryPink, width: 1.5),
            ),
            child: Padding(
              padding: const EdgeInsets.all(9),
              child: Image.asset('asset/flower.png'),
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: onSend,
          child: Container(
            width: 46,
            height: 46,
            decoration: const BoxDecoration(
              color: AppColors.primaryPink,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.send_rounded,
                color: AppColors.white, size: 21),
          ),
        ),
      ],
    );
  }
}

// ---------- Flower animation ----------

// One flower gift received through the "flower:new" socket event.
class FlowerEvent {
  final int id;
  final String senderName;
  final String? senderAvatar;
  final String recipientName;
  final int quantity;
  final double align; // -1 (left) .. 1 (right)

  FlowerEvent({
    required this.id,
    required this.senderName,
    required this.senderAvatar,
    required this.recipientName,
    required this.quantity,
    required this.align,
  });

  // [data] is the payload of LiveStreamService.onFlower():
  // gift_id, stream_id, quantity, sender, recipient, created_at.
  factory FlowerEvent.fromSocket(Map<String, dynamic> data, int counter) {
    String nameOf(dynamic user) {
      if (user is Map) {
        final full = user['full_name'];
        if (full is String && full.isNotEmpty) return full;
        final username = user['username'];
        if (username is String && username.isNotEmpty) return username;
      }
      return 'Someone';
    }

    final sender = data['sender'];
    final quantity = data['quantity'];
    return FlowerEvent(
      id: counter,
      senderName: nameOf(sender),
      senderAvatar: sender is Map ? sender['avatar_url'] as String? : null,
      recipientName: nameOf(data['recipient']),
      quantity: quantity is int ? quantity : 1,
      align: (math.Random().nextDouble() * 1.0) - 0.5,
    );
  }
}

// Floats a flower card upward, then calls [onDone].
class FlowerFloat extends StatefulWidget {
  final FlowerEvent event;
  final VoidCallback onDone;

  const FlowerFloat({super.key, required this.event, required this.onDone});

  @override
  State<FlowerFloat> createState() => _FlowerFloatState();
}

class _FlowerFloatState extends State<FlowerFloat>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3000),
  )..forward();

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) widget.onDone();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.event;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        final rise = Curves.easeOut.transform(t);
        final opacity = t < 0.75 ? 1.0 : (1 - t) / 0.25;
        return Align(
          alignment: Alignment(e.align, 0.75 - 1.5 * rise),
          child: Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: Transform.scale(
              scale: 0.85 + 0.15 * math.min(1.0, t * 5),
              child: child,
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
        decoration: BoxDecoration(
          color: AppColors.darkSurface.withOpacity(0.9),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: AppColors.primaryPink, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryPink.withOpacity(0.4),
              blurRadius: 16,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            UserAvatar(url: e.senderAvatar, name: e.senderName, radius: 18),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    e.senderName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppColors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'to ${e.recipientName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppColors.softPink, fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Image.asset('asset/flower.png', width: 34, height: 34),
            const SizedBox(width: 4),
            Text(
              '×${e.quantity}',
              style: const TextStyle(
                color: AppColors.gold,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------- Flower gift bottom sheet ----------

// Opens the "send flowers" sheet. Returns true when flowers were sent.
// The flower animation itself arrives through the socket (onFlower).
Future<bool?> showFlowerGiftSheet(
  BuildContext context, {
  required int streamId,
  required ParticipantModel recipient,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _FlowerGiftSheet(streamId: streamId, recipient: recipient),
  );
}

class _FlowerGiftSheet extends StatefulWidget {
  final int streamId;
  final ParticipantModel recipient;

  const _FlowerGiftSheet({required this.streamId, required this.recipient});

  @override
  State<_FlowerGiftSheet> createState() => _FlowerGiftSheetState();
}

class _FlowerGiftSheetState extends State<_FlowerGiftSheet> {
  static const List<int> _quickAmounts = [1, 2, 5, 10, 50];

  WalletModel? _wallet;
  bool _loadingWallet = true;
  bool _sending = false;
  int _quantity = 1;
  String? _message;
  // The same id is kept when a failed send is retried (see GiftService).
  String? _requestId;

  @override
  void initState() {
    super.initState();
    _loadWallet();
  }

  Future<void> _loadWallet() async {
    setState(() => _loadingWallet = true);
    try {
      final wallet = await WalletService.getWallet();
      if (!mounted) return;
      setState(() {
        _wallet = wallet;
        _loadingWallet = false;
        _message = null;
      });
    } on ApiException catch (e) {
      _walletFailed(e.message);
    } catch (_) {
      _walletFailed('Could not load your balance.');
    }
  }

  void _walletFailed(String message) {
    if (!mounted) return;
    setState(() {
      _loadingWallet = false;
      _message = message;
    });
  }

  void _setQuantity(int value) {
    setState(() {
      _quantity = value.clamp(1, 1000);
      _requestId = null; // a different gift
      _message = null;
    });
  }

  Future<void> _send() async {
    if (_sending) return;
    setState(() {
      _sending = true;
      _message = null;
    });
    _requestId ??= const Uuid().v4();
    try {
      final result = await GiftService.sendFlowerGift(
        streamId: widget.streamId,
        recipientId: widget.recipient.id,
        quantity: _quantity,
        requestId: _requestId,
      );
      if (!mounted) return;
      // Backend balance is the truth.
      setState(() => _sending = false);
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Flowers sent. You have ${result.flowersLeft} left.'),
      ));
    } on ApiException catch (e) {
      if (!mounted) return;
      // A network error keeps the request id so a retry is not charged twice.
      if (e.statusCode != 0) _requestId = null;
      setState(() {
        _sending = false;
        _message = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _message = 'Could not send flowers. Please try again.';
      });
    }
  }

  Future<void> _openBuyFlowers() async {
    await Navigator.pushNamed(context, '/buy-flowers');
    if (!mounted) return;
    _loadWallet();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.recipient;
    final name = (r.fullName != null && r.fullName!.isNotEmpty)
        ? r.fullName!
        : r.username;
    final wallet = _wallet;
    final notEnough = wallet != null && wallet.flowers < _quantity;

    return Container(
      padding: EdgeInsets.fromLTRB(
          20, 12, 20, 20 + MediaQuery.of(context).viewPadding.bottom),
      decoration: const BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.softGrey.withOpacity(0.5),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              UserAvatar(url: r.avatarUrl, name: name, radius: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Send flowers to',
                        style: TextStyle(
                            color: AppColors.softGrey, fontSize: 12)),
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              Image.asset('asset/flower.png', width: 44, height: 44),
            ],
          ),
          const SizedBox(height: 16),
          if (_loadingWallet)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: TypingDots(color: AppColors.primaryPink),
            )
          else if (wallet != null)
            Row(
              children: [
                _balanceChip(Icons.local_florist_rounded, AppColors.primaryPink,
                    '${wallet.flowers} flowers'),
                const SizedBox(width: 10),
                _balanceChip(Icons.monetization_on_rounded, AppColors.gold,
                    '${wallet.coins} coins'),
              ],
            ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _quickAmounts.map((amount) {
              final active = amount == _quantity;
              return GestureDetector(
                onTap: () => _setQuantity(amount),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: active
                        ? AppColors.primaryPink
                        : AppColors.darkBackground,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: active
                            ? AppColors.primaryPink
                            : AppColors.softGrey.withOpacity(0.4)),
                  ),
                  child: Text('×$amount',
                      style: const TextStyle(
                          color: AppColors.white,
                          fontWeight: FontWeight.bold)),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed:
                    _quantity > 1 ? () => _setQuantity(_quantity - 1) : null,
                icon: const Icon(Icons.remove_circle_outline_rounded),
                color: AppColors.white,
                disabledColor: AppColors.softGrey.withOpacity(0.4),
              ),
              SizedBox(
                width: 80,
                child: Text(
                  '×$_quantity',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: AppColors.gold,
                      fontSize: 26,
                      fontWeight: FontWeight.w900),
                ),
              ),
              IconButton(
                onPressed: () => _setQuantity(_quantity + 1),
                icon: const Icon(Icons.add_circle_outline_rounded),
                color: AppColors.white,
              ),
            ],
          ),
          if (_message != null) ...[
            const SizedBox(height: 6),
            Text(_message!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColors.primaryPink, fontSize: 13)),
          ],
          if (notEnough) ...[
            const SizedBox(height: 6),
            const Text('You do not have enough flowers for this gift.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.softGrey, fontSize: 13)),
            TextButton(
              onPressed: _openBuyFlowers,
              child: const Text('Get Flowers',
                  style: TextStyle(
                      color: AppColors.primaryPink,
                      fontWeight: FontWeight.bold)),
            ),
          ],
          const SizedBox(height: 10),
          PinkButton(
            text: 'Send ×$_quantity',
            width: double.infinity,
            loading: _sending,
            onPressed:
                (_loadingWallet || wallet == null || notEnough) ? null : _send,
          ),
        ],
      ),
    );
  }

  Widget _balanceChip(IconData icon, Color color, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.darkBackground,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 6),
          Text(text,
              style: const TextStyle(color: AppColors.white, fontSize: 13)),
        ],
      ),
    );
  }
}
