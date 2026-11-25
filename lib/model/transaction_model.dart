// One wallet transaction.
// Types: coin_purchase, flower_purchase, flower_sent, diamond_earned,
// withdrawal, withdrawal_refund.
class TransactionModel {
  final int id;
  final String type;
  final String asset; // "coins", "flowers" or "diamonds"
  final int amount; // negative when the balance went down
  final int balanceAfter;
  final String? reference;
  final String? description;
  final DateTime createdAt;

  TransactionModel({
    required this.id,
    required this.type,
    required this.asset,
    required this.amount,
    required this.balanceAfter,
    this.reference,
    this.description,
    required this.createdAt,
  });

  factory TransactionModel.fromJson(Map<String, dynamic> json) {
    return TransactionModel(
      id: json['id'],
      type: json['type'],
      asset: json['asset'],
      amount: json['amount'],
      balanceAfter: json['balance_after'],
      reference: json['reference'],
      description: json['description'],
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'asset': asset,
      'amount': amount,
      'balance_after': balanceAfter,
      'reference': reference,
      'description': description,
      'created_at': createdAt.toUtc().toIso8601String(),
    };
  }
}
