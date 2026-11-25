// A withdrawal request. Money values are strings in the API (e.g. "10.00"),
// so they are kept as strings here.
class WithdrawalModel {
  final int id;
  final int diamonds;
  final String usdPerDiamond;
  final String usdAmount;
  final String? localCurrency;
  final String? localAmount;
  final String status; // pending, approved, processing, completed, rejected
  final int? paymentMethodId;
  final String? adminNote;
  final DateTime createdAt;
  final DateTime? updatedAt;

  WithdrawalModel({
    required this.id,
    required this.diamonds,
    required this.usdPerDiamond,
    required this.usdAmount,
    this.localCurrency,
    this.localAmount,
    required this.status,
    this.paymentMethodId,
    this.adminNote,
    required this.createdAt,
    this.updatedAt,
  });

  factory WithdrawalModel.fromJson(Map<String, dynamic> json) {
    return WithdrawalModel(
      id: json['id'],
      diamonds: json['diamonds'],
      usdPerDiamond: json['usd_per_diamond'],
      usdAmount: json['usd_amount'],
      localCurrency: json['local_currency'],
      localAmount: json['local_amount'],
      status: json['status'],
      paymentMethodId: json['payment_method_id'],
      adminNote: json['admin_note'],
      createdAt: DateTime.parse(json['created_at']),
      updatedAt:
          json['updated_at'] == null ? null : DateTime.parse(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'diamonds': diamonds,
      'usd_per_diamond': usdPerDiamond,
      'usd_amount': usdAmount,
      'local_currency': localCurrency,
      'local_amount': localAmount,
      'status': status,
      'payment_method_id': paymentMethodId,
      'admin_note': adminNote,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt?.toUtc().toIso8601String(),
    };
  }
}
