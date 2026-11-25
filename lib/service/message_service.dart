import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as io;

import '../model/conversation_model.dart';
import '../model/message_model.dart';
import 'api_service.dart';

class MessageService {
  // =====================================================================
  // REST
  // =====================================================================

  // Creates the conversation automatically on the first message.
  static Future<MessageModel> sendMessage({
    required int receiverId,
    required String body,
  }) async {
    final response = await ApiService.post('/messages/send', body: {
      'receiver_id': receiverId,
      'body': body,
    });
    return MessageModel.fromJson(response['data']['message']);
  }

  // Chat list, newest first. An empty list means "No messages yet."
  static Future<List<ConversationModel>> getConversations({
    int page = 1,
    int perPage = 20,
  }) async {
    final response = await ApiService.get('/messages/conversations', query: {
      'page': page.toString(),
      'per_page': perPage.toString(),
    });

    List<ConversationModel> conversations = [];
    for (var item in response['data']['conversations']) {
      conversations.add(ConversationModel.fromJson(item));
    }
    return conversations;
  }

  // Messages are oldest first. To load older messages, call again with
  // beforeId = nextBeforeId (only when hasMore is true).
  static Future<({List<MessageModel> messages, bool hasMore, int? nextBeforeId})>
      getConversationMessages({
    required int conversationId,
    int limit = 30,
    int? beforeId,
  }) async {
    final query = <String, String>{'limit': limit.toString()};
    if (beforeId != null) {
      query['before_id'] = beforeId.toString();
    }

    final response = await ApiService.get(
      '/messages/conversations/$conversationId/messages',
      query: query,
    );
    final data = response['data'];

    List<MessageModel> messages = [];
    for (var item in data['messages']) {
      messages.add(MessageModel.fromJson(item));
    }

    return (
      messages: messages,
      hasMore: (data['has_more'] as bool?) ?? false,
      nextBeforeId: data['next_before_id'] as int?,
    );
  }

  // Marks the messages sent to you as read. Returns your new unread count.
  static Future<int> markConversationAsRead({
    required int conversationId,
  }) async {
    final response =
        await ApiService.post('/messages/conversations/$conversationId/read');
    return response['data']['unread_count'];
  }

  // =====================================================================
  // Socket.IO (live-only events)
  // =====================================================================
  // This service uses its own connection, separate from LiveStreamService.
  // Socket events are NOT stored. After a reconnect (see onReconnected),
  // reload with getConversations() / getConversationMessages().

  static io.Socket? _socket;
  static bool _hasConnectedBefore = false;
  static void Function()? _reconnectedCallback;

  // One handler per event name, so listeners can never be registered twice.
  static final Map<String, Function(dynamic)> _handlers = {};

  // Connects and waits until the server accepts the access token.
  static Future<void> connectSocket() async {
    if (_socket != null) return;

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

    // The socket server is the same host as the REST API (path /socket.io).
    final serverUrl = Uri.parse(ApiService.baseUrl).origin;

    final socket = io.io(
      serverUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
          .disableAutoConnect()
          .build(),
    );

    final firstConnect = Completer<void>();

    socket.onConnect((_) {
      if (!firstConnect.isCompleted) {
        firstConnect.complete();
      }
      if (_hasConnectedBefore) {
        _reconnectedCallback?.call();
      }
      _hasConnectedBefore = true;
    });

    socket.onConnectError((error) {
      if (!firstConnect.isCompleted) {
        firstConnect.completeError(
            ApiException('Could not connect to the chat server.'));
      }
    });

    _handlers.forEach((event, handler) => socket.on(event, handler));
    _socket = socket;
    socket.connect();

    try {
      await firstConnect.future.timeout(const Duration(seconds: 10));
    } catch (e) {
      disconnectSocket();
      if (e is ApiException) rethrow;
      throw ApiException('Could not connect to the chat server.');
    }
  }

  // Removes every listener and closes the connection.
  static void disconnectSocket() {
    _handlers.clear();
    _reconnectedCallback = null;
    _socket?.dispose();
    _socket = null;
    _hasConnectedBefore = false;
  }

  // Removes every listener but keeps the connection open.
  static void removeAllListeners() {
    for (var event in _handlers.keys) {
      _socket?.off(event);
    }
    _handlers.clear();
    _reconnectedCallback = null;
  }

  // Same as sendMessage(), but over the socket.
  static Future<MessageModel> sendMessageRealtime({
    required int receiverId,
    required String body,
  }) async {
    final data = await _emitWithAck('message:send', {
      'receiver_id': receiverId,
      'body': body,
    });
    return MessageModel.fromJson(data['message']);
  }

  // Same as markConversationAsRead(), but over the socket.
  static Future<void> markConversationAsReadRealtime({
    required int conversationId,
  }) async {
    await _emitWithAck('message:read', {'conversation_id': conversationId});
  }

  // ---------- Listeners ----------
  // Each function replaces the previous listener for that event.

  // A message sent to you (isMine is false).
  static void onNewMessage(void Function(MessageModel message) callback) {
    _listen('message:new', (data) => callback(MessageModel.fromJson(data)));
  }

  // Your message was "delivered" or "read". Update the ticks.
  static void onMessageStatus(
      void Function(int conversationId, String status) callback) {
    _listen('message:status', (data) {
      callback(data['conversation_id'], data['status']);
    });
  }

  // Called when the connection came back after a drop.
  static void onReconnected(void Function() callback) {
    _reconnectedCallback = callback;
  }

  // ---------- Private helpers ----------

  static void _listen(
    String event,
    void Function(Map<String, dynamic> data) callback,
  ) {
    dynamic handler(dynamic data) {
      callback(Map<String, dynamic>.from(data));
    }

    _socket?.off(event);
    _handlers[event] = handler;
    _socket?.on(event, handler);
  }

  // Sends an event and waits for the server's answer:
  // { "success": true, "data": {...} } or { "success": false, "message": ... }
  static Future<Map<String, dynamic>> _emitWithAck(
    String event,
    Map<String, dynamic> payload,
  ) async {
    final socket = _socket;
    if (socket == null) {
      throw ApiException('Not connected to the chat server.');
    }

    final completer = Completer<dynamic>();
    socket.emitWithAck(event, payload, ack: (result) {
      if (!completer.isCompleted) completer.complete(result);
    });

    dynamic result;
    try {
      result = await completer.future.timeout(const Duration(seconds: 10));
    } catch (e) {
      throw ApiException('The chat server did not answer.');
    }

    if (result is List && result.isNotEmpty) {
      result = result.first;
    }
    if (result is! Map) {
      throw ApiException('The chat server sent an unexpected answer.');
    }

    final answer = Map<String, dynamic>.from(result);
    if (answer['success'] != true) {
      throw ApiException(
        answer['message'] ?? 'The request failed.',
        errorCode: answer['error_code'],
      );
    }
    if (answer['data'] == null) return <String, dynamic>{};
    return Map<String, dynamic>.from(answer['data']);
  }
}