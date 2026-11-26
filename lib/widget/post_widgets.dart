import 'package:flutter/material.dart';

import '../model/live_stream_model.dart';
import '../model/post_model.dart';
import '../model/user_model.dart';
import '../screens/colors.dart';
import '../service/api_service.dart';
import '../service/post_service.dart';
import 'common_widgets.dart';

// =========================================================================
// Widgets of the Home feed: post card, picture grid, comments, live section.
// =========================================================================

// "now", "5m", "3h", "2d", "4w", then a date.
String timeAgo(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inSeconds < 45) return 'now';
  if (diff.inMinutes < 60) return '${diff.inMinutes <= 0 ? 1 : diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  if (diff.inDays < 7) return '${diff.inDays}d';
  if (diff.inDays < 30) return '${diff.inDays ~/ 7}w';
  final t = time.toLocal();
  return '${t.day}/${t.month}/${t.year}';
}

// =========================================================================
// PostController: the state of ONE post on the Home feed (likes + comments).
// The Home screen keeps one per post, so the state survives scrolling.
//
// Everything is "optimistic": the screen changes immediately and the request
// to the server runs in the background. If it fails, the change is undone (or,
// for a comment, marked "Failed - Retry").
// =========================================================================
class PostController extends ChangeNotifier {
  final PostModel post;
  UserModel me; // the logged-in user (shown on comments written by you)
  void Function(String message)? onMessage;

  final List<PostCommentModel> comments = []; // newest first
  bool loadingComments = false;
  bool commentsLoaded = false;
  bool hasMoreComments = false;
  String? commentsError;

  int _commentPage = 1;
  bool _likeBusy = false;
  bool _disposed = false;
  int _tempCounter = 0;

  PostController({required this.post, required this.me, this.onMessage});

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _tell(Object error, String fallback) {
    if (error is ApiException) {
      if (!error.sessionExpired) onMessage?.call(error.message);
    } else {
      onMessage?.call(fallback);
    }
  }

  // ---------- Like ----------

  Future<void> toggleLike() async {
    // 1. Change the screen right away.
    post.isLiked = !post.isLiked;
    post.likeCount += post.isLiked ? 1 : -1;
    if (post.likeCount < 0) post.likeCount = 0;
    notifyListeners();

    // 2. Tell the server in the background. Taps made while a request is
    // running are not lost: the loop sends the latest wish afterwards.
    if (_likeBusy) return;
    _likeBusy = true;
    try {
      while (true) {
        final want = post.isLiked;
        try {
          final count = want
              ? await PostService.likePost(postId: post.id)
              : await PostService.unlikePost(postId: post.id);
          if (post.isLiked == want) {
            post.likeCount = count;
            notifyListeners();
            break;
          }
          // The person tapped again meanwhile: send the new wish.
        } catch (e) {
          // Undo the change.
          post.isLiked = !want;
          post.likeCount += want ? -1 : 1;
          if (post.likeCount < 0) post.likeCount = 0;
          notifyListeners();
          _tell(e, 'Could not update your like.');
          break;
        }
      }
    } finally {
      _likeBusy = false;
    }
  }

  // ---------- Comments ----------

  Future<void> loadComments({bool more = false}) async {
    if (loadingComments) return;
    if (more && !hasMoreComments) return;
    loadingComments = true;
    commentsError = null;
    notifyListeners();
    try {
      final page = more ? _commentPage + 1 : 1;
      final result = await PostService.getComments(postId: post.id, page: page);
      if (more) {
        for (final c in result.comments) {
          if (!comments.any((x) => x.id == c.id)) comments.add(c);
        }
      } else {
        // Keep comments that are still being delivered from this phone.
        final local = comments.where((c) => c.id < 0).toList();
        comments
          ..clear()
          ..addAll(local)
          ..addAll(result.comments);
      }
      _commentPage = page;
      hasMoreComments = result.hasMore;
      commentsLoaded = true;
    } on ApiException catch (e) {
      if (!e.sessionExpired) commentsError = e.message;
    } catch (_) {
      commentsError = 'Could not load comments.';
    }
    loadingComments = false;
    notifyListeners();
  }

