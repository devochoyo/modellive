import 'user_model.dart';

// A live-stream comment (received with the "comment:new" WebSocket event).
class CommentModel {
  final int streamId;
  final UserModel user; // who wrote the comment
  final String text;
  final DateTime createdAt;

  CommentModel({
    required this.streamId,
    required this.user,
    required this.text,
    required this.createdAt,
  });

  factory CommentModel.fromJson(Map<String, dynamic> json) {
    return CommentModel(
      streamId: json['stream_id'],
      user: UserModel.fromJson(json['user']),
      text: json['text'],
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'stream_id': streamId,
      'user': user.toJson(),
      'text': text,
      'created_at': createdAt.toUtc().toIso8601String(),
    };
  }
}
