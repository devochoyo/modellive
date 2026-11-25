import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:permission_handler/permission_handler.dart';
import 'package:videosdk/videosdk.dart';

import 'diagnostics_service.dart';

// Handles the VideoSDK room. The room id, participant id and token come from
// the backend (createLiveStream / joinLiveStream). Tokens are never made here.
//
// Permissions: before joining as "host" or "guest", the screen must ask for
// camera and microphone permission (VideoSdkService.ensurePermissions()).
//
// The backend token does NOT separate viewers from guests, so this service
// enforces it: only the roles "host" and "guest" can publish.
class VideoSdkService {
  static Room? _room;
  static String _role = 'viewer';
  static bool _isCameraOn = false;
  static bool _isMicOn = false;
  static Timer? _joinWatchdog;
  static Timer? _monitor;
  static bool _joinedEventSeen = false;
  static String _lastDump = '';
  static int _dumpTicks = 0;

  // Why the last ensurePermissions() / ensureBluetoothPermission() returned
  // false (a message that can be shown to the person). Null when all is fine.
  static String? permissionProblem;

  // ---------- Callbacks the screen can set ----------

  static void Function()? onRoomJoined;
  static void Function(String? reason)? onRoomLeft;
  static void Function()? onParticipantsChanged; // someone joined or left
  // kind is "video", "audio" or "share"
  static void Function(String participantId, String kind, bool enabled)?
      onStreamChanged;
  static void Function(String message)? onError;

  // ---------- State the screen can read ----------

  static Room? get room => _room;
  static Participant? get localParticipant => _room?.localParticipant;
  static bool get isCameraOn => _isCameraOn;
  static bool get isMicOn => _isMicOn;
  static bool get canPublish => _role == 'host' || _role == 'guest';

  // Everyone except you (the host and the guests you can see).
  static List<Participant> get remoteParticipants {
    if (_room == null) return [];
    return _room!.participants.values.toList();
  }

  // ---------- Permissions ----------

  // Asks for camera, microphone and (Android 12+) nearby-devices/Bluetooth.
  // Returns false when something was refused; [permissionProblem] then says
  // what to tell the person.
  //
  // Android 12+ needs the Bluetooth ("Nearby devices") permission granted
  // BEFORE the video room starts, because the audio system looks for
  // headsets. Without it the app can close immediately when the live
  // connects, so it is required here and not only asked for.
  static Future<bool> ensurePermissions() async {
    permissionProblem = null;
    // In a web browser the camera and microphone prompt appears by itself
    // when the video room starts, so there is nothing to ask here.
    // (permission_handler and dart:io Platform do not work on the web.)
    if (kIsWeb) return true;

    try {
      final sdk = Platform.isAndroid ? await Diagnostics.androidSdk() : 0;
      final needed = <Permission>[Permission.camera, Permission.microphone];
      final needsBluetooth = Platform.isAndroid && sdk >= 31;
      if (needsBluetooth) needed.add(Permission.bluetoothConnect);

      await _logStatuses('permissions BEFORE asking (android sdk $sdk)', needed);
      final results = await needed.request();
      await _logStatuses('permissions AFTER asking', needed);

      final cameraOk = results[Permission.camera]?.isGranted ?? false;
      final micOk = results[Permission.microphone]?.isGranted ?? false;
      final bluetoothOk = !needsBluetooth ||
          (results[Permission.bluetoothConnect]?.isGranted ?? false);

      if (!cameraOk || !micOk) {
        permissionProblem =
            'Camera and microphone permission are needed to go live. '
            'Please allow them in your phone settings.';
        return false;
      }
      if (!bluetoothOk) {
        permissionProblem =
            'Please allow "Nearby devices" for ModelLive in your phone '
            'settings. Android needs it to connect the audio of a live.';
        return false;
      }
      return true;
    } catch (e, st) {
      Diagnostics.log('PERM', 'permission request threw: $e\n$st');
      permissionProblem = 'Could not check the permissions: $e';
      return false;
    }
  }

