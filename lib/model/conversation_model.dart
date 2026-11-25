import 'message_model.dart';
import 'user_model.dart';

// One row in the chat list.
class ConversationModel {
  final int conversationId;
  final UserModel user; // the other person in the chat
  final MessageModel? lastMessage;
  final int unreadCount;
  final DateTime? lastMessageAt;

  ConversationModel({
    required this.conversationId,
    required this.user,
    this.lastMessage,
    required this.unreadCount,
    this.lastMessageAt,
  });

  factory ConversationModel.fromJson(Map<String, dynamic> json) {
    return ConversationModel(
      conversationId: json['conversation_id'],
      user: UserModel.fromJson(json['user']),
      lastMessage: json['last_message'] == null
          ? null
          : MessageModel.fromJson(json['last_message']),
      unreadCount: json['unread_count'] ?? 0,
      lastMessageAt: json['last_message_at'] == null
          ? null
          : DateTime.parse(json['last_message_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'conversation_id': conversationId,
      'user': user.toJson(),
      'last_message': lastMessage?.toJson(),
      'unread_count': unreadCount,
      'last_message_at': lastMessageAt?.toUtc().toIso8601String(),
    };
  }
}