  // Shows the comment immediately and delivers it in the background.
  void sendComment(String text) {
    final clean = text.trim();
    if (clean.isEmpty) return;
    final temp = PostCommentModel(
      id: -(DateTime.now().microsecondsSinceEpoch + _tempCounter++),
      postId: post.id,
      user: me,
      text: clean,
      createdAt: DateTime.now().toUtc(),
      status: 'sending',
      animateIn: true,
    );
    comments.insert(0, temp);
    post.commentCount += 1;
    notifyListeners();
    _deliver(temp);
  }

  Future<void> _deliver(PostCommentModel temp) async {
    try {
      final saved =
          await PostService.addComment(postId: post.id, text: temp.text);
      temp.id = saved.id;
      temp.status = 'sent';
      notifyListeners();
    } catch (e) {
      temp.status = 'failed';
      post.commentCount = post.commentCount > 0 ? post.commentCount - 1 : 0;
      notifyListeners();
      _tell(e, 'Could not send your comment.');
    }
  }

  void retryComment(PostCommentModel comment) {
    if (comment.status != 'failed') return;
    comment.status = 'sending';
    post.commentCount += 1;
    notifyListeners();
    _deliver(comment);
  }

  void removeFailedComment(PostCommentModel comment) {
    comments.remove(comment);
    notifyListeners();
  }
}

// =========================================================================
// Post card: header, caption, pictures, like/comment row, comment box.
// =========================================================================
class PostCard extends StatefulWidget {
  final PostController controller;
  final VoidCallback onDelete;

  const PostCard({super.key, required this.controller, required this.onDelete});

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  bool _expanded = false;

