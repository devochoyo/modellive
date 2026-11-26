import 'package:flutter/material.dart';

import '../../model/post_model.dart';
import '../../widget/common_widgets.dart';
import '../colors.dart';

// Full-screen pictures of a post. Swipe left/right between pictures, pinch to
// zoom, tap to hide or show the text. Open it with:
//   Navigator.pushNamed(context, '/post-images',
//       arguments: {'post': postModel, 'index': 0})
class PostImageViewerScreen extends StatefulWidget {
  final PostModel post;
  final int initialIndex;

  const PostImageViewerScreen({
    super.key,
    required this.post,
    this.initialIndex = 0,
  });

  @override
  State<PostImageViewerScreen> createState() => _PostImageViewerScreenState();
}

class _PostImageViewerScreenState extends State<PostImageViewerScreen> {
  late final PageController _pages;
  late int _index;
  bool _showUi = true;

  PostModel get _post => widget.post;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, _post.images.length - 1).toInt();
    _pages = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasCaption = _post.caption.trim().isNotEmpty;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => setState(() => _showUi = !_showUi),
        child: Stack(
          fit: StackFit.expand,
          children: [
            PageView.builder(
              controller: _pages,
              itemCount: _post.images.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) {
                return InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: Center(
                    child: Hero(
                      tag: 'post_${_post.id}_img_$i',
                      child: Image.network(
                        _post.images[i].url,
                        fit: BoxFit.contain,
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) return child;
                          return const SizedBox(
                            height: 200,
                            child: LoadingView(message: '', dark: true),
                          );
                        },
                        errorBuilder: (context, error, stack) => const Icon(
                            Icons.broken_image_rounded,
                            color: Colors.white54,
                            size: 64),
                      ),
                    ),
                  ),
                );
              },
            ),

            // Top bar: close + "2 / 5"
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                ignoring: !_showUi,
                child: AnimatedOpacity(
                  opacity: _showUi ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xAA000000), Color(0x00000000)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 4),
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.close_rounded,
                                  color: Colors.white, size: 28),
                              onPressed: () => Navigator.pop(context),
                            ),
                            const Spacer(),
                            if (_post.images.length > 1)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 5),
                                decoration: BoxDecoration(
                                  color: Colors.black45,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Text(
                                  '${_index + 1} / ${_post.images.length}',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600),
                                ),
                              ),
                            const SizedBox(width: 12),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Bottom: author, caption, counters
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                ignoring: !_showUi,
                child: AnimatedOpacity(
                  opacity: _showUi ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0x00000000), Color(0xCC000000)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                    child: SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 28, 16, 14),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                UserAvatar(
                                    url: _post.user.avatarUrl,
                                    name: _post.user.username,
                                    radius: 16),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _post.user.fullName?.isNotEmpty == true
                                        ? _post.user.fullName!
                                        : _post.user.username,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15),
                                  ),
                                ),
                              ],
                            ),
                            if (hasCaption) ...[
                              const SizedBox(height: 10),
                              Text(
                                _post.caption,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 14, height: 1.35),
                              ),
                            ],
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                const Icon(Icons.favorite_rounded,
                                    color: AppColors.primaryPink, size: 18),
                                const SizedBox(width: 5),
                                Text(formatCompactCount(_post.likeCount),
                                    style: const TextStyle(
                                        color: Colors.white70, fontSize: 13)),
                                const SizedBox(width: 18),
                                const Icon(Icons.mode_comment_outlined,
                                    color: Colors.white70, size: 18),
                                const SizedBox(width: 5),
                                Text(formatCompactCount(_post.commentCount),
                                    style: const TextStyle(
                                        color: Colors.white70, fontSize: 13)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
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
