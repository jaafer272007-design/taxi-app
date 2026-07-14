import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/api_exception.dart';
import '../core/token_store.dart';
import 'auth_api.dart';
import 'auth_user.dart';

/// Top-level session state.
enum AuthStatus { unknown, onboarding, authenticated }

/// Which onboarding screen is showing.
enum OnboardingStep { phone, otp, name }

/// Owns authentication + the onboarding flow. Business logic lives here; screens
/// only read state (`context.watch`) and call methods (`context.read`).
class AuthController extends ChangeNotifier {
  AuthController({required AuthApi api, required TokenStore tokenStore})
      : _api = api,
        _tokenStore = tokenStore;

  final AuthApi _api;
  final TokenStore _tokenStore;

  /// Seconds a resend is blocked after each OTP request (a client-side courtesy
  /// on top of the server's per-phone rate limit).
  static const int resendCooldownSeconds = 60;

  AuthStatus _status = AuthStatus.unknown;
  OnboardingStep _step = OnboardingStep.phone;
  bool _busy = false;
  String? _error;
  String _phone = '';
  AuthUser? _user;
  int _resendSeconds = 0;
  Timer? _resendTimer;

  AuthStatus get status => _status;
  OnboardingStep get step => _step;
  bool get busy => _busy;
  String? get error => _error;

  /// The E.164 phone being verified (for display on the OTP screen).
  String get phone => _phone;
  AuthUser? get user => _user;
  int get resendSeconds => _resendSeconds;
  bool get canResend => _resendSeconds == 0 && !_busy;

  /// Restore a session on launch. A valid JWT with a name skips onboarding
  /// entirely; a valid JWT without a name resumes at the name step.
  Future<void> bootstrap() async {
    final token = await _tokenStore.read();
    if (token == null || token.isEmpty) {
      _enterOnboarding(OnboardingStep.phone);
      return;
    }
    try {
      final user = await _api.me();
      _user = user;
      if (user.hasName) {
        _status = AuthStatus.authenticated;
        notifyListeners();
      } else {
        _enterOnboarding(OnboardingStep.name);
      }
    } catch (_) {
      await _tokenStore.clear();
      _enterOnboarding(OnboardingStep.phone);
    }
  }

  /// Step 1 → request an OTP for [normalizedPhone] (`+9647XXXXXXXXX`).
  Future<void> requestOtp(String normalizedPhone) async {
    _phone = normalizedPhone;
    await _run(() async {
      await _api.requestOtp(normalizedPhone);
      _step = OnboardingStep.otp;
      _startResendCooldown();
    });
  }

  /// Re-request the OTP for the same phone (only when the cooldown has elapsed).
  Future<void> resendOtp() async {
    if (!canResend) return;
    await _run(() async {
      await _api.requestOtp(_phone);
      _startResendCooldown();
    });
  }

  /// Step 2 → verify [code], store the JWT, then either finish (has name) or
  /// advance to the name step (new user).
  Future<void> verifyOtp(String code) async {
    await _run(() async {
      final session = await _api.verifyOtp(_phone, code);
      await _tokenStore.write(session.accessToken);
      _user = session.user;
      if (session.user.hasName) {
        _stopResendTimer();
        _status = AuthStatus.authenticated;
      } else {
        _step = OnboardingStep.name;
      }
    });
  }

  /// Step 3 (new users) → save the name and enter the app.
  Future<void> submitName(String name) async {
    await _run(() async {
      _user = await _api.updateName(name);
      _stopResendTimer();
      _status = AuthStatus.authenticated;
    });
  }

  /// "تغيير الرقم" — back to phone entry.
  void changePhone() {
    _stopResendTimer();
    _resendSeconds = 0;
    _error = null;
    _step = OnboardingStep.phone;
    notifyListeners();
  }

  /// Clear the visible error (e.g. when the user edits the code after a failure).
  void clearError() {
    if (_error != null) {
      _error = null;
      notifyListeners();
    }
  }

  // ── internals ───────────────────────────────────────────────────────────
  void _enterOnboarding(OnboardingStep step) {
    _status = AuthStatus.onboarding;
    _step = step;
    notifyListeners();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return; // ignore re-entrancy (e.g. auto-submit + button tap)
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await action();
    } on ApiException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'حدث خطأ غير متوقع. حاول مرة أخرى.';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void _startResendCooldown() {
    _resendSeconds = resendCooldownSeconds;
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _resendSeconds--;
      if (_resendSeconds <= 0) {
        _resendSeconds = 0;
        timer.cancel();
      }
      notifyListeners();
    });
  }

  void _stopResendTimer() {
    _resendTimer?.cancel();
    _resendTimer = null;
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    super.dispose();
  }
}
