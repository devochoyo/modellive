import 'participant_model.dart';
import 'user_model.dart';

// A live stream. The same model is used for the Home feed, stream details,
// create/join responses and the small "live_stream" object in a public profile.
class LiveStreamModel {
  final int id;
  final String? title;
  final String? status; // "created", "live", ...
  final int? likeCount;
  final int viewerCount;
  final String? viewerCountDisplay; // e.g. "1K"
  final int? maxParticipants;
  final DateTime? startedAt;
  final UserModel? host;
  final List<ParticipantModel> participants; // only in stream details

  // Only returned by the create/join responses (next to "stream").
  final String? role; // "host", "guest" or "viewer"
  final String? roomId; // VideoSDK room id
  final String? participantId; // VideoSDK participantId
  final String? token; // VideoSDK token

  LiveStreamModel({
    required this.id,
    this.title,
    this.status,
    this.likeCount,
    required this.viewerCount,
    this.viewerCountDisplay,
    this.maxParticipants,
    this.startedAt,
    this.host,
    this.participants = const [],
    this.role,
    this.roomId,
    this.participantId,
    this.token,
  });

  // Use this for a plain "stream" object.
  factory LiveStreamModel.fromJson(Map<String, dynamic> json) {
    List<ParticipantModel> participantList = [];
    if (json['participants'] != null) {
      for (var item in json['participants']) {
        participantList.add(ParticipantModel.fromJson(item));
      }
    }

    return LiveStreamModel(
      id: json['id'],
      title: json['title'],
      status: json['status'],
      likeCount: json['like_count'],
      viewerCount: json['viewer_count'] ?? 0,
      viewerCountDisplay: json['viewer_count_display'],
      maxParticipants: json['max_participants'],
      startedAt:
          json['started_at'] == null ? null : DateTime.parse(json['started_at']),
      host: json['host'] == null ? null : UserModel.fromJson(json['host']),
      participants: participantList,
    );
  }

  // Use this for the create/join response:
  // { "stream": {...}, "role": ..., "room_id": ..., "participant_id": ..., "token": ... }
  factory LiveStreamModel.fromJoinResponse(Map<String, dynamic> json) {
    LiveStreamModel stream = LiveStreamModel.fromJson(json['stream']);
    return LiveStreamModel(
      id: stream.id,
      title: stream.title,
      status: stream.status,
      likeCount: stream.likeCount,
      viewerCount: stream.viewerCount,
      viewerCountDisplay: stream.viewerCountDisplay,
      maxParticipants: stream.maxParticipants,
      startedAt: stream.startedAt,
      host: stream.host,
      participants: stream.participants,
      role: json['role'],
      roomId: json['room_id'],
      participantId: json['participant_id'],
      token: json['token'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'status': status,
      'like_count': likeCount,
      'viewer_count': viewerCount,
      'viewer_count_display': viewerCountDisplay,
      'max_participants': maxParticipants,
      'started_at': startedAt?.toUtc().toIso8601String(),
      'host': host?.toJson(),
      'participants': participants.map((p) => p.toJson()).toList(),
    };
  }
}
