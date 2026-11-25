import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as io;

import '../model/notification_model.dart';
import 'api_service.dart';

class NotificationService {
  // ---------- REST ----------

  // An empty list means there are no notifications.
  static Future<({List<NotificationModel> notifications, int unreadCount})>
      getNotifications({int page = 1, int perPage = 20}) async {
    final response = await ApiService.get('/notifications', query: {
      'page': page.toString(),
      'per_page': perPage.toString(),
    });
    final data = response['data'];

    List<NotificationModel> notifications = [];
    for (var item in data['notifications']) {
      notifications.add(NotificationModel.fromJson(item));
    }

    return (
      notifications: notifications,
      unreadCount: data['unread_count'] as int,
    );
  }

  static Future<NotificationModel> markNotificationAsRead({
    required int notificationId,
  }) async {
    final response =
        await ApiService.post('/notifications/$notificationId/read');
    return NotificationModel.fromJson(response['data']['notification']);
  }

  // Returns the new unread count (0).
  static Future<int> markAllNotificationsAsRead() async {
    final response = await ApiService.post('/notifications/read-all');
    return response['data']['unread_count'];
  }

  // ---------- Socket.IO ----------
  // Uses its own connection, so it never interferes with the live-stream or
  // message connections. Events are live-only: after a reconnect, call
  // getNotifications() again.

  static io.Socket? _socket;
  static void Function(NotificationModel notification)? _listener;

  // Connects (if needed) and listens for "notification:new".
  // Calling it again replaces the previous listener, so there are no duplicates.
  static Future<void> listenForNotifications(
    void Function(NotificationModel notification) callback,
  ) async {
    _listener = callback;

    if (_socket == null) {
      try {
        await ApiService.ensureSession(); // renews an expired token first
      } on ApiException catch (e) {
        if (e.sessionExpired) rethrow;
      }
      final token = await ApiService.getAccessToken();
      if (token == null) {
        throw ApiException('Session expired.',
            statusCode: 401, sessionExpired: true);
      }

      // Same host as the REST API (path /socket.io).
      final serverUrl = Uri.parse(ApiService.baseUrl).origin;

      final socket = io.io(
        serverUrl,
        io.OptionBuilder()
            .setTransports(['websocket'])
            .setAuth({'token': token})
            .disableAutoConnect()
            .build(),
      );
      _socket = socket;
      socket.connect();
    }

    _socket!.off('notification:new');
    _socket!.on('notification:new', (data) {
      _listener?.call(NotificationModel.fromJson(Map<String, dynamic>.from(data)));
    });
  }

  // Removes the listener and closes this connection.
  static void stopListening() {
    _listener = null;
    _socket?.off('notification:new');
    _socket?.dispose();
    _socket = null;
  }
}
