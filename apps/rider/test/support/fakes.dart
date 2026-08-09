import 'package:shared/shared.dart';

/// A scriptable fake of [AuthApi] for tests — no real network.
class FakeAuthApi implements AuthApi {
  int requestOtpCalls = 0;
  String? lastPhone;
  ApiException? requestOtpError;

  AuthSession? verifyResult;
  ApiException? verifyError;

  AuthUser? meResult;
  Object? meError;

  String? lastName;
  AuthUser? updateNameResult;
  ApiException? updateNameError;

  Gender? lastGender;
  AuthUser? updateProfileResult;
  ApiException? updateProfileError;

  @override
  Future<void> requestOtp(String phone) async {
    requestOtpCalls++;
    lastPhone = phone;
    if (requestOtpError != null) throw requestOtpError!;
  }

  @override
  Future<AuthSession> verifyOtp(String phone, String code) async {
    if (verifyError != null) throw verifyError!;
    return verifyResult!;
  }

  @override
  Future<AuthUser> me() async {
    if (meError != null) throw meError!;
    return meResult!;
  }

  @override
  Future<AuthUser> updateName(String name) async {
    lastName = name;
    if (updateNameError != null) throw updateNameError!;
    return updateNameResult ?? fakeUser(name: name);
  }

  @override
  Future<AuthUser> updateProfile({String? name, Gender? gender}) async {
    if (name != null) lastName = name;
    if (gender != null) lastGender = gender;
    if (updateProfileError != null) throw updateProfileError!;
    return updateProfileResult ??
        fakeUser(name: name ?? lastName, gender: gender ?? lastGender);
  }

  /// Whatever the "server" currently holds for this rider.
  EmergencyContact? emergencyContact;

  @override
  Future<AuthUser> updateEmergencyContact(EmergencyContact? contact) async {
    emergencyContact = contact;
    return fakeUser(
      name: lastName,
      gender: lastGender,
      emergencyContact: contact,
    );
  }
}

AuthUser fakeUser({
  String? name,
  Gender? gender,
  /// Null by default — the state almost every rider is in, and the one the
  /// "no emergency UI anywhere" assertions depend on.
  EmergencyContact? emergencyContact,
}) =>
    AuthUser(
      id: 'u1',
      phone: '+9647701234567',
      name: name,
      gender: gender,
      roles: const ['RIDER'],
      profileComplete:
          (name?.trim().isNotEmpty ?? false) && gender != null,
      emergencyContact: emergencyContact,
    );

/// A scriptable [NotificationApi] — no network, empty inbox by default.
class FakeNotificationApi implements NotificationApi {
  NotificationFeed feed = NotificationFeed.empty;
  Object? listError;
  int listCalls = 0;
  final List<String> readCalls = [];
  int readAllCalls = 0;
  Object? markError;

  @override
  Future<NotificationFeed> list() async {
    listCalls++;
    if (listError != null) throw listError!;
    return feed;
  }

  @override
  Future<void> markRead(String id) async {
    readCalls.add(id);
    if (markError != null) throw markError!;
  }

  @override
  Future<void> markAllRead() async {
    readAllCalls++;
    if (markError != null) throw markError!;
  }
}

/// A notification fixture. [minutesAgo] keeps ordering deterministic.
AppNotification notificationFixture({
  String id = 'n1',
  AppNotificationType type = AppNotificationType.bookingConfirmed,
  String title = 'تم تأكيد حجزك',
  String body = 'حجزك مؤكد.',
  bool read = false,
  int minutesAgo = 0,
  String? tripId,
}) =>
    AppNotification(
      id: id,
      type: type,
      title: title,
      body: body,
      createdAt: DateTime.utc(2026, 7, 20, 5).subtract(Duration(minutes: minutesAgo)),
      tripId: tripId,
      readAt: read ? DateTime.utc(2026, 7, 20, 6) : null,
    );

/// A signed-in [AuthController], for screens that read the current user.
///
/// Tests mount a real one rather than making the screen tolerate a missing
/// provider: the production tree always has an AuthController (TaxiApp
/// provides it at the shell), and an emergency action that quietly disappears
/// when a lookup fails is exactly the failure this feature cannot afford.
///
/// [emergencyContact] defaults to null — the state almost every rider is in.
Future<AuthController> signedInAuth({EmergencyContact? emergencyContact}) async {
  final api = FakeAuthApi()
    ..meResult = fakeUser(
      name: 'راكب',
      gender: Gender.male,
      emergencyContact: emergencyContact,
    );
  final auth = AuthController(api: api, tokenStore: InMemoryTokenStore('jwt'));
  await auth.bootstrap();
  return auth;
}

/// A [LinkLauncher] that records instead of leaving the app.
///
/// This is what `url_launcher` sitting behind an interface buys us: "tapping
/// شارك opens WhatsApp" is not observable in a widget test, but "tapping شارك
/// launched `https://wa.me/?text=…`" is — and the URL is the part that
/// actually breaks. A `+` where `%20` belongs, or a phone number left in the
/// path, fails silently on the user's phone and nowhere else.
class FakeLinkLauncher implements LinkLauncher {
  FakeLinkLauncher({this.handles = _everything});

  /// Which URIs this device "has an app for".
  bool Function(Uri) handles;

  final List<Uri> opened = [];

  /// Everything it was ASKED to open, refusals included.
  final List<Uri> attempted = [];

  Uri? get last => opened.isEmpty ? null : opened.last;

  @override
  Future<bool> open(Uri uri) async {
    attempted.add(uri);
    if (!handles(uri)) return false;
    opened.add(uri);
    return true;
  }

  static bool _everything(Uri _) => true;

  /// A phone that can open nothing — e.g. no WhatsApp installed, which is an
  /// ordinary outcome and not an error.
  factory FakeLinkLauncher.deaf() => FakeLinkLauncher(handles: (_) => false);
}
