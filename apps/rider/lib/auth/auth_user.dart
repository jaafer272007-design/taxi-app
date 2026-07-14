/// The authenticated user (mirrors the backend `PublicUser`).
class AuthUser {
  const AuthUser({
    required this.id,
    required this.phone,
    required this.roles,
    this.name,
  });

  final String id;
  final String phone;
  final String? name;
  final List<String> roles;

  /// A user still needs onboarding's name step until they have a non-empty name.
  bool get hasName => (name?.trim().isNotEmpty) ?? false;

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    final rawName = json['name'] as String?;
    return AuthUser(
      id: json['id'] as String,
      phone: json['phone'] as String,
      name: (rawName != null && rawName.trim().isNotEmpty) ? rawName : null,
      roles: (json['roles'] as List<dynamic>? ?? const [])
          .map((r) => r.toString())
          .toList(),
    );
  }
}

/// Result of a successful OTP verification.
class AuthSession {
  const AuthSession({required this.accessToken, required this.user});

  final String accessToken;
  final AuthUser user;
}
