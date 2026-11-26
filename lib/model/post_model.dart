import 'live_stream_model.dart';
import 'user_model.dart';

// One picture of a post.
class PostImageModel {
  final int id;
  final String url;

  PostImageModel({required this.id, required this.url});

  factory PostImageModel.fromJson(Map<String, dynamic> json) {
    return PostImageModel(id: json['id'], url: json['url']);
  }
}

// A Home feed post. The counters and [isLiked] are not final because the
// screen updates them immediately when the person taps like or comments.
class PostModel {
  final int id;
  final UserModel user; // the author
  final String caption; // empty when the post is only pictures
  final List<PostImageModel> images;
  int likeCount;
  int commentCount;
  bool isLiked;
  final bool isMine;
  final DateTime createdAt;

  PostModel({
    required this.id,
    required this.user,
    required this.caption,
    required this.images,
    required this.likeCount,
    required this.commentCount,
    required this.isLiked,
    required this.isMine,
    required this.createdAt,
  });

  factory PostModel.fromJson(Map<String, dynamic> json) {
    final images = <PostImageModel>[];
    for (var item in (json['images'] ?? [])) {
      images.add(PostImageModel.fromJson(item));
    }
    return PostModel(
      id: json['id'],
      user: UserModel.fromJson(json['user']),
      caption: json['caption'] ?? '',
      images: images,
      likeCount: json['like_count'] ?? 0,
      commentCount: json['comment_count'] ?? 0,
      isLiked: json['is_liked'] ?? false,
      isMine: json['is_mine'] ?? false,
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}

// A comment on a post. [status] is "sending" or "failed" only for a comment
// that was just written on this phone and is still being delivered.
class PostCommentModel {
  int id; // negative while the comment only exists on this phone
  final String uid; // never changes, so the list item keeps its identity
  final int postId;
  final UserModel user;
  final String text;
  final DateTime createdAt;
  String status; // "sent", "sending" or "failed"
  final bool animateIn; // slide in smoothly (comments written just now)

  PostCommentModel({
    required this.id,
    required this.postId,
    required this.user,
    required this.text,
    required this.createdAt,
    this.status = 'sent',
    this.animateIn = false,
  }) : uid = 'c$id';

  factory PostCommentModel.fromJson(Map<String, dynamic> json) {
    return PostCommentModel(
      id: json['id'],
      postId: json['post_id'],
      user: UserModel.fromJson(json['user']),
      text: json['text'],
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}

// One row of the Home feed: either a post, or the "live now" section.
class FeedItem {
  final PostModel? post;
  final List<LiveStreamModel>? streams;

  FeedItem.post(PostModel this.post) : streams = null;
  FeedItem.live(List<LiveStreamModel> this.streams) : post = null;

  bool get isLiveSection => streams != null;
}
