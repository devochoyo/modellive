import 'user_model.dart';

// A viewer's request to join a live stream as a guest.
class JoinRequestModel {
  final int id;
  final int? streamId; // not included in the host's request list
  final String status; // "pending", "approved" or "rejected"
  final DateTime? createdAt;
  final UserModel user; // the viewer who made the request

  JoinRequestModel({
    required this.id,
    this.streamId,
    required this.status,
    this.createdAt,
    required this.user,
  });

  factory JoinRequestModel.fromJson(Map<String, dynamic> json) {
    return JoinRequestModel(
      id: json['id'],
      streamId: json['stream_id'],
      status: json['status'],
      createdAt:
          json['created_at'] == null ? null : DateTime.parse(json['created_at']),
      user: UserModel.fromJson(json['user']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'stream_id': streamId,
      'status': status,
      'created_at': createdAt?.toUtc().toIso8601String(),
      'user': user.toJson(),
    };
  }
}
