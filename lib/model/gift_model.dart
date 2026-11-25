// A flower gift sent during a live stream.
class GiftModel {
  final int id;
  final int streamId;
  final int senderId;
  final int recipientId;
  final int quantity;
  final int diamondsEarned; // diamonds the recipient earned from this gift
  final DateTime createdAt;

  GiftModel({
    required this.id,
    required this.streamId,
    required this.senderId,
    required this.recipientId,
    required this.quantity,
    required this.diamondsEarned,
    required this.createdAt,
  });

  factory GiftModel.fromJson(Map<String, dynamic> json) {
    return GiftModel(
      id: json['id'],
      streamId: json['stream_id'],
      senderId: json['sender_id'],
      recipientId: json['recipient_id'],
      quantity: json['quantity'],
      diamondsEarned: json['diamonds_earned'],
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'stream_id': streamId,
      'sender_id': senderId,
      'recipient_id': recipientId,
      'quantity': quantity,
      'diamonds_earned': diamondsEarned,
      'created_at': createdAt.toUtc().toIso8601String(),
    };
  }
}
