import '../model/withdrawal_model.dart';
import 'api_service.dart';

// Only diamonds can be withdrawn. The backend checks balances, deducts diamonds
// and controls the status. This service never changes a status.
class PayoutService {
  // Keys: diamonds, usd_per_diamond, available_usd, has_payment_method,
  // payment_methods. When has_payment_method is false, show the
  // "Add Payment Method" form.
  static Future<Map<String, dynamic>> getPayoutSummary() async {
    final response = await ApiService.get('/payouts/summary');
    return response['data'];
  }

  // Keys: diamonds, usd_per_diamond, usd_amount, currency, exchange_rate,
  // local_amount (null when no exchange rate is set for that currency).
  static Future<Map<String, dynamic>> calculateWithdrawal({
    required int diamonds,
    String? currency,
  }) async {
    final query = <String, String>{'diamonds': diamonds.toString()};
    if (currency != null) {
      query['currency'] = currency;
    }

    final response = await ApiService.get('/payouts/calculate', query: query);
    return response['data'];
  }

  // The diamonds are taken from the wallet by the backend. Reload the wallet
  // afterwards. An insufficient balance throws an ApiException (402).
  static Future<({WithdrawalModel withdrawal, int diamondsLeft})>
      requestWithdrawal({
    required int diamonds,
    required int paymentMethodId,
  }) async {
    final response = await ApiService.post('/payouts/withdrawals', body: {
      'diamonds': diamonds,
      'payment_method_id': paymentMethodId,
    });
    final data = response['data'];

    return (
      withdrawal: WithdrawalModel.fromJson(data['withdrawal']),
      diamondsLeft: data['diamonds_left'] as int,
    );
  }

  // The README does not show the list's key; "withdrawals" is assumed.
  static Future<List<WithdrawalModel>> getWithdrawals({
    int page = 1,
    int perPage = 20,
  }) async {
    final response = await ApiService.get('/payouts/withdrawals', query: {
      'page': page.toString(),
      'per_page': perPage.toString(),
    });

    List<WithdrawalModel> withdrawals = [];
    for (var item in response['data']['withdrawals']) {
      withdrawals.add(WithdrawalModel.fromJson(item));
    }
    return withdrawals;
  }

  // The README does not show whether the object is inside "withdrawal", so
  // both are handled.
  static Future<WithdrawalModel> getWithdrawalDetails({
    required int withdrawalId,
  }) async {
    final response = await ApiService.get('/payouts/withdrawals/$withdrawalId');
    final data = response['data'];
    return WithdrawalModel.fromJson(data['withdrawal'] ?? data);
  }
}
