import '../model/transaction_model.dart';
import '../model/wallet_model.dart';
import 'api_service.dart';

// The backend is the only authority for balances. Nothing here changes a
// balance: reload with getWallet() after any purchase, gift or withdrawal.
class WalletService {
  static Future<WalletModel> getWallet() async {
    final response = await ApiService.get('/wallet');
    return WalletModel.fromJson(response['data']);
  }

  // [asset] is optional: "coins", "flowers" or "diamonds".
  static Future<List<TransactionModel>> getTransactions({
    String? asset,
    int page = 1,
    int perPage = 20,
  }) async {
    final query = <String, String>{
      'page': page.toString(),
      'per_page': perPage.toString(),
    };
    if (asset != null) {
      query['asset'] = asset;
    }

    final response = await ApiService.get('/wallet/transactions', query: query);

    List<TransactionModel> transactions = [];
    for (var item in response['data']['transactions']) {
      transactions.add(TransactionModel.fromJson(item));
    }
    return transactions;
  }

  // Current conversion settings. Keys: coins_per_flower, flowers_per_diamond,
  // diamonds_per_flower, usd_per_diamond (a string like "0.20"), max_participants.
  static Future<Map<String, dynamic>> getWalletRates() async {
    final response = await ApiService.get('/wallet/rates');
    return response['data'];
  }
}
