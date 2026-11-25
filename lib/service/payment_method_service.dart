import '../model/payment_method_model.dart';
import 'api_service.dart';

// The backend only returns a masked account number. Nothing here is logged.
class PaymentMethodService {
  static const int maxPaymentMethods = 5; // backend limit

  // The README does not show the list's key; "payment_methods" is assumed.
  static Future<List<PaymentMethodModel>> getPaymentMethods() async {
    final response = await ApiService.get('/payouts/payment-methods');

    List<PaymentMethodModel> methods = [];
    for (var item in response['data']['payment_methods']) {
      methods.add(PaymentMethodModel.fromJson(item));
    }
    return methods;
  }

  // Country rules: US needs routingNumber, NG needs neither routingNumber nor
  // swiftCode, every other country needs swiftCode. The backend has the final say.
  static Future<PaymentMethodModel> addPaymentMethod({
    required String country,
    required String currency,
    required String accountName,
    required String bankName,
    required String accountNumber,
    String? routingNumber,
    String? swiftCode,
    Map<String, dynamic>? extraDetails,
    bool? isDefault,
  }) async {
    final countryCode = country.toUpperCase();

    final body = <String, dynamic>{
      'country': countryCode,
      'currency': currency,
      'account_name': accountName,
      'bank_name': bankName,
      'account_number': accountNumber,
    };

    if (countryCode == 'US') {
      if (routingNumber == null || routingNumber.isEmpty) {
        throw ApiException('A routing number is required for the US.',
            statusCode: 400);
      }
      body['routing_number'] = routingNumber;
    } else if (countryCode != 'NG') {
      if (swiftCode == null || swiftCode.isEmpty) {
        throw ApiException('A SWIFT code is required for this country.',
            statusCode: 400);
      }
      body['swift_code'] = swiftCode;
    }

    if (extraDetails != null) body['extra_details'] = extraDetails;
    if (isDefault != null) body['is_default'] = isDefault;

    // Maximum 5 payment methods per user.
    final existing = await getPaymentMethods();
    if (existing.length >= maxPaymentMethods) {
      throw ApiException('You can save at most $maxPaymentMethods payment methods.',
          statusCode: 400);
    }

    final response = await ApiService.post('/payouts/payment-methods', body: body);
    return _toPaymentMethod(response['data']);
  }

  // PUT /payouts/payment-methods/<id>. Only the fields you pass are sent.
  static Future<PaymentMethodModel> updatePaymentMethod({
    required int paymentMethodId,
    String? country,
    String? currency,
    String? accountName,
    String? bankName,
    String? accountNumber,
    String? routingNumber,
    String? swiftCode,
    Map<String, dynamic>? extraDetails,
    bool? isDefault,
  }) async {
    final body = <String, dynamic>{};
    if (country != null) body['country'] = country.toUpperCase();
    if (currency != null) body['currency'] = currency;
    if (accountName != null) body['account_name'] = accountName;
    if (bankName != null) body['bank_name'] = bankName;
    if (accountNumber != null) body['account_number'] = accountNumber;
    if (routingNumber != null) body['routing_number'] = routingNumber;
    if (swiftCode != null) body['swift_code'] = swiftCode;
    if (extraDetails != null) body['extra_details'] = extraDetails;
    if (isDefault != null) body['is_default'] = isDefault;

    final response =
        await ApiService.put('/payouts/payment-methods/$paymentMethodId', body: body);
    return _toPaymentMethod(response['data']);
  }

  // The README does not show whether the object is inside "payment_method",
  // so both are handled.
  static PaymentMethodModel _toPaymentMethod(Map<String, dynamic> data) {
    return PaymentMethodModel.fromJson(data['payment_method'] ?? data);
  }
}
