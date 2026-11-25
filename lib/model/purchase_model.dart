// A coin purchase record (purchase history and the verify response).
class PurchaseModel {
  final int id;
  final String productId;
  final int coins;
  final String? orderId; // Google Play order id
  final String status; // e.g. "completed"
  final DateTime createdAt;

  PurchaseModel({
    required this.id,
    required this.productId,
    required this.coins,
    this.orderId,
    required this.status,
    required this.createdAt,
  });

  factory PurchaseModel.fromJson(Map<String, dynamic> json) {
    return PurchaseModel(
      id: json['id'],
      productId: json['product_id'],
      coins: json['coins'],
      orderId: json['order_id'],
      status: json['status'],
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'product_id': productId,
      'coins': coins,
      'order_id': orderId,
      'status': status,
      'created_at': createdAt.toUtc().toIso8601String(),
    };
  }
}
