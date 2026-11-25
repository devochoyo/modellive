// A user as returned by the API (auth, user lists, hosts, requesters...).
// Fields that only appear in some responses are nullable.
class UserModel {
  final int id;
  final String username;
  final String? fullName;
  final String? avatarUrl;
  final String? email; // only returned for the logged-in user
  final int? followersCount; // only in user lists
  final String? followersDisplay; // e.g. "1.2K"
  final bool? isFollowing; // only in user lists and the Home feed

  UserModel({
    required this.id,
    required this.username,
    this.fullName,
    this.avatarUrl,
    this.email,
    this.followersCount,
    this.followersDisplay,
    this.isFollowing,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'],
      username: json['username'],
      fullName: json['full_name'],
      avatarUrl: json['avatar_url'],
      email: json['email'],
      followersCount: json['followers_count'],
      followersDisplay: json['followers_display'],
      isFollowing: json['is_following'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'full_name': fullName,
      'avatar_url': avatarUrl,
      'email': email,
      'followers_count': followersCount,
      'followers_display': followersDisplay,
      'is_following': isFollowing,
    };
  }
}
