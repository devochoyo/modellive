// One person you referred: an item of "GET /referrals".
class ReferralModel {
  final int id;
  final String username;
  final String? fullName;
  final String? avatarUrl;
  final DateTime? joinedAt;
  final int coinsEarned; // 0 until they make their first purchase
  final bool hasPurchased;

  ReferralModel({
    required this.id,
    required this.username,
    this.fullName,
    this.avatarUrl,
    this.joinedAt,
    required this.coinsEarned,
    required this.hasPurchased,
  });

  factory ReferralModel.fromJson(Map<String, dynamic> json) {
    return ReferralModel(
      id: json['id'],
      username: json['username'],
      fullName: json['full_name'],
      avatarUrl: json['avatar_url'],
      joinedAt:
          json['joined_at'] == null ? null : DateTime.parse(json['joined_at']),
      coinsEarned: json['coins_earned'] ?? 0,
      hasPurchased: json['has_purchased'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'full_name': fullName,
      'avatar_url': avatarUrl,
      'joined_at': joinedAt?.toUtc().toIso8601String(),
      'coins_earned': coinsEarned,
      'has_purchased': hasPurchased,
    };
  }
}

// The totals at the top of the Referrals screen: "GET /referrals/summary".
class ReferralSummaryModel {
  final String referralCode; // the code this user shares with friends
  final int rewardPercent; // e.g. 5 means 5% of a friend's first purchase
  final int totalReferrals;
  final int totalEarnedCoins;

  ReferralSummaryModel({
    required this.referralCode,
    required this.rewardPercent,
    required this.totalReferrals,
    required this.totalEarnedCoins,
  });

  factory ReferralSummaryModel.fromJson(Map<String, dynamic> json) {
    return ReferralSummaryModel(
      referralCode: json['referral_code'],
      rewardPercent: json['reward_percent'] ?? 5,
      totalReferrals: json['total_referrals'] ?? 0,
      totalEarnedCoins: json['total_earned_coins'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'referral_code': referralCode,
      'reward_percent': rewardPercent,
      'total_referrals': totalReferrals,
      'total_earned_coins': totalEarnedCoins,
    };
  }
}
