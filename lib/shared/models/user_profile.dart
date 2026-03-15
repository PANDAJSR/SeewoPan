class UserProfile {
  const UserProfile({
    required this.displayName,
    this.realName,
    this.username,
    this.photoUrl,
    this.schoolName,
  });

  final String displayName;
  final String? realName;
  final String? username;
  final String? photoUrl;
  final String? schoolName;

  factory UserProfile.fromApi(Map<String, dynamic> data) {
    final nickName = data['nickName']?.toString().trim();
    final realName = data['realName']?.toString().trim();
    final username = data['username']?.toString().trim();
    final photoUrl = data['photoUrl']?.toString().trim();
    final schoolName = data['schoolName']?.toString().trim();

    final displayName = [nickName, realName, username]
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .join(' / ');

    if (displayName.isEmpty) {
      throw const FormatException('No display name fields in response.');
    }

    return UserProfile(
      displayName: displayName,
      realName: realName?.isNotEmpty == true ? realName : null,
      username: username?.isNotEmpty == true ? username : null,
      photoUrl: photoUrl?.isNotEmpty == true ? photoUrl : null,
      schoolName: schoolName?.isNotEmpty == true ? schoolName : null,
    );
  }
}
