// A coin package. The product id matches the Google Play product id.
// The price is not stored by the API; it comes from Google Play Billing.
class CoinPackageModel {
  final String productId;
  final int coins;

  CoinPackageModel({
    required this.productId,
    required this.coins,
  });

  factory CoinPackageModel.fromJson(Map<String, dynamic> json) {
    return CoinPackageModel(
      productId: json['product_id'],
      coins: json['coins'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'product_id': productId,
      'coins': coins,
    };
  }
}
