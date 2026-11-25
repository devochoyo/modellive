import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as io;

import '../model/comment_model.dart';
import '../model/join_request_model.dart';
import '../model/live_stream_model.dart';
import '../model/participant_model.dart';
import 'api_service.dart';

class LiveStreamService {
  // =====================================================================
  // REST
  // =====================================================================
  // The stream limit (default 9 including the host) is enforced by the
  // backend. Requests that go over it fail with an ApiException
  // (errorCode "stream_full").

  // Host: creates the stream and the VideoSDK room. The returned model has
  // roomId, participantId, token and role = "host".
  static Future<LiveStreamModel> createLiveStream({String? title}) async {
    Map<String, dynamic>? body;
    if (title != null) {
      body = {'title': title};
    }

    final response = await ApiService.post('/live/streams', body: body);
    return LiveStreamModel.fromJoinResponse(response['data']);
  }

  // Home feed.
  static Future<List<LiveStreamModel>> getLiveStreams({
    int page = 1,
    int perPage = 20,
  }) async {
    final response = await ApiService.get('/live/streams', query: {
      'page': page.toString(),
      'per_page': perPage.toString(),
    });

    List<LiveStreamModel> streams = [];
    for (var item in response['data']['streams']) {
      streams.add(LiveStreamModel.fromJson(item));
    }
    return streams;
  }

  // Stream info plus the people on stage (participants).
  static Future<LiveStreamModel> getLiveStreamDetails({
    required int streamId,
  }) async {
    final response = await ApiService.get('/live/streams/$streamId');
    final data = response['data'];

    // The README does not say whether the stream is inside "stream" or
    // directly in "data", so both are handled.
    final stream = Map<String, dynamic>.from(data['stream'] ?? data);
    if (data['participants'] != null) {
      stream['participants'] = data['participants'];
    }
    return LiveStreamModel.fromJson(stream);
  }

  // Host only.
  static Future<LiveStreamModel> startLiveStream({required int streamId}) async {
    final response = await ApiService.post('/live/streams/$streamId/start');
    return LiveStreamModel.fromJson(response['data']['stream']);
  }

  // Host only.
  static Future<LiveStreamModel> endLiveStream({required int streamId}) async {
    final response = await ApiService.post('/live/streams/$streamId/end');
    return LiveStreamModel.fromJson(response['data']['stream']);
  }

  // Viewer, approved guest or host. Safe to call again.
  // Check the returned model's "role" ("host", "guest" or "viewer").
  static Future<LiveStreamModel> joinLiveStream({required int streamId}) async {
    final response = await ApiService.post('/live/streams/$streamId/join');
    return LiveStreamModel.fromJoinResponse(response['data']);
  }

  // Viewers and guests only. The host must call endLiveStream().
  static Future<void> leaveLiveStream({required int streamId}) async {
    await ApiService.post('/live/streams/$streamId/leave');
  }

  // Returns the new like count. You must have joined the stream first.
  static Future<int> likeLiveStream({required int streamId}) async {
    final response = await ApiService.post('/live/streams/$streamId/like');
    return response['data']['like_count'];
  }

  // Viewer asks to join as a guest. The request is "pending" until the
  // host approves it, so this does NOT make the viewer a guest.
  static Future<JoinRequestModel> requestToJoinLiveStream({
    required int streamId,
  }) async {
    final response = await ApiService.post('/live/streams/$streamId/requests');
    return JoinRequestModel.fromJson(response['data']['request']);
  }

  // Host: the requests waiting for an answer.
  static Future<List<JoinRequestModel>> getJoinRequests({
    required int streamId,
  }) async {
    final response = await ApiService.get('/live/streams/$streamId/requests');

    List<JoinRequestModel> requests = [];
    for (var item in response['data']['requests']) {
      requests.add(JoinRequestModel.fromJson(item));
    }
    return requests;
  }

  // Host. Returns { "request": {...}, "guest": {...} }.
  static Future<Map<String, dynamic>> approveJoinRequest({
    required int streamId,
    required int requestId,
  }) async {
    final response = await ApiService.post(
        '/live/streams/$streamId/requests/$requestId/approve');
    return response['data'];
  }

  // Host.
  static Future<Map<String, dynamic>> rejectJoinRequest({
    required int streamId,
    required int requestId,
  }) async {
    final response = await ApiService.post(
        '/live/streams/$streamId/requests/$requestId/reject');
    return response['data'] ?? <String, dynamic>{};
  }

