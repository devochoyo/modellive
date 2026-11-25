// The user's wallet balances.
class WalletModel {
  final int coins;
  final int flowers;
  final int diamonds;
  final int flowersTowardNextDiamond; // received flowers not yet making a diamond

  WalletModel({
    required this.coins,
    required this.flowers,
    required this.diamonds,
    required this.flowersTowardNextDiamond,
  });

  factory WalletModel.fromJson(Map<String, dynamic> json) {
    return WalletModel(
      coins: json['coins'],
      flowers: json['flowers'],
      diamonds: json['diamonds'],
      flowersTowardNextDiamond: json['flowers_toward_next_diamond'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'coins': coins,
      'flowers': flowers,
      'diamonds': diamonds,
      'flowers_toward_next_diamond': flowersTowardNextDiamond,
    };
  }
}