  // Viewers do not publish, but the audio system still looks for headsets on
  // Android 12+, so they need the Bluetooth ("Nearby devices") permission.
  static Future<bool> ensureBluetoothPermission() async {
    permissionProblem = null;
    if (kIsWeb || !Platform.isAndroid) return true;
    try {
      final sdk = await Diagnostics.androidSdk();
      if (sdk < 31) return true;
      final result = await Permission.bluetoothConnect.request();
      Diagnostics.log('PERM', 'bluetoothConnect (viewer) -> $result');
      if (result.isGranted) return true;
      permissionProblem =
          'Please allow "Nearby devices" for ModelLive in your phone '
          'settings. Android needs it to play the audio of a live.';
      return false;
    } catch (e) {
      Diagnostics.log('PERM', 'bluetooth request threw: $e');
      permissionProblem = 'Could not check the permissions: $e';
      return false;
    }
  }

  static Future<void> _logStatuses(String title, List<Permission> list) async {
    final parts = <String>[];
    for (final p in list) {
      try {
        parts.add('$p=${await p.status}');
      } catch (e) {
        parts.add('$p=? ($e)');
      }
    }
    Diagnostics.log('PERM', '$title: ${parts.join(', ')}');
  }

  // ---------- Join and leave ----------

  // [role] is the "role" returned by the backend: "host", "guest" or "viewer".
  // A viewer joins receive-only, with camera and microphone off.
  static Future<void> joinRoom({
    required String roomId,
    required String participantId,
    required String token,
    required String role,
    String? displayName,
  }) async {
    if (_room != null) {
      Diagnostics.log('VIDEO', 'already in a room, leaving it first');
      await leaveRoom();
    }

    _role = role;
    final publish = canPublish;
    Diagnostics.log(
        'VIDEO',
        'joinRoom: roomId=$roomId participantId=$participantId role=$role '
        'publish=$publish tokenLength=${token.length}');

    final Room room;
    try {
      await Diagnostics.logNow('VIDEO', 'STEP A: creating the room object...');
      room = VideoSDK.createRoom(
        roomId: roomId,
        token: token,
        participantId: participantId,
        participantName: displayName ?? 'User',
        micEnabled: publish,
        camEnabled: publish,
        mode: publish ? Mode.SEND_AND_RECV : Mode.RECV_ONLY,
      );
      Diagnostics.log('VIDEO', 'STEP A done: room object created');
    } catch (e, st) {
      Diagnostics.log('VIDEO', 'STEP A FAILED (createRoom): $e\n$st');
      _resetState();
      throw Exception('Could not create the video room: $e');
    }

    _room = room;
    _listenToRoom(room);

    try {
      // If the app dies inside room.join(), the LAST line in the crash report
      // is this one: the crash is inside the VideoSDK / WebRTC native code
      // (camera, microphone, audio routing or network setup).
      await Diagnostics.logNow('VIDEO',
          'STEP B: calling room.join() NOW (camera/mic/WebRTC start here)...');
      _joinedEventSeen = false;
      await room.join();
      Diagnostics.log('VIDEO',
          'STEP B done: room.join() returned, waiting for the roomJoined event');
      _isCameraOn = publish;
      _isMicOn = publish;
      _startMonitor(room);

      _joinWatchdog?.cancel();
      // roomJoined can fire BEFORE join() returns; only watch if it has not.
      if (!_joinedEventSeen) _joinWatchdog = Timer(const Duration(seconds: 20), () {
        Diagnostics.log('VIDEO',
            'WARNING: roomJoined event NOT received 20 seconds after join()');
        onError?.call('The live is taking too long to connect.');
      });
    } catch (e, st) {
      Diagnostics.log('VIDEO', 'STEP B FAILED (room.join): $e\n$st');
      _resetState();
      throw Exception('Could not join the video room: $e');
    }
  }

