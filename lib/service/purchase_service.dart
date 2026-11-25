import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

import '../model/coin_package_model.dart';
import '../model/purchase_model.dart';
import 'api_service.dart';

class PurchaseService {
  // =====================================================================
  // Backend (REST)
  // =====================================================================

  // The packages always come from the backend.
  static Future<List<CoinPackageModel>> getCoinPackages() async {
    final response = await ApiService.get('/purchases/coin-packages');

    List<CoinPackageModel> packages = [];
    for (var item in response['data']['packages']) {
      packages.add(CoinPackageModel.fromJson(item));
    }
    return packages;
  }

  // Asks the backend to check the purchase with Google Play. The backend
  // decides how many coins to add. Returns { purchase, coins_added,
  // duplicate, wallet }. Reload the wallet afterwards.
  static Future<Map<String, dynamic>> verifyCoinPurchase({
    required String productId,
    required String purchaseToken,
  }) async {
    final response = await ApiService.post('/purchases/coins/verify', body: {
      'product_id': productId,
      'purchase_token': purchaseToken,
    });
    return response['data'];
  }

  static Future<List<PurchaseModel>> getPurchaseHistory({
    int page = 1,
    int perPage = 20,
  }) async {
    final response = await ApiService.get('/purchases/history', query: {
      'page': page.toString(),
      'per_page': perPage.toString(),
    });

    List<PurchaseModel> purchases = [];
    for (var item in response['data']['purchases']) {
      purchases.add(PurchaseModel.fromJson(item));
    }
    return purchases;
  }

  // [payWith] is "coins" or "diamonds". The backend works out the cost.
  // Returns { flowers_bought, cost, paid_with, wallet }. A 402 error
  // (insufficient_coins / insufficient_diamonds) throws an ApiException.
  static Future<Map<String, dynamic>> purchaseFlowers({
    required int quantity,
    String payWith = 'coins',
  }) async {
    if (quantity < 1 || quantity > 10000) {
      throw ApiException('Quantity must be between 1 and 10000.',
          statusCode: 400);
    }
    if (payWith != 'coins' && payWith != 'diamonds') {
      throw ApiException('Pay with coins or diamonds.', statusCode: 400);
    }

    final response = await ApiService.post('/purchases/flowers', body: {
      'quantity': quantity,
      'pay_with': payWith,
    });
    return response['data'];
  }

  // =====================================================================
  // Google Play Billing
  // =====================================================================
  // Order:
  //   1. startListening()  - call early (app start or the buy screen).
  //      Unfinished purchases from an earlier session are delivered here too.
  //   2. isStoreAvailable(), then getCoinPackages(), then loadProducts().
  //   3. startPurchase(product)
  //   4. The listener verifies the token with the backend and ONLY THEN
  //      consumes the purchase, so the user can buy it again.
  // If verification fails, the purchase is NOT consumed. It is delivered again
  // later and verified again (the backend never credits the same token twice).

  static final InAppPurchase _store = InAppPurchase.instance;
  static StreamSubscription<List<PurchaseDetails>>? _subscription;

  // Tokens being verified right now, to avoid verifying the same one twice.
  static final Set<String> _beingVerified = {};

  static void Function()? onPending;
  static void Function()? onCancelled;
  static void Function(String message)? onFailed;
  // Called with the backend's verify response (coins_added, wallet, ...).
  static void Function(Map<String, dynamic> result)? onCompleted;

  static Future<bool> isStoreAvailable() {
    return _store.isAvailable();
  }

  // Loads the Google Play details (including the local price) for the
  // packages returned by the backend.
  static Future<List<ProductDetails>> loadProducts(
    List<CoinPackageModel> packages,
  ) async {
    final ids = packages.map((package) => package.productId).toSet();
    final response = await _store.queryProductDetails(ids);

    if (response.error != null) {
      throw ApiException('Could not load products from Google Play.');
    }
    return response.productDetails;
  }

  // The result arrives through the callbacks above.
  // autoConsume is false so nothing is consumed before the backend confirms.
  static Future<void> startPurchase(ProductDetails product) async {
    final started = await _store.buyConsumable(
      purchaseParam: PurchaseParam(productDetails: product),
      autoConsume: false,
    );
    if (!started) {
      throw ApiException('The purchase could not be started.');
    }
  }

  static void startListening() {
    _subscription ??= _store.purchaseStream.listen((purchases) async {
      for (var purchase in purchases) {
        await _handlePurchase(purchase);
      }
    });
  }

  static void stopListening() {
    _subscription?.cancel();
    _subscription = null;
  }

  static Future<void> _handlePurchase(PurchaseDetails purchase) async {
    switch (purchase.status) {
      case PurchaseStatus.pending:
        onPending?.call();
        break;
      case PurchaseStatus.canceled:
        onCancelled?.call();
        await _finish(purchase);
        break;
      case PurchaseStatus.error:
        onFailed?.call(purchase.error?.message ?? 'The purchase failed.');
        await _finish(purchase);
        break;
      case PurchaseStatus.purchased:
      case PurchaseStatus.restored:
        await _verifyAndConsume(purchase);
        break;
    }
  }

  static Future<void> _verifyAndConsume(PurchaseDetails purchase) async {
    // On Android this is the Google Play purchase token.
    final token = purchase.verificationData.serverVerificationData;
    if (!_beingVerified.add(token)) return;

    Map<String, dynamic> result;
    try {
      result = await verifyCoinPurchase(
        productId: purchase.productID,
        purchaseToken: token,
      );
    } on ApiException catch (e) {
      // Not verified: do NOT consume.
      onFailed?.call(e.message);
      _beingVerified.remove(token);
      return;
    } catch (e) {
      onFailed?.call('Could not verify the purchase. Please try again.');
      _beingVerified.remove(token);
      return;
    }

    // The backend confirmed. Now the purchase can be consumed.
    try {
      final android =
          _store.getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
      await android.consumePurchase(purchase);
      await _finish(purchase);
    } catch (e) {
      // The coins are already credited. An unconsumed purchase is delivered
      // again later and the backend answers "duplicate" without adding coins.
    }

    _beingVerified.remove(token);
    onCompleted?.call(result);
  }

  static Future<void> _finish(PurchaseDetails purchase) async {
    if (!purchase.pendingCompletePurchase) return;
    try {
      await _store.completePurchase(purchase);
    } catch (e) {
      // Already completed.
    }
  }
}