  // Host. Returns "kicked". If it is false, VideoSDK could not be reached,
  // so the app should also stop that guest's video.
  static Future<bool> removeParticipant({
    required int streamId,
    required int userId,
  }) async {
    final response = await ApiService.post(
        '/live/streams/$streamId/participants/$userId/remove');
    return response['data']['kicked'] ?? false;
  }

  // =====================================================================
  // Socket.IO (live-only events)
  // =====================================================================
  // Order for entering a stream:
  //   1. joinLiveStream()  (REST)
  //   2. connectSocket()
  //   3. register the listeners
  //   4. joinStreamRoom()
  // The host does the same after createLiveStream().
  //
  // Socket events are NOT stored. After a reconnect (see onReconnected) the
  // app must call joinLiveStream(), joinStreamRoom() and getLiveStreamDetails()
  // again to reload the current state.

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
            ApiException('Could not connect to the live server.'));
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
      throw ApiException('Could not connect to the live server.');
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

  // Call after joinLiveStream(). Returns
  // { "stream_id", "role", "viewer_count", "like_count" }.
  static Future<Map<String, dynamic>> joinStreamRoom({
    required int streamId,
  }) {
    return _emitWithAck('stream:join', {'stream_id': streamId});
  }

  static Future<void> leaveStreamRoom({required int streamId}) async {
    await _emitWithAck('stream:leave', {'stream_id': streamId});
  }

  // 1 to 200 characters, about 2 per second (errorCode "rate_limited").
  // Everyone in the room (including you) receives "comment:new".
  static Future<void> sendComment({
    required int streamId,
    required String text,
  }) async {
    if (text.isEmpty || text.length > 200) {
      throw ApiException('A comment must be 1 to 200 characters.',
          statusCode: 400);
    }
    await _emitWithAck('comment:send', {'stream_id': streamId, 'text': text});
  }

  // ---------- Listeners ----------
  // Each function replaces the previous listener for that event.

  static void onComment(void Function(CommentModel comment) callback) {
    _listen('comment:new', (data) => callback(CommentModel.fromJson(data)));
  }

  // Payload keys: gift_id, stream_id, quantity, sender, recipient, created_at.
  static void onFlower(void Function(Map<String, dynamic> flower) callback) {
    _listen('flower:new', callback);
  }

  static void onViewerCount(
      void Function(int viewerCount, String? display) callback) {
    _listen('stream:viewer_count', (data) {
      callback(data['viewer_count'], data['viewer_count_display']);
    });
  }

  static void onLikeCount(void Function(int likeCount) callback) {
    _listen('stream:like_count', (data) => callback(data['like_count']));
  }

  // The people on stage (host and guests). Rebuild the video grid with it.
  static void onParticipants(
      void Function(List<ParticipantModel> participants) callback) {
    _listen('stream:participants', (data) {
      List<ParticipantModel> participants = [];
      for (var item in data['participants']) {
        participants.add(ParticipantModel.fromJson(item));
      }
      callback(participants);
    });
  }

  static void onStreamEnded(void Function() callback) {
    _listen('stream:ended', (data) => callback());
  }

  // Host: a viewer asked to join.
  static void onJoinRequest(void Function(JoinRequestModel request) callback) {
    _listen('join_request:new', (data) {
      callback(JoinRequestModel.fromJson(data['request']));
    });
  }

  // Requester: status is "approved" or "rejected". If approved, call
  // joinLiveStream() again to get the guest role.
  static void onJoinRequestUpdate(
      void Function(int requestId, String status) callback) {
    _listen('join_request:update', (data) {
      callback(data['request_id'], data['status']);
    });
  }

  // Guest: you were removed from the stage. Stop publishing video.
  static void onRemovedFromStage(void Function() callback) {
    _listen('stream:removed', (data) => callback());
  }

  // Called when the connection came back after a drop. Reload the stream
  // state through REST (see the comment above).
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
      throw ApiException('Not connected to the live server.');
    }

    final completer = Completer<dynamic>();
    socket.emitWithAck(event, payload, ack: (result) {
      if (!completer.isCompleted) completer.complete(result);
    });

    dynamic result;
    try {
      result = await completer.future.timeout(const Duration(seconds: 10));
    } catch (e) {
      throw ApiException('The live server did not answer.');
    }

    if (result is List && result.isNotEmpty) {
      result = result.first;
    }
    if (result is! Map) {
      throw ApiException('The live server sent an unexpected answer.');
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
