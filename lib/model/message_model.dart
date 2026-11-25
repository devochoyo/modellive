// A private message. Also used for the "last_message" inside a conversation,
// which only contains id, body, sender_id, status and created_at.
class MessageModel {
  final int id;
  final int? conversationId;
  final int senderId;
  final int? receiverId;
  final String body;
  final String status; // "sent", "delivered" or "read"
  final bool? isMine;
  final DateTime createdAt;
  final DateTime? deliveredAt;
  final DateTime? readAt;

  MessageModel({
    required this.id,
    this.conversationId,
    required this.senderId,
    this.receiverId,
    required this.body,
    required this.status,
    this.isMine,
    required this.createdAt,
    this.deliveredAt,
    this.readAt,
  });

  factory MessageModel.fromJson(Map<String, dynamic> json) {
    return MessageModel(
      id: json['id'],
      conversationId: json['conversation_id'],
      senderId: json['sender_id'],
      receiverId: json['receiver_id'],
      body: json['body'],
      status: json['status'],
      isMine: json['is_mine'],
      createdAt: DateTime.parse(json['created_at']),
      deliveredAt: json['delivered_at'] == null
          ? null
          : DateTime.parse(json['delivered_at']),
      readAt: json['read_at'] == null ? null : DateTime.parse(json['read_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'conversation_id': conversationId,
      'sender_id': senderId,
      'receiver_id': receiverId,
      'body': body,
      'status': status,
      'is_mine': isMine,
      'created_at': createdAt.toUtc().toIso8601String(),
      'delivered_at': deliveredAt?.toUtc().toIso8601String(),
      'read_at': readAt?.toUtc().toIso8601String(),
    };
  }
}