  static Future<void> leaveRoom() async {
    final room = _room;
    _resetState();
    if (room == null) return;

    try {
      Diagnostics.log('VIDEO', 'leaving the room...');
      await room.leave();
      Diagnostics.log('VIDEO', 'left the room');
    } catch (e) {
      // Already left, nothing more to do.
      Diagnostics.log('VIDEO', 'leave threw (ignored): $e');
    }
  }

  // ---------- Camera diagnostics (printed to the console) ----------

  // Reads one field without ever throwing.
  static String _safe(dynamic Function() read) {
    try {
      return '${read()}';
    } catch (e) {
      return '?';
    }
  }

  static String _describeStream(dynamic st) {
    final r = _safe(() => st.renderer == null ? 'null' : 'present');
    final tex = _safe(() => st.renderer.textureId);
    final src = _safe(() => st.renderer.srcObject != null);
    final w = _safe(() => st.renderer.value.width);
    final h = _safe(() => st.renderer.value.height);
    final trackEnabled = _safe(() => st.track.enabled);
    final trackMuted = _safe(() => st.track.muted);
    final trackState = _safe(() => st.track.readyState);
    return '{id=${_safe(() => st.id)} kind=${_safe(() => st.kind)} '
        'track(enabled=$trackEnabled muted=$trackMuted state=$trackState) '
        'renderer=$r tex=$tex src=$src size=${w}x$h}';
  }

  static String _describeParticipant(Participant p, String label) {
    final streams = <String>[];
    try {
      for (final st in p.streams.values) {
        streams.add(_describeStream(st));
      }
    } catch (e) {
      streams.add('streams unreadable: $e');
    }
    return '$label id=${p.id} name=${p.displayName} '
        'streams(${streams.length})=[${streams.join(', ')}]';
  }

  // Prints the whole camera picture: the local participant and every remote
  // one, with each stream's track and renderer state.
  static void dumpState(String why) {
    final room = _room;
    if (room == null) {
      Diagnostics.log('CAMERA', '[$why] not in a room');
      return;
    }
    final lines = <String>[
      'role=$_role canPublish=$canPublish camOn=$_isCameraOn micOn=$_isMicOn '
          'room=${_safe(() => room.id)} remotes=${room.participants.length}',
      _describeParticipant(room.localParticipant, 'LOCAL'),
      for (final p in room.participants.values)
        _describeParticipant(p, 'REMOTE'),
    ];
    final text = lines.join('\n    ');
    Diagnostics.log('CAMERA', '[$why]\n    $text');
  }

