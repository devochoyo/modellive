import '../model/user_model.dart';
import 'api_service.dart';

class FollowService {
  // Returns { "is_following": true, "followers_count": 13 }
  static Future<Map<String, dynamic>> followUser({required int userId}) async {
    final response = await ApiService.post('/follows/$userId');
    return response['data'];
  }

  // Returns { "is_following": false, "followers_count": 12 }
  static Future<Map<String, dynamic>> unfollowUser({required int userId}) async {
    final response = await ApiService.delete('/follows/$userId');
    return response['data'];
  }

  // Your followers, or the followers of [userId] when it is given.
  static Future<List<UserModel>> getFollowers({
    int? userId,
    int page = 1,
    int perPage = 20,
  }) {
    return _getUserList('/follows/followers', userId, page, perPage);
  }

  // Who you follow, or who [userId] follows when it is given.
  static Future<List<UserModel>> getFollowing({
    int? userId,
    int page = 1,
    int perPage = 20,
  }) {
    return _getUserList('/follows/following', userId, page, perPage);
  }

  static Future<List<UserModel>> _getUserList(
    String path,
    int? userId,
    int page,
    int perPage,
  ) async {
    final query = <String, String>{
      'page': page.toString(),
      'per_page': perPage.toString(),
    };
    if (userId != null) {
      query['user_id'] = userId.toString();
    }

    final response = await ApiService.get(path, query: query);

    List<UserModel> users = [];
    for (var item in response['data']['users']) {
      users.add(UserModel.fromJson(item));
    }
    return users;
  }
}
