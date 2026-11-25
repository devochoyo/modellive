import '../model/profile_model.dart';
import 'api_service.dart';

class ProfileService {
  // Your own profile (includes your email).
  static Future<ProfileModel> getMyProfile() async {
    final response = await ApiService.get('/users/me');

    return ProfileModel.fromJson(response['data']);
  }

  // Only the fields you pass are sent. Returns the updated profile.
  static Future<ProfileModel> updateMyProfile({
    String? fullName,
    String? bio,
    String? avatarUrl,
    String? country,
  }) async {
    final body = <String, dynamic>{};
    if (fullName != null) body['full_name'] = fullName;
    if (bio != null) body['bio'] = bio;
    if (avatarUrl != null) body['avatar_url'] = avatarUrl;
    if (country != null) body['country'] = country;

    final response = await ApiService.put('/users/me', body: body);

    return ProfileModel.fromJson(response['data']);
  }

  // Uploads a new profile picture (a file picked from the gallery/camera).
  // Returns the updated profile with the new avatarUrl.
  static Future<ProfileModel> uploadAvatar({required String filePath}) async {
    final response = await ApiService.uploadFile(
      '/users/me/avatar',
      field: 'avatar',
      filePath: filePath,
    );

    return ProfileModel.fromJson(response['data']);
  }

  // Someone else's profile. liveStream is null when they are not live.
  static Future<ProfileModel> getPublicProfile({required int userId}) async {
    final response = await ApiService.get('/users/$userId');

    return ProfileModel.fromJson(response['data']);
  }
}
