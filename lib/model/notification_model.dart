// An app notification.
// Types: new_follower, new_message, join_request, join_request_approved,
// join_request_rejected, removed_from_stream.
class NotificationModel {
  final int id;
  final String type;
  final String title;
  final String? body;
  final bool isRead;
  final DateTime createdAt;

  NotificationModel({
    required this.id,
    required this.type,
    required this.title,
    this.body,
    required this.isRead,
    required this.createdAt,
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    return NotificationModel(
      id: json['id'],
      type: json['type'],
      title: json['title'],
      body: json['body'],
      isRead: json['is_read'],
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'title': title,
      'body': body,
      'is_read': isRead,
      'created_at': createdAt.toUtc().toIso8601String(),
    };
  }
}
