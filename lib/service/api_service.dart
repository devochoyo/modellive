import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

// The error thrown when a request fails. Show [message] to the user.
class ApiException implements Exception {
  final String message;
  final int statusCode; // HTTP status (0 = could not reach the server)
  final String? errorCode; // e.g. "email_taken", "insufficient_flowers"

  // True when the login session ended and the user is already being sent to
  // the login page. Screens can ignore this error.
  final bool sessionExpired;

  ApiException(this.message,
      {this.statusCode = 0, this.errorCode, this.sessionExpired = false});

  @override
  String toString() => message;
}

// All HTTP communication with the backend goes through this class.
class ApiService {
  // The ONLY place where the backend address is written.
  // TODO: replace with the real domain when it is supplied.
  static const String baseUrl = 'https://drezolive.onrender.com/api/v1';

  // Lets the service move to the login page from anywhere (set in main.dart).
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static bool _isLoggingOut = false;
  static Future<bool>? _refreshing;

  // Called when the session can no longer be renewed (expired token).
  // Clears the tokens and opens the login page. No error is shown.
  static Future<void> forceLogout() async {
    if (_isLoggingOut) return;
    _isLoggingOut = true;
    try {
      await clearTokens();
      final nav = navigatorKey.currentState;
      if (nav != null) {
        nav.pushNamedAndRemoveUntil('/login', (route) => false);
      }
    } finally {
      // Allow a future session to be ended again after a short pause.
      Future.delayed(const Duration(seconds: 2), () => _isLoggingOut = false);
    }
  }

