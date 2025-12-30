class UserCandidate {
  const UserCandidate({
    required this.userKey,
    required this.display,
  });

  final String userKey;
  final String display;

  factory UserCandidate.fromJson(Map<String, dynamic> json) {
    return UserCandidate(
      userKey: (json['userKey'] ?? json['user_key'] ?? '').toString(),
      display: (json['display'] ?? '').toString(),
    );
  }
}

