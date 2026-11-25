import '../model/user_model.dart';
import 'api_service.dart';

class AuthService {
  // Creates an account, saves the tokens and returns the new user.
  // [country] is the 2-letter code, e.g. "NG". [referralCode] is optional.
  static Future<UserModel> register({
    required String email,
    required String username,
    required String fullName,
    required String password,
    required String country,
    String? referralCode,
  }) async {
    final response = await ApiService.post(
      '/auth/register',
      requiresAuth: false,
      body: {
        'email': email,
        'username': username,
        'full_name': fullName,
        'password': password,
        'country': country,
        if (referralCode != null && referralCode.isNotEmpty)
          'referral_code': referralCode,
      },
    );

    return _saveTokensAndGetUser(response['data']);
  }

  // Logs in, saves the tokens and returns the user.
  static Future<UserModel> login({
    required String email,
    required String password,
  }) async {
    final response = await ApiService.post(
      '/auth/login',
      requiresAuth: false,
      body: {
        'email': email,
        'password': password,
      },
    );

    return _saveTokensAndGetUser(response['data']);
  }

  // Uses the stored refresh token to get a new access token.
  static Future<void> refreshToken() async {
    final response = await ApiService.post(
      '/auth/refresh',
      useRefreshToken: true,
    );

    await ApiService.saveAccessToken(response['data']['access_token']);
  }

  // Sends a reset code to the email. In development the returned map may
  // contain "reset_token".
  static Future<Map<String, dynamic>> forgotPassword({
    required String email,
  }) async {
    final response = await ApiService.post(
      '/auth/forgot-password',
      requiresAuth: false,
      body: {'email': email},
    );

    return response['data'] ?? <String, dynamic>{};
  }

  // [token] is the code from the email.
  static Future<Map<String, dynamic>> resetPassword({
    required String token,
    required String newPassword,
  }) async {
    final response = await ApiService.post(
      '/auth/reset-password',
      requiresAuth: false,
      body: {
        'token': token,
        'new_password': newPassword,
      },
    );

    return response['data'] ?? <String, dynamic>{};
  }

  // There is no logout endpoint, so we only delete the stored tokens.
  static Future<void> logout() async {
    await ApiService.clearTokens();
  }

  // Register and login return the same data: user, access_token, refresh_token.
  // This is only called after the backend answered successfully.
  static Future<UserModel> _saveTokensAndGetUser(Map<String, dynamic> data) async {
    await ApiService.saveTokens(data['access_token'], data['refresh_token']);
    return UserModel.fromJson(data['user']);
  }
}