  PostController get _c => widget.controller;
  PostModel get _post => _c.post;

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete post?'),
        content: const Text('This post will be removed for everyone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete',
                  style: TextStyle(color: AppColors.deepPink))),
        ],
      ),
    );
    if (ok == true) widget.onDelete();
  }

  void _openImages(int index) {
    Navigator.pushNamed(context, '/post-images',
        arguments: {'post': _post, 'index': index});
  }

  void _openProfile() {
    if (_post.isMine) return;
    Navigator.pushNamed(context, '/public-profile', arguments: _post.user);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final hasCaption = _post.caption.trim().isNotEmpty;
        final longCaption = _post.caption.length > 180 ||
            '\n'.allMatches(_post.caption).length > 3;
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          color: AppColors.white,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 6, 8),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: _openProfile,
                      child: UserAvatar(
                          url: _post.user.avatarUrl,
                          name: _post.user.username,
                          radius: 21),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GestureDetector(
                        onTap: _openProfile,
                        behavior: HitTestBehavior.opaque,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _post.user.fullName?.isNotEmpty == true
                                  ? _post.user.fullName!
                                  : _post.user.username,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                            Text(
                              '@${_post.user.username} · ${timeAgo(_post.createdAt)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: AppColors.softGrey, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_post.isMine)
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_horiz_rounded,
                            color: AppColors.softGrey),
                        onSelected: (_) => _confirmDelete(),
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                              value: 'delete', child: Text('Delete post')),
                        ],
                      )
                    else
                      const SizedBox(width: 8),
                  ],
                ),
              ),

              // Caption first, pictures below it
              if (hasCaption)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AnimatedSize(
                        duration: const Duration(milliseconds: 200),
                        alignment: Alignment.topCenter,
                        child: Text(
                          _post.caption,
                          maxLines: _expanded ? null : 5,
                          overflow: _expanded
                              ? TextOverflow.visible
                              : TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 15, height: 1.35),
                        ),
                      ),
                      if (longCaption)
                        GestureDetector(
                          onTap: () => setState(() => _expanded = !_expanded),
                          child: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              _expanded ? 'See less' : 'See more',
                              style: const TextStyle(
                                  color: AppColors.deepPink,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              if (_post.images.isNotEmpty)
                PostImageGrid(post: _post, onTap: _openImages),

              // Likes (left) and comments (right)
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 4, 6, 0),
                child: Row(
                  children: [
                    _LikeButton(
                      liked: _post.isLiked,
                      count: _post.likeCount,
                      onTap: _c.toggleLike,
                    ),
                    const Spacer(),
                    InkWell(
                      onTap: () => showPostComments(context, _c),
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        child: Row(
                          children: [
                            const Icon(Icons.mode_comment_outlined,
                                size: 22, color: Color(0xFF6B6270)),
                            const SizedBox(width: 6),
                            Text(
                              _post.commentCount == 0
                                  ? 'Comment'
                                  : '${formatCompactCount(_post.commentCount)} '
                                      '${_post.commentCount == 1 ? 'Comment' : 'Comments'}',
                              style: const TextStyle(
                                  color: Color(0xFF6B6270),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Quick comment box
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 2, 14, 12),
                child: CommentInputBar(onSend: _c.sendComment),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LikeButton extends StatelessWidget {
  final bool liked;
  final int count;
  final VoidCallback onTap;

  const _LikeButton(
      {required this.liked, required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              transitionBuilder: (child, animation) => ScaleTransition(
                scale: Tween<double>(begin: 0.5, end: 1).animate(
                    CurvedAnimation(parent: animation, curve: Curves.elasticOut)),
                child: child,
              ),
              child: Icon(
                liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                key: ValueKey(liked),
                size: 24,
                color: liked ? AppColors.primaryPink : const Color(0xFF6B6270),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              count == 0
                  ? 'Like'
                  : '${formatCompactCount(count)} ${count == 1 ? 'Like' : 'Likes'}',
              style: TextStyle(
                color: liked ? AppColors.deepPink : const Color(0xFF6B6270),
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =========================================================================
// Comment box: input field + send button. Sending clears the field at once.
// =========================================================================
class CommentInputBar extends StatefulWidget {
  final void Function(String text) onSend;
  final bool autofocus;

  const CommentInputBar({super.key, required this.onSend, this.autofocus = false});

  @override
  State<CommentInputBar> createState() => _CommentInputBarState();
}

class _CommentInputBarState extends State<CommentInputBar> {
  final TextEditingController _text = TextEditingController();

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _send() {
    final value = _text.text.trim();
    if (value.isEmpty) return;
    widget.onSend(value);
    _text.clear();
  }

  @override
  Widget build(BuildContext context) {
    final canSend = _text.text.trim().isNotEmpty;
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _text,
            autofocus: widget.autofocus,
            minLines: 1,
            maxLines: 4,
            maxLength: 500,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _send(),
            decoration: InputDecoration(
              hintText: 'Write a comment...',
              counterText: '',
              isDense: true,
              filled: true,
              fillColor: AppColors.blushBackground,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: canSend ? _send : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: canSend ? AppColors.primaryPink : AppColors.softPink,
            ),
            child: AnimatedScale(
              duration: const Duration(milliseconds: 200),
              scale: canSend ? 1.0 : 0.85,
              child: Icon(Icons.send_rounded,
                  size: 20,
                  color: canSend ? AppColors.white : AppColors.softGrey),
            ),
          ),
        ),
      ],
    );
  }
}

// =========================================================================
// Comments list (bottom sheet) for one post
// =========================================================================
Future<void> showPostComments(BuildContext context, PostController controller) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _CommentsSheet(controller: controller),
  );
}

class _CommentsSheet extends StatefulWidget {
  final PostController controller;

  const _CommentsSheet({required this.controller});

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  final ScrollController _scroll = ScrollController();

  PostController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    if (!_c.commentsLoaded) _c.loadComments();
    _scroll.addListener(() {
      if (_scroll.hasClients &&
          _scroll.position.pixels > _scroll.position.maxScrollExtent - 300) {
        _c.loadComments(more: true);
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _send(String text) {
    _c.sendComment(text);
    if (_scroll.hasClients) {
      _scroll.animateTo(0,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SizedBox(
        height: media.size.height * 0.78,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: AppColors.softPink,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(height: 12),
            AnimatedBuilder(
              animation: _c,
              builder: (_, __) => Text(
                _c.post.commentCount == 0
                    ? 'Comments'
                    : 'Comments (${formatCompactCount(_c.post.commentCount)})',
                style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: AppColors.deepPink),
              ),
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            Expanded(
              child: AnimatedBuilder(
                animation: _c,
                builder: (_, __) => _buildList(),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: EdgeInsets.fromLTRB(14, 10, 14, 10 + media.padding.bottom),
              child: CommentInputBar(onSend: _send),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    if (_c.comments.isEmpty) {
      if (_c.commentsError != null) {
        return ErrorRetryView(
          message: _c.commentsError!,
          retrying: _c.loadingComments,
          onRetry: _c.loadComments,
        );
      }
      if (!_c.commentsLoaded || _c.loadingComments) {
        return const LoadingView(message: 'Loading comments...');
      }
      return const EmptyStateView(
        icon: Icons.chat_bubble_outline_rounded,
        title: 'No comments yet',
        message: 'Be the first to comment on this post.',
      );
    }
    final extra = (_c.loadingComments || _c.commentsError != null) ? 1 : 0;
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      itemCount: _c.comments.length + extra,
      itemBuilder: (context, i) {
        if (i >= _c.comments.length) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: _c.commentsError != null
                  ? TextButton(
                      onPressed: () => _c.loadComments(more: true),
                      child: const Text('Could not load more. Tap to retry'))
                  : const TypingDots(color: AppColors.primaryPink),
            ),
          );
        }
        final comment = _c.comments[i];
        return _CommentTile(
          key: ValueKey(comment.uid),
          comment: comment,
          onRetry: () => _c.retryComment(comment),
          onRemove: () => _c.removeFailedComment(comment),
        );
      },
    );
  }
}

class _CommentTile extends StatelessWidget {
  final PostCommentModel comment;
  final VoidCallback onRetry;
  final VoidCallback onRemove;

  const _CommentTile({
    super.key,
    required this.comment,
    required this.onRetry,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final failed = comment.status == 'failed';
    final sending = comment.status == 'sending';
    final tile = Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UserAvatar(
              url: comment.user.avatarUrl,
              name: comment.user.username,
              radius: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Opacity(
                  opacity: sending ? 0.6 : 1,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      color: failed
                          ? const Color(0xFFFEE2E2)
                          : AppColors.blushBackground,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(comment.user.username,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(height: 2),
                        Text(comment.text,
                            style: const TextStyle(fontSize: 14, height: 1.3)),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 6, top: 3),
                  child: failed
                      ? Row(
                          children: [
                            GestureDetector(
                              onTap: onRetry,
                              child: const Text('Not sent. Tap to retry',
                                  style: TextStyle(
                                      color: Color(0xFFDC2626),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600)),
                            ),
                            const SizedBox(width: 12),
                            GestureDetector(
                              onTap: onRemove,
                              child: const Text('Remove',
                                  style: TextStyle(
                                      color: AppColors.softGrey, fontSize: 12)),
                            ),
                          ],
                        )
                      : Text(sending ? 'Sending...' : timeAgo(comment.createdAt),
                          style: const TextStyle(
                              color: AppColors.softGrey, fontSize: 12)),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (!comment.animateIn) return tile;
    // A comment written just now slides in smoothly.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, (1 - t) * -14), child: child),
      ),
      child: tile,
    );
  }
}

// =========================================================================
// Pictures of a post, arranged like Facebook:
//   1 picture: full width (its own shape)   2: side by side
//   3: one big + two small                  4: 2 x 2
//   5 or more: 2 on top, 3 below, "+N" on the last one
// Tapping a picture opens the full-screen viewer at that picture.
// =========================================================================
class PostImageGrid extends StatelessWidget {
  final PostModel post;
  final void Function(int index) onTap;

  const PostImageGrid({super.key, required this.post, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final images = post.images;
    final n = images.length;
    if (n == 0) return const SizedBox.shrink();

    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      const g = 2.0; // gap between pictures

      Widget tile(int i, double tw, double th, {int extra = 0}) {
        return SizedBox(
          width: tw,
          height: th,
          child: GestureDetector(
            onTap: () => onTap(i),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Hero(
                  tag: 'post_${post.id}_img_$i',
                  child: _NetImage(url: images[i].url),
                ),
                if (extra > 0)
                  Container(
                    color: Colors.black54,
                    alignment: Alignment.center,
                    child: Text('+$extra',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
          ),
        );
      }

      const gapW = SizedBox(width: g);
      const gapH = SizedBox(height: g);

      if (n == 1) {
        return _SingleImage(
          url: images[0].url,
          tag: 'post_${post.id}_img_0',
          onTap: () => onTap(0),
        );
      }
      if (n == 2) {
        final tw = (w - g) / 2;
        return Row(children: [tile(0, tw, w * 0.75), gapW, tile(1, tw, w * 0.75)]);
      }
      if (n == 3) {
        final tw = (w - g) / 2;
        return Column(children: [
          tile(0, w, w * 0.62),
          gapH,
          Row(children: [tile(1, tw, w * 0.4), gapW, tile(2, tw, w * 0.4)]),
        ]);
      }
      if (n == 4) {
        final tw = (w - g) / 2;
        return Column(children: [
          Row(children: [tile(0, tw, tw), gapW, tile(1, tw, tw)]),
          gapH,
          Row(children: [tile(2, tw, tw), gapW, tile(3, tw, tw)]),
        ]);
      }
      final top = (w - g) / 2;
      final bottom = (w - 2 * g) / 3;
      return Column(children: [
        Row(children: [tile(0, top, top), gapW, tile(1, top, top)]),
        gapH,
        Row(children: [
          tile(2, bottom, bottom),
          gapW,
          tile(3, bottom, bottom),
          gapW,
          tile(4, bottom, bottom, extra: n - 5),
        ]),
      ]);
    });
  }
}

class _NetImage extends StatelessWidget {
  final String url;

  const _NetImage({required this.url});

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Container(color: AppColors.softPink);
      },
      errorBuilder: (context, error, stack) => Container(
        color: AppColors.softPink,
        alignment: Alignment.center,
        child: const Icon(Icons.broken_image_rounded, color: AppColors.softGrey),
      ),
    );
  }
}

// One picture shown in its own shape (not too tall, not too flat).
class _SingleImage extends StatefulWidget {
  final String url;
  final String tag;
  final VoidCallback onTap;

  const _SingleImage({required this.url, required this.tag, required this.onTap});

  @override
  State<_SingleImage> createState() => _SingleImageState();
}

class _SingleImageState extends State<_SingleImage> {
  double? _aspect;
  ImageStream? _stream;
  ImageStreamListener? _listener;

  @override
  void initState() {
    super.initState();
    final stream =
        NetworkImage(widget.url).resolve(ImageConfiguration.empty);
    final listener = ImageStreamListener((info, _) {
      if (mounted) {
        setState(() => _aspect = info.image.width / info.image.height);
      }
    }, onError: (_, __) {});
    stream.addListener(listener);
    _stream = stream;
    _listener = listener;
  }

  @override
  void dispose() {
    if (_listener != null) _stream?.removeListener(_listener!);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ratio = (_aspect ?? 1.2).clamp(0.75, 1.91).toDouble();
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedSize(
        duration: const Duration(milliseconds: 200),
        child: AspectRatio(
          aspectRatio: ratio,
          child: Hero(tag: widget.tag, child: _NetImage(url: widget.url)),
        ),
      ),
    );
  }
}

// =========================================================================
// "Live now" section: reel-style cards with a play button and a LIVE badge.
// =========================================================================
class LiveNowSection extends StatelessWidget {
  final List<LiveStreamModel> streams;
  final void Function(LiveStreamModel stream) onOpen;

  const LiveNowSection({super.key, required this.streams, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.only(top: 12, bottom: 14),
      color: AppColors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                _PulsingDot(color: Color(0xFFE11D48), size: 10),
                SizedBox(width: 8),
                Text('Live now',
                    style:
                        TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 226,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              itemCount: streams.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) =>
                  _LiveCard(stream: streams[i], onTap: () => onOpen(streams[i])),
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveCard extends StatelessWidget {
  final LiveStreamModel stream;
  final VoidCallback onTap;

  const _LiveCard({required this.stream, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final host = stream.host;
    final name = host?.username ?? 'Live';
    final avatar = host?.avatarUrl;
    final viewers = stream.viewerCountDisplay ?? stream.viewerCount.toString();

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: 142,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Background: the host's picture, or a rose gradient.
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.primaryPink, AppColors.purple],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  name.isEmpty ? '?' : name[0].toUpperCase(),
                  style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 64,
                      fontWeight: FontWeight.bold),
                ),
              ),
              if (avatar != null && avatar.isNotEmpty)
                Image.network(avatar,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink()),
              // Dark fade so the text is readable.
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0x33000000), Color(0x00000000), Color(0xCC000000)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0, 0.45, 1],
                  ),
                ),
              ),
              // Play button
              Center(
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.25),
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: const Icon(Icons.play_arrow_rounded,
                      color: Colors.white, size: 30),
                ),
              ),
              // LIVE badge (round-edged) and viewer count
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE11D48),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _PulsingDot(color: Colors.white, size: 6),
                      SizedBox(width: 4),
                      Text('LIVE',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5)),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.remove_red_eye_rounded,
                          color: Colors.white, size: 11),
                      const SizedBox(width: 3),
                      Text(viewers,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 10,
                right: 10,
                bottom: 10,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14)),
                    if ((stream.title ?? '').isNotEmpty)
                      Text(stream.title!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  final Color color;
  final double size;

  const _PulsingDot({required this.color, required this.size});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1).animate(_anim),
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}