  // Prints the state when it changes, and every ~6 seconds regardless, for as
  // long as the room is open.
  static void _startMonitor(Room room) {
    _monitor?.cancel();
    _lastDump = '';
    _dumpTicks = 0;
    _monitor = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_room == null) return;
      _dumpTicks++;
      final lines = <String>[
        _describeParticipant(room.localParticipant, 'LOCAL'),
        for (final p in room.participants.values)
          _describeParticipant(p, 'REMOTE'),
      ];
      final summary = lines.join('\n    ');
      if (summary != _lastDump || _dumpTicks % 3 == 0) {
        _lastDump = summary;
        Diagnostics.log('CAMERA', '[monitor]\n    $summary');
      }
    });
  }

  // ---------- Role changes ----------

  // Call this with the role the backend returned:
  //  - after joinLiveStream() returns "guest" (the host approved the request)
  //  - after the "removed from stage" event, with "viewer"
  static Future<void> updateRole(String role) async {
    final room = _checkInRoom();
    _role = role;

    if (canPublish) {
      await room.changeMode(Mode.SEND_AND_RECV);
      await enableCamera();
      await enableMic();
    } else {
      await _stopPublishing(room);
      await room.changeMode(Mode.RECV_ONLY);
    }
  }

  // ---------- Camera and microphone ----------

  static Future<void> enableCamera() async {
    final room = _checkCanPublish();
    Diagnostics.log('CAMERA', 'enableCam() called');
    try {
      await room.enableCam();
    } catch (e, st) {
      Diagnostics.log('CAMERA', 'enableCam() FAILED: $e\n$st');
      rethrow;
    }
    Diagnostics.log('CAMERA', 'enableCam() returned');
    _isCameraOn = true;
  }

  static Future<void> disableCamera() async {
    final room = _checkInRoom();
    await room.disableCam();
    _isCameraOn = false;
  }

  static Future<void> enableMic() async {
    final room = _checkCanPublish();
    await room.unmuteMic();
    _isMicOn = true;
  }

  static Future<void> disableMic() async {
    final room = _checkInRoom();
    await room.muteMic();
    _isMicOn = false;
  }

  // ---------- Private helpers ----------

  static Room _checkInRoom() {
    final room = _room;
    if (room == null) {
      throw Exception('You are not in a video room.');
    }
    return room;
  }

  // Viewers can never publish, even though their token would allow it.
  static Room _checkCanPublish() {
    final room = _checkInRoom();
    if (!canPublish) {
      throw Exception('Only the host and approved guests can publish video.');
    }
    return room;
  }

  static Future<void> _stopPublishing(Room room) async {
    try {
      await room.disableCam();
    } catch (e) {
      // The camera was already off.
    }
    try {
      await room.muteMic();
    } catch (e) {
      // The microphone was already off.
    }
    _isCameraOn = false;
    _isMicOn = false;
  }

  static void _resetState() {
    _monitor?.cancel();
    _monitor = null;
    _joinWatchdog?.cancel();
    _joinWatchdog = null;
    _room = null;
    _role = 'viewer';
    _isCameraOn = false;
    _isMicOn = false;
  }

  static void _listenToRoom(Room room) {
    room.on(Events.roomJoined, ([dynamic a]) {
      _joinedEventSeen = true;
      _joinWatchdog?.cancel();
      Diagnostics.log('VIDEO',
          'EVENT roomJoined: connected. participants=${room.participants.length}');
      dumpState('right after roomJoined');
      Future<void>.delayed(const Duration(seconds: 3), () => dumpState('3s after roomJoined'));
      _listenToParticipant(room.localParticipant);
      for (var participant in room.participants.values) {
        _listenToParticipant(participant);
      }
      onRoomJoined?.call();
      onParticipantsChanged?.call();
    });

    room.on(Events.roomLeft, ([dynamic reason]) {
      Diagnostics.log('VIDEO', 'EVENT roomLeft: reason=$reason');
      _resetState();
      onRoomLeft?.call(reason?.toString());
    });

    room.on(Events.participantJoined, ([dynamic participant]) {
      Diagnostics.log('VIDEO', 'EVENT participantJoined');
      if (participant != null) {
        _listenToParticipant(participant);
      }
      onParticipantsChanged?.call();
    });

    room.on(Events.participantLeft, ([dynamic a]) {
      Diagnostics.log('VIDEO', 'EVENT participantLeft');
      onParticipantsChanged?.call();
    });

    room.on(Events.error, ([dynamic error]) {
      Diagnostics.log('VIDEO', 'EVENT error: $error');
      onError?.call(error.toString());
    });
  }

  static void _listenToParticipant(Participant participant) {
    participant.on(Events.streamEnabled, ([dynamic stream]) {
      Diagnostics.log('VIDEO',
          'EVENT streamEnabled: participant=${participant.id} kind=${_kindOf(stream)}');
      onStreamChanged?.call(participant.id, _kindOf(stream), true);
    });
    participant.on(Events.streamDisabled, ([dynamic stream]) {
      Diagnostics.log('VIDEO',
          'EVENT streamDisabled: participant=${participant.id} kind=${_kindOf(stream)}');
      onStreamChanged?.call(participant.id, _kindOf(stream), false);
    });
  }

  static String _kindOf(dynamic stream) {
    final kind = stream.kind.toString().toLowerCase();
    if (kind.contains('share')) return 'share';
    if (kind.contains('video')) return 'video';
    return 'audio';
  }
}