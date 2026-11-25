import 'live_stream_model.dart';

// A user's profile: "/users/me" (personal) or "/users/<id>" (public).
class ProfileModel {
  final int id;
  final String username;
  final String? fullName;
  final String? avatarUrl;
  final String? email; // only on your own profile
  final String? bio;
  final String? country;
  final int followersCount;
  final String? followersDisplay; // e.g. "1.2K"
  final int followingCount;
  final DateTime? createdAt;

  // Only on a public profile.
  final bool? isSelf;
  final bool? isFollowing;
  final bool? isBlocked;
  final LiveStreamModel? liveStream; // null when the person is not live

  ProfileModel({
    required this.id,
    required this.username,
    this.fullName,
    this.avatarUrl,
    this.email,
    this.bio,
    this.country,
    required this.followersCount,
    this.followersDisplay,
    required this.followingCount,
    this.createdAt,
    this.isSelf,
    this.isFollowing,
    this.isBlocked,
    this.liveStream,
  });

  factory ProfileModel.fromJson(Map<String, dynamic> json) {
    return ProfileModel(
      id: json['id'],
      username: json['username'],
      fullName: json['full_name'],
      avatarUrl: json['avatar_url'],
      email: json['email'],
      bio: json['bio'],
      country: json['country'],
      followersCount: json['followers_count'] ?? 0,
      followersDisplay: json['followers_display'],
      followingCount: json['following_count'] ?? 0,
      createdAt:
          json['created_at'] == null ? null : DateTime.parse(json['created_at']),
      isSelf: json['is_self'],
      isFollowing: json['is_following'],
      isBlocked: json['is_blocked'],
      liveStream: json['live_stream'] == null
          ? null
          : LiveStreamModel.fromJson(json['live_stream']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'full_name': fullName,
      'avatar_url': avatarUrl,
      'email': email,
      'bio': bio,
      'country': country,
      'followers_count': followersCount,
      'followers_display': followersDisplay,
      'following_count': followingCount,
      'created_at': createdAt?.toUtc().toIso8601String(),
      'is_self': isSelf,
      'is_following': isFollowing,
      'is_blocked': isBlocked,
      'live_stream': liveStream?.toJson(),
    };
  }
}
