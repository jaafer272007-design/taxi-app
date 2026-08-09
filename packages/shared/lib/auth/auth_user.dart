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

/// Someone the user chose to be able to call in a hurry.
///
/// Their own contact, not another user's — so there is no cross-user boundary
/// here. What there IS: it must never leave its owner. The server returns it
/// from `GET /auth/me` and nowhere else, which is asserted against the real
/// driver-facing payloads in `emergency-contact.int-spec.ts`.
class EmergencyContact {
  const EmergencyContact({required this.name, required this.phone});

  final String name;

  /// E.164 (`+9647…`), normalised by the server whichever way it was typed —
  /// so `tel:` always gets a number that dials from a roaming SIM too.
  final String phone;

  factory EmergencyContact.fromJson(Map<String, dynamic> json) =>
      EmergencyContact(
        name: json['name'] as String? ?? '',
        phone: json['phone'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {'name': name, 'phone': phone};
}

/// The authenticated user (mirrors the backend `PublicUser`).
class AuthUser {
  const AuthUser({
    required this.id,
    required this.phone,
    required this.roles,
    required this.profileComplete,
    this.name,
    this.gender,
    this.emergencyContact,
  });

  final String id;
  final String phone;
  final String? name;
  final Gender? gender;
  final List<String> roles;

  /// `null` for almost everyone — the feature is opt-in and nothing about it
  /// renders until the user has saved one. Never prompted for.
  final EmergencyContact? emergencyContact;

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
      emergencyContact: json['emergencyContact'] == null
          ? null
          : EmergencyContact.fromJson(
              json['emergencyContact'] as Map<String, dynamic>),
    );
  }
}

/// Result of a successful OTP verification.
class AuthSession {
  const AuthSession({required this.accessToken, required this.user});

  final String accessToken;
  final AuthUser user;
}
