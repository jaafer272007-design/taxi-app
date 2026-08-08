import 'dart:async';

import 'package:dio/dio.dart';

import 'api_exception.dart';
import 'token_store.dart';

/// How long the JWT read may take before the request is abandoned.
///
/// **The one await on the request path that Dio's timeouts do not cover.** Dio
/// applies `connectTimeout`/`receiveTimeout` in the ADAPTER, which runs after
/// the whole interceptor chain — so anything awaited in `onRequest` is outside
/// that budget. Reading the token goes to the platform keystore (and on web to
/// WebCrypto); a wedged platform channel there would hang the request forever,
/// and a background poll that never completes is invisible: it shows no error,
/// leaves the last good data on screen, and silences that screen's poller.
///
/// 5s is generous for a keystore read, so a slow store surfaces as an ordinary
/// failed request long before [kRequestDeadline] has to step in.
const Duration kTokenReadTimeout = Duration(seconds: 5);

/// A TOTAL deadline for one request, enforced by cancelling it.
///
/// **`connectTimeout` + `receiveTimeout` is not a total bound**, and assuming it
/// was is the trap here. On web it happens to be one — `dio_web_adapter` sets
/// `xhr.timeout = connectTimeout + receiveTimeout`, a real ceiling. On Android
/// it is not: `receiveTimeout` is an INTER-CHUNK idle timer, re-armed on every
/// chunk (dio `response_stream_handler.dart`: "between received chunks"), so a
/// server dripping a byte every 14s keeps one request alive for ever. Nothing
/// else on the IO path caps the body read.
///
/// So the bound has to come from us. Dio evaluates `requestOptions.cancelToken`
/// LAZILY, inside the closure it wraps each interceptor in
/// (`dio_mixin.dart` `requestInterceptorWrapper` → `listenCancelForAsyncTask`,
/// which is `Future.any([work, cancelToken.whenCancel])`) — so a token armed by
/// the FIRST interceptor bounds every interceptor after it, including the JWT
/// read, and the adapter too.
///
/// This is what makes the whole design safe against "polls never stack": the
/// request is **cancelled**, not abandoned, so when [Poller] recovers there is
/// provably nothing still on the wire to collide with.
///
/// 45s sits above web's own 30s ceiling, so it never pre-empts a request the
/// browser would have finished, and caps the Android drip case.
const Duration kRequestDeadline = Duration(seconds: 45);

const String _deadlineTimerKey = 'taxi.deadlineTimer';

/// Owns the shared [Dio] instance used by every API client: base URL, timeouts,
/// a total per-request deadline ([kRequestDeadline]) and a JWT interceptor that
/// attaches the stored token to each request (harmless on public endpoints,
/// required for authenticated ones).
class ApiClient {
  ApiClient({required String baseUrl, required TokenStore tokenStore})
      : dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
          contentType: Headers.jsonContentType,
        )) {
    // FIRST, so its CancelToken is already on the options when the JWT
    // interceptor below runs — that ordering is the whole point (see
    // [kRequestDeadline]).
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          // Never clobber a caller's own token — a screen that cancels its own
          // request on dispose still owns that decision.
          if (options.cancelToken == null) {
            final token = CancelToken();
            options.cancelToken = token;
            options.extra[_deadlineTimerKey] = Timer(kRequestDeadline, () {
              if (!token.isCancelled) {
                token.cancel('request exceeded $kRequestDeadline');
              }
            });
          }
          handler.next(options);
        },
        // Disarm on the way out, or every request would leave a live timer
        // behind for its full deadline.
        onResponse: (response, handler) {
          _disarm(response.requestOptions);
          handler.next(response);
        },
        onError: (error, handler) {
          _disarm(error.requestOptions);
          handler.next(error);
        },
      ),
    );

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          String? token;
          try {
            token = await tokenStore.read().timeout(kTokenReadTimeout);
          } catch (e) {
            // REJECT, don't continue unauthenticated. Sending the request
            // without the header would turn a storage problem into a 401, and
            // a 401 reads as "your session expired" — a lie that would send the
            // user back to the login screen over a keystore hiccup.
            //
            // Rejecting with a DioException (rather than letting the raw error
            // escape) is also what keeps the failure mappable: every API class
            // catches `on DioException`, so an error thrown out of an
            // interceptor would otherwise sail past `mapDioError` and land in a
            // bare `catch (_)` with no message and no type.
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.connectionError,
                error: e,
              ),
            );
            return;
          }
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
      ),
    );
  }

  final Dio dio;
}

void _disarm(RequestOptions options) {
  (options.extra.remove(_deadlineTimerKey) as Timer?)?.cancel();
}

const _networkTypes = {
  DioExceptionType.connectionTimeout,
  DioExceptionType.sendTimeout,
  DioExceptionType.receiveTimeout,
  DioExceptionType.connectionError,
};

/// Maps a [DioException] to a user-facing [ApiException] (always Arabic).
ApiException mapDioError(DioException e) {
  if (_networkTypes.contains(e.type) || e.response == null) {
    return const ApiException(
      'تعذّر الاتصال بالخادم. تحقّق من الإنترنت وحاول مرة أخرى.',
      isNetwork: true,
    );
  }
  final status = e.response!.statusCode;
  final data = e.response!.data;
  return ApiException(
    _serverMessage(data, status),
    statusCode: status,
    code: data is Map && data['code'] is String ? data['code'] as String : null,
    details: data is Map ? Map<String, dynamic>.from(data) : const {},
  );
}

/// Prefer the backend's Arabic message; fall back by status code.
String _serverMessage(dynamic data, int? status) {
  if (data is Map) {
    final msg = data['message'];
    if (msg is String && msg.trim().isNotEmpty) return msg;
    if (msg is List && msg.isNotEmpty) return msg.first.toString();
  }
  return switch (status) {
    401 => 'انتهت الجلسة. سجّل الدخول من جديد.',
    403 => 'ليس لديك صلاحية لهذا الإجراء.',
    404 => 'غير موجود.',
    429 => 'محاولات كثيرة. انتظر قليلاً ثم حاول مرة أخرى.',
    _ => 'حدث خطأ غير متوقع. حاول مرة أخرى.',
  };
}
