import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared/shared.dart';

/// [ApiClient]'s JWT interceptor — specifically, that it is BOUNDED.
///
/// Dio applies `connectTimeout`/`receiveTimeout` in its adapter, which runs
/// after the whole interceptor chain. Anything awaited in `onRequest` is
/// therefore outside that budget, and the token read goes to the platform
/// keystore. An unbounded await there is not a slow request — it is a request
/// that never completes, which latches [Poller] and silences that screen's
/// refresh for as long as it is open, with no error anywhere.
void main() {
  ApiClient clientWith(TokenStore store) {
    final c = ApiClient(baseUrl: 'http://localhost', tokenStore: store);
    c.dio.httpClientAdapter = _StubAdapter();
    return c;
  }

  test('attaches the JWT when the store answers', () async {
    final c = clientWith(InMemoryTokenStore('jwt-123'));
    final res = await c.dio.get<dynamic>('/anything');
    expect(res.requestOptions.headers['Authorization'], 'Bearer jwt-123');
  });

  test('sends no Authorization header when there is no token', () async {
    final c = clientWith(InMemoryTokenStore());
    final res = await c.dio.get<dynamic>('/anything');
    expect(res.requestOptions.headers.containsKey('Authorization'), isFalse);
  });

  test('a hung token read FAILS the request instead of hanging forever',
      () async {
    // The whole point. Before this bound, `dio.get` here never completed — and
    // neither did the poll that called it.
    final c = clientWith(_HangingTokenStore());

    final stopwatch = Stopwatch()..start();
    await expectLater(
      c.dio.get<dynamic>('/anything'),
      throwsA(isA<DioException>()),
    );
    stopwatch.stop();

    expect(stopwatch.elapsed, lessThan(kTokenReadTimeout * 3),
        reason: 'bounded by kTokenReadTimeout, not left to hang');
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('the failure is a DioException, so mapDioError can speak Arabic',
      () async {
    // An error thrown out of an interceptor is NOT a DioException, so it would
    // sail past every `on DioException` mapper in the API classes and land in a
    // bare `catch (_)` with no type and no message. Rejecting keeps one error
    // shape for the whole app.
    final c = clientWith(_HangingTokenStore());
    try {
      await c.dio.get<dynamic>('/anything');
      fail('should have thrown');
    } on DioException catch (e) {
      final mapped = mapDioError(e);
      expect(mapped.isNetwork, isTrue);
      expect(mapped.message, contains('تعذّر الاتصال'));
    }
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('does NOT send the request unauthenticated when the store hangs',
      () async {
    // Continuing without the header would turn a keystore problem into a 401,
    // and a 401 reads as "your session expired" — which would bounce the user
    // to the login screen over a storage hiccup.
    final adapter = _StubAdapter();
    final c = ApiClient(
      baseUrl: 'http://localhost',
      tokenStore: _HangingTokenStore(),
    );
    c.dio.httpClientAdapter = adapter;

    await expectLater(
      c.dio.get<dynamic>('/anything'),
      throwsA(isA<DioException>()),
    );

    expect(adapter.calls, 0, reason: 'nothing reached the wire');
  }, timeout: const Timeout(Duration(seconds: 30)));
  test('the deadline is disarmed when the request completes', () async {
    // The 45s deadline itself is not unit-tested: waiting it out would stall
    // the suite, and shortening it would test a different number than
    // production ships. The mechanism is verified where it is real — dio wraps
    // every interceptor in `Future.any([work, cancelToken.whenCancel])`
    // (dio_mixin.dart), and apps/rider/e2e/poll_recovery.mjs proves the whole
    // path recovers in a real browser.
    //
    // What IS worth pinning here is the cleanup, because a leak would be
    // silent: without it every single request would leave a live 45s Timer
    // behind. The key is private, hence the literal.
    final c = clientWith(InMemoryTokenStore('jwt'));
    final res = await c.dio.get<dynamic>('/anything');

    expect(res.requestOptions.extra.containsKey('taxi.deadlineTimer'), isFalse);
    expect(res.requestOptions.cancelToken, isNotNull,
        reason: 'it was armed in the first place');
  });

}

/// Never answers — a wedged platform channel.
class _HangingTokenStore implements TokenStore {
  final _forever = Completer<String?>();

  @override
  Future<String?> read() => _forever.future;

  @override
  Future<void> write(String token) async {}

  @override
  Future<void> clear() async {}
}

/// Records whether a request ever got past the interceptors.
class _StubAdapter implements HttpClientAdapter {
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    return ResponseBody.fromString('{}', 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}
