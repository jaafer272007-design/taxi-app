import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rider/auth/auth_api.dart';
import 'package:rider/auth/auth_controller.dart';
import 'package:rider/auth/auth_user.dart';
import 'package:rider/core/api_exception.dart';
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
    return updateNameResult ?? fakeUser(name: name);
  }
}

AuthUser fakeUser({String? name}) => AuthUser(
      id: 'u1',
      phone: '+9647701234567',
      name: name,
      roles: const ['RIDER'],
    );

/// Wraps [child] with the design-system theme + RTL so onboarding screens can
/// render in a widget test. Default (English) Material localizations satisfy the
/// Material widgets; the Arabic copy is in the widgets' own strings.
Widget wrapApp(Widget child, AuthController auth) {
  return ChangeNotifierProvider<AuthController>.value(
    value: auth,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: Directionality(textDirection: TextDirection.rtl, child: child),
    ),
  );
}