  // Asks the server for a new access token with the refresh token.
  // Several requests failing together share one refresh call.
  static Future<bool> _tryRefresh() {
    return _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);
  }

  static Future<bool> _doRefresh() async {
    try {
      final refresh = await getRefreshToken();
      if (refresh == null) return false;
      final response = await http
          .post(
            Uri.parse('$baseUrl/auth/refresh'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'Authorization': 'Bearer $refresh',
            },
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return false;
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final newToken = json['data']?['access_token'];
      if (newToken is! String) return false;
      await saveAccessToken(newToken);
      return true;
    } catch (_) {
      return false;
    }
  }

  static ApiException _sessionEnded() {
    forceLogout();
    return ApiException('Session expired.',
        statusCode: 401, errorCode: 'session_expired', sessionExpired: true);
  }

  // Makes sure the stored access token still works (renews it if needed).
  // Used before opening socket connections, which cannot renew by themselves.
  static Future<void> ensureSession() async {
    await get('/users/me');
  }

  // ---------- Token storage (encrypted by the phone's secure storage) ----------

  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _accessKey = 'access_token';
  static const String _refreshKey = 'refresh_token';

  static Future<void> saveTokens(String accessToken, String refreshToken) async {
    await _storage.write(key: _accessKey, value: accessToken);
    await _storage.write(key: _refreshKey, value: refreshToken);
  }

  static Future<void> saveAccessToken(String accessToken) async {
    await _storage.write(key: _accessKey, value: accessToken);
  }

  static Future<String?> getAccessToken() {
    return _storage.read(key: _accessKey);
  }

  static Future<String?> getRefreshToken() {
    return _storage.read(key: _refreshKey);
  }

  static Future<void> clearTokens() async {
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
  }

  // ---------- Requests ----------
  // Each function returns the full decoded response:
  // { "success": true, "message": "...", "data": {...} }
  // Set requiresAuth to false for public endpoints (login, register...).
  // Set useRefreshToken to true only for POST /auth/refresh.

  static Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? query,
    bool requiresAuth = true,
  }) {
    return _send('GET', path, query: query, requiresAuth: requiresAuth);
  }

  static Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
    bool requiresAuth = true,
    bool useRefreshToken = false,
  }) {
    return _send('POST', path,
        body: body,
        requiresAuth: requiresAuth,
        useRefreshToken: useRefreshToken);
  }

  static Future<Map<String, dynamic>> put(
    String path, {
    Map<String, dynamic>? body,
    bool requiresAuth = true,
  }) {
    return _send('PUT', path, body: body, requiresAuth: requiresAuth);
  }

  static Future<Map<String, dynamic>> delete(
    String path, {
    bool requiresAuth = true,
  }) {
    return _send('DELETE', path, requiresAuth: requiresAuth);
  }

  // Uploads one file as multipart/form-data (e.g. the profile picture).
  static Future<Map<String, dynamic>> uploadFile(
    String path, {
    required String field,
    required String filePath,
    bool retried = false,
  }) async {
    final token = await getAccessToken();
    if (token == null) throw _sessionEnded();

    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl$path'));
    request.headers['Authorization'] = 'Bearer $token';
    request.headers['Accept'] = 'application/json';
    request.files.add(await http.MultipartFile.fromPath(field, filePath));

    http.Response response;
    try {
      final streamed = await request.send().timeout(const Duration(seconds: 60));
      response = await http.Response.fromStream(streamed);
    } catch (e) {
      throw ApiException('Could not reach the server. Check your internet connection.');
    }

    if (response.statusCode == 401) {
      if (!retried && await _tryRefresh()) {
        return uploadFile(path,
            field: field, filePath: filePath, retried: true);
      }
      throw _sessionEnded();
    }

    Map<String, dynamic> json;
    try {
      json = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      throw ApiException('The server sent an unexpected response.',
          statusCode: response.statusCode);
    }
    final isOk = response.statusCode >= 200 && response.statusCode < 300;
    if (!isOk || json['success'] == false) {
      throw ApiException(
        json['message'] ?? _defaultMessage(response.statusCode),
        statusCode: response.statusCode,
        errorCode: json['error_code'],
      );
    }
    return json;
  }

  // ---------- Shared code for all requests ----------

  static Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    bool requiresAuth = true,
    bool useRefreshToken = false,
    bool retried = false,
  }) async {
    // 1. Build the full URL from the central base URL.
    Uri url = Uri.parse('$baseUrl$path');
    if (query != null && query.isNotEmpty) {
      url = url.replace(queryParameters: query);
    }

    // 2. Build the headers.
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (requiresAuth) {
      String? token;
      if (useRefreshToken) {
        token = await getRefreshToken();
      } else {
        token = await getAccessToken();
      }
      if (token == null) {
        throw _sessionEnded();
      }
      headers['Authorization'] = 'Bearer $token';
    }

    // 3. Send the request.
    final request = http.Request(method, url);
    request.headers.addAll(headers);
    if (body != null) {
      request.body = jsonEncode(body);
    }

    http.Response response;
    try {
      final streamed = await request.send().timeout(const Duration(seconds: 30));
      response = await http.Response.fromStream(streamed);
    } catch (e) {
      throw ApiException('Could not reach the server. Check your internet connection.');
    }

    // 4. An expired or invalid token is not an error for the user: renew it
    // once, and if that is not possible send the user to the login page.
    if (response.statusCode == 401 && requiresAuth) {
      if (useRefreshToken) throw _sessionEnded();
      if (!retried && await _tryRefresh()) {
        return _send(method, path,
            body: body, query: query, requiresAuth: requiresAuth, retried: true);
      }
      throw _sessionEnded();
    }

    // 5. Decode the JSON answer.
    Map<String, dynamic> json;
    try {
      json = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      throw ApiException('The server sent an unexpected response.',
          statusCode: response.statusCode);
    }

    // 6. Turn failures into an ApiException.
    final isOk = response.statusCode >= 200 && response.statusCode < 300;
    if (!isOk || json['success'] == false) {
      throw ApiException(
        json['message'] ?? _defaultMessage(response.statusCode),
        statusCode: response.statusCode,
        errorCode: json['error_code'],
      );
    }

    return json;
  }

  // Used only when the server did not send its own message.
  static String _defaultMessage(int statusCode) {
    switch (statusCode) {
      case 400:
        return 'Invalid input.';
      case 401:
        return 'Please log in again.';
      case 402:
        return 'Not enough balance, or the payment was not completed.';
      case 403:
        return 'You are not allowed to do this.';
      case 404:
        return 'Not found.';
      case 409:
        return 'This conflicts with existing data.';
      case 502:
        return 'An outside service had a problem. Please try again.';
      case 503:
        return 'The service is not available right now.';
      default:
        return 'Something went wrong.';
    }
  }
}
