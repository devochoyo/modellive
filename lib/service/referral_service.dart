import '../model/referral_model.dart';
import 'api_service.dart';

class ReferralService {
  // Your referral code, how many people you referred and the coins earned.
  static Future<ReferralSummaryModel> getSummary() async {
    final response = await ApiService.get('/referrals/summary');

    return ReferralSummaryModel.fromJson(response['data']);
  }

  // The people you referred, newest first.
  static Future<List<ReferralModel>> getReferrals({
    int page = 1,
    int perPage = 20,
  }) async {
    final response = await ApiService.get('/referrals', query: {
      'page': page.toString(),
      'per_page': perPage.toString(),
    });

    List<ReferralModel> referrals = [];
    for (var item in response['data']['referrals']) {
      referrals.add(ReferralModel.fromJson(item));
    }
    return referrals;
  }
}
