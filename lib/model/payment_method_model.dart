// A saved payout payment method, as returned by the API.
// The API only returns a masked account number. To create a method, the
// service sends the full "account_number" itself (it is not stored here).
class PaymentMethodModel {
  final int id;
  final String country; // 2-letter code
  final String currency;
  final String accountName;
  final String bankName;
  final String accountNumberMasked; // e.g. "*****6789"
  final String? routingNumber;
  final String? swiftCode;
  final Map<String, dynamic>? extraDetails;
  final bool isDefault;

  PaymentMethodModel({
    required this.id,
    required this.country,
    required this.currency,
    required this.accountName,
    required this.bankName,
    required this.accountNumberMasked,
    this.routingNumber,
    this.swiftCode,
    this.extraDetails,
    required this.isDefault,
  });

  factory PaymentMethodModel.fromJson(Map<String, dynamic> json) {
    return PaymentMethodModel(
      id: json['id'],
      country: json['country'],
      currency: json['currency'],
      accountName: json['account_name'],
      bankName: json['bank_name'],
      accountNumberMasked: json['account_number_masked'],
      routingNumber: json['routing_number'],
      swiftCode: json['swift_code'],
      extraDetails: json['extra_details'],
      isDefault: json['is_default'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'country': country,
      'currency': currency,
      'account_name': accountName,
      'bank_name': bankName,
      'account_number_masked': accountNumberMasked,
      'routing_number': routingNumber,
      'swift_code': swiftCode,
      'extra_details': extraDetails,
      'is_default': isDefault,
    };
  }
}
