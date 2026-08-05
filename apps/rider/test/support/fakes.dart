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
}

AuthUser fakeUser({String? name, Gender? gender}) => AuthUser(
      id: 'u1',
      phone: '+9647701234567',
      name: name,
      gender: gender,
      roles: const ['RIDER'],
      profileComplete:
          (name?.trim().isNotEmpty ?? false) && gender != null,
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
