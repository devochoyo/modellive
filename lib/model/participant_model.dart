// A person on the stage of a live stream (the host or a guest).
class ParticipantModel {
  final int id;
  final String username;
  final String? fullName;
  final String? avatarUrl;
  final String role; // "host" or "guest"

  ParticipantModel({
    required this.id,
    required this.username,
    this.fullName,
    this.avatarUrl,
    required this.role,
  });

  factory ParticipantModel.fromJson(Map<String, dynamic> json) {
    return ParticipantModel(
      id: json['id'],
      username: json['username'],
      fullName: json['full_name'],
      avatarUrl: json['avatar_url'],
      role: json['role'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'full_name': fullName,
      'avatar_url': avatarUrl,
      'role': role,
    };
  }
}
