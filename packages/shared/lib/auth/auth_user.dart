/// The user's gender (mirrors the backend `Gender` enum). Required to complete
/// a profile; used for trip eligibility (women/family trips) and search filters.
enum Gender { male, female }

extension GenderApi on Gender {
  /// The wire value the backend expects (`MALE` / `FEMALE`).
  String get apiValue => this == Gender.male ? 'MALE' : 'FEMALE';
}

/// Parse a backend gender string; unknown / null → `null`.
Gender? genderFromApi(String? raw) => switch (raw) {
      'MALE' => Gender.male,
      'FEMALE' => Gender.female,
      _ => null,
    };

/// The authenticated user (mirrors the backend `PublicUser`).
class AuthUser {
  const AuthUser({
    required this.id,
    required this.phone,
    required this.roles,
    required this.profileComplete,
    this.name,
    this.gender,
  });

  final String id;
  final String phone;
  final String? name;
  final Gender? gender;
  final List<String> roles;

  /// Whether the profile is complete enough to enter the app. The backend
  /// computes this (name + gender both set); we mirror its flag so a valid JWT
  /// with an incomplete profile is routed back to onboarding.
  final bool profileComplete;

  /// A user still needs onboarding's name step until they have a non-empty name.
  bool get hasName => (name?.trim().isNotEmpty) ?? false;

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    final rawName = json['name'] as String?;
    final name = (rawName != null && rawName.trim().isNotEmpty) ? rawName : null;
    final gender = genderFromApi(json['gender'] as String?);
    return AuthUser(
      id: json['id'] as String,
      phone: json['phone'] as String,
      name: name,
      gender: gender,
      roles: (json['roles'] as List<dynamic>? ?? const [])
          .map((r) => r.toString())
          .toList(),
      // Trust the backend flag; fall back to the same rule locally so older
      // API responses (pre-gender) still route correctly.
      profileComplete:
          json['profileComplete'] as bool? ?? (name != null && gender != null),
    );
  }
}

/// Result of a successful OTP verification.
class AuthSession {
  const AuthSession({required this.accessToken, required this.user});

  final String accessToken;
  final AuthUser user;
}
