import '../model/user_model.dart';
import 'api_service.dart';

class UserService {
  // Lists users for the Friends screen. [search] is optional.
  static Future<List<UserModel>> getUsers({
    String? search,
    int page = 1,
    int perPage = 20,
  }) async {
    final query = <String, String>{
      'page': page.toString(),
      'per_page': perPage.toString(),
    };
    if (search != null && search.isNotEmpty) {
      query['search'] = search;
    }

    final response = await ApiService.get('/users', query: query);

    return _toUserList(response['data']['users']);
  }

  // Returns true when the user is now blocked.
  static Future<bool> blockUser({required int userId}) async {
    final response = await ApiService.post('/users/$userId/block');
    return response['data']['is_blocked'];
  }

  // Returns false when the user is no longer blocked.
  static Future<bool> unblockUser({required int userId}) async {
    final response = await ApiService.delete('/users/$userId/block');
    return response['data']['is_blocked'];
  }

  // The README does not document pagination for this endpoint.
  static Future<List<UserModel>> getBlockedUsers() async {
    final response = await ApiService.get('/users/blocked');

    return _toUserList(response['data']['users']);
  }

  static List<UserModel> _toUserList(List<dynamic> items) {
    List<UserModel> users = [];
    for (var item in items) {
      users.add(UserModel.fromJson(item));
    }
    return users;
  }
}
