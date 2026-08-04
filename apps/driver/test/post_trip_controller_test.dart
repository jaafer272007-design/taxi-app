import 'package:driver/trip/driver_trip_models.dart';
import 'package:driver/trip/post_trip_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared/shared.dart';

import 'support/driver_fakes.dart';

PostTripController _controller(FakeDriverTripApi api, {int maxSeats = 4}) =>
    PostTripController(api: api, maxSeats: maxSeats);

void main() {
  group('PostTripController', () {
    test('loadCorridors filters inactive corridors and picks the default pair',
        () async {
      final api = FakeDriverTripApi()
        ..corridors = const [
          najafKarbala,
          karbalaNajaf,
          Corridor(
            id: 'c9',
            originCity: 'Baghdad',
            destCity: 'Basra',
            active: false,
            suggestedPricePerSeat: 1000,
            minPricePerSeat: 500,
            maxPricePerSeat: 2000,
          ),
        ];
      final c = _controller(api);
      await c.loadCorridors();
      expect(c.corridorsLoad, CorridorsLoad.ready);
      expect(c.corridors.length, 2); // inactive filtered out
      expect(c.origin, 'Najaf');
      expect(c.dest, 'Karbala');
      expect(c.matchedCorridor, najafKarbala);
      // The suggestion is prefilled into the price field, ready to accept.
      expect(c.suggestedPrice, 6000);
      expect(c.priceInput, '6000');
      expect(c.enteredPrice, 6000);
    });

    test('swapCities resolves the reverse corridor', () async {
      final api = FakeDriverTripApi()..corridors = const [najafKarbala, karbalaNajaf];
      final c = _controller(api);
      await c.loadCorridors();
      c.swapCities();
      expect(c.origin, 'Karbala');
      expect(c.dest, 'Najaf');
      expect(c.matchedCorridor, karbalaNajaf);
    });

    test('a pair with no active corridor blocks posting (clear notice)',
        () async {
      final api = FakeDriverTripApi()..corridors = const [najafKarbala];
      final c = _controller(api);
      await c.loadCorridors();

      c.setOrigin('Baghdad');
      c.setDest('Basra');
      expect(c.matchedCorridor, isNull);
      expect(c.noCorridorForPair, isTrue);
      expect(c.canSubmit, isFalse);
      // No corridor → no suggestion to prefill, and the field is cleared rather
      // than left holding a price for a route that no longer applies.
      expect(c.suggestedPrice, 0);
      expect(c.priceInput, isEmpty);
    });

    test('seat count is capped at the vehicle seats', () async {
      final api = FakeDriverTripApi()..corridors = const [najafKarbala];
      final c = _controller(api, maxSeats: 3);
      await c.loadCorridors();
      expect(c.seatCount, 1);
      c.incrementSeat();
      c.incrementSeat();
      expect(c.seatCount, 3);
      c.incrementSeat(); // capped
      expect(c.seatCount, 3);
      expect(c.canIncrement, isFalse);
      c.setSeatCount(99);
      expect(c.seatCount, 3);
    });

    test('submit (الآن) sends departNow=true and no departureTime', () async {
      final api = FakeDriverTripApi()..corridors = const [najafKarbala];
      final c = _controller(api, maxSeats: 4);
      await c.loadCorridors();
      c.setSeatCount(2);
      expect(c.mode, DepartMode.now);
      expect(c.canSubmit, isTrue);

      final ok = await c.submit();

      expect(ok, isTrue);
      expect(api.postCalls, 1);
      expect(api.lastDepartNow, isTrue);
      expect(api.lastDepartureTime, isNull);
      expect(api.lastSeatsTotal, 2);
      expect(api.lastCorridorId, 'c1');
      expect(api.lastPricePerSeat, 6000); // the prefilled suggestion
      expect(c.posted, isNotNull);
    });

    test('scheduled needs a chosen time; then sends departureTime', () async {
      final api = FakeDriverTripApi()..corridors = const [najafKarbala];
      final c = _controller(api);
      await c.loadCorridors();
      c.setMode(DepartMode.scheduled);
      expect(c.canSubmit, isFalse); // no time chosen yet

      c.setScheduledAt(DateTime.utc(2026, 7, 20, 10, 0));
      expect(c.canSubmit, isTrue);

      final ok = await c.submit();
      expect(ok, isTrue);
      expect(api.lastDepartNow, isFalse);
      expect(api.lastDepartureTime, isNotNull);
    });

    test('trip type defaults to general and is sent on submit', () async {
      final api = FakeDriverTripApi()..corridors = const [najafKarbala];
      final c = _controller(api);
      await c.loadCorridors();
      expect(c.tripType, TripType.general);

      await c.submit();
      expect(api.lastTripType, TripType.general);
    });

    test('setTripType(womenFamily) is sent on submit', () async {
      final api = FakeDriverTripApi()..corridors = const [najafKarbala];
      final c = _controller(api);
      await c.loadCorridors();

      c.setTripType(TripType.womenFamily);
      expect(c.tripType, TripType.womenFamily);

      final ok = await c.submit();
      expect(ok, isTrue);
      expect(api.lastTripType, TripType.womenFamily);
    });

    test('submit error surfaces the backend message', () async {
      final api = FakeDriverTripApi()
        ..corridors = const [najafKarbala]
        ..postError = const ApiException(
          'يجب اعتماد حسابك كسائق قبل إعلان الرحلات.',
          statusCode: 403,
        );
      final c = _controller(api);
      await c.loadCorridors();
      final ok = await c.submit();
      expect(ok, isFalse);
      expect(c.error, contains('اعتماد حسابك'));
    });
  });

  group('PostTripController — the driver sets the price', () {
    Future<PostTripController> ready(
      FakeDriverTripApi api, {
      List<Corridor> corridors = const [najafKarbala, karbalaNajaf],
    }) async {
      api.corridors = corridors;
      final c = _controller(api);
      await c.loadCorridors();
      return c;
    }

    test('prefills the corridor suggestion, in Western digits', () async {
      final c = await ready(FakeDriverTripApi());

      // Western, because this is an INPUT — the locked numerals rule.
      expect(c.priceInput, '6000');
      expect(c.enteredPrice, 6000);
      expect(c.priceValid, isTrue);
      expect(c.minPrice, 3000);
      expect(c.maxPrice, 12000);
    });

    test('sends the price the driver typed, not the suggestion', () async {
      final api = FakeDriverTripApi();
      final c = await ready(api);

      c.setPriceInput('9500');
      expect(await c.submit(), isTrue);

      expect(api.lastPricePerSeat, 9500);
    });

    test('stays silent while typing, and speaks up on blur', () async {
      final c = await ready(FakeDriverTripApi());

      // Mid-typing "1" of "12000" is out of range, but saying so now would
      // teach the driver to distrust the field.
      c.setPriceInput('1');
      expect(c.priceError, isNull);

      c.markPriceTouched();
      expect(c.priceError, isNotNull);
    });

    test('the range error names the range, in Arabic-Indic numerals', () async {
      final c = await ready(FakeDriverTripApi());

      c.setPriceInput('999');
      c.markPriceTouched();

      // ٣٬٠٠٠ … ١٢٬٠٠٠ — never the Western digits the API speaks.
      expect(c.priceError, contains('٣٬٠٠٠'));
      expect(c.priceError, contains('١٢٬٠٠٠'));
      expect(c.priceError, isNot(contains('3000')));
    });

    test('accepts both edges of the band and rejects one dinar outside',
        () async {
      final c = await ready(FakeDriverTripApi());

      for (final edge in ['3000', '12000']) {
        c.setPriceInput(edge);
        expect(c.priceValid, isTrue, reason: '$edge should be allowed');
      }
      for (final outside in ['2999', '12001']) {
        c.setPriceInput(outside);
        expect(c.priceValid, isFalse, reason: '$outside should be rejected');
      }
    });

    test('an empty or non-numeric price blocks submit', () async {
      final api = FakeDriverTripApi();
      final c = await ready(api);

      c.setPriceInput('');
      expect(c.enteredPrice, isNull);
      expect(c.canSubmit, isFalse);

      expect(await c.submit(), isFalse);
      expect(api.postCalls, 0);
      // Pressing submit counts as touching it, so the driver is told why.
      expect(c.priceError, isNotNull);
    });

    test('a zero price is rejected, not treated as free', () async {
      final c = await ready(FakeDriverTripApi());

      c.setPriceInput('0');
      expect(c.enteredPrice, isNull);
      expect(c.priceValid, isFalse);
    });

    test('normalises Arabic-Indic digits if they ever reach the field',
        () async {
      // The keyboard emits Western digits, but a paste can carry ٦٠٠٠. The wire
      // format is always Western.
      final api = FakeDriverTripApi();
      final c = await ready(api);

      c.setPriceInput('٩٠٠٠');
      expect(c.enteredPrice, 9000);
      expect(await c.submit(), isTrue);
      expect(api.lastPricePerSeat, 9000);
    });

    test('withholds the full-car total while the price is unusable', () async {
      final c = await ready(FakeDriverTripApi());
      c.setSeatCount(3);
      expect(c.fullCarTotal, 18000);

      c.setPriceInput('999');
      // A confident total from a price the server will reject is worse than none.
      expect(c.fullCarTotal, isNull);
    });

    test('the total follows the price live, without waiting for blur',
        () async {
      final c = await ready(FakeDriverTripApi());
      c.setSeatCount(4);

      c.setPriceInput('7000');
      expect(c.fullCarTotal, 28000);
      expect(c.priceError, isNull); // feedback, not judgement
    });

    test('re-prefills when the route changes — a price is per-route', () async {
      final c = await ready(
        FakeDriverTripApi(),
        corridors: const [najafKarbala, karbalaNajaf, fixedPriceCorridor],
      );

      c.setPriceInput('11000');
      c.setDest('Baghdad'); // Najaf → Baghdad, suggestion 8000

      expect(c.matchedCorridor, fixedPriceCorridor);
      expect(c.priceInput, '8000');
    });

    test('a fixed-price corridor (min == max) says ثابت, not a range',
        () async {
      final c = await ready(
        FakeDriverTripApi(),
        corridors: const [najafKarbala, fixedPriceCorridor],
      );
      c.setDest('Baghdad');

      c.setPriceInput('9000');
      c.markPriceTouched();

      expect(c.priceError, contains('ثابت'));
      expect(c.priceError, contains('٨٬٠٠٠'));
    });

    test('"use the usual price" restores the suggestion and clears the error',
        () async {
      final c = await ready(FakeDriverTripApi());

      c.setPriceInput('50');
      c.markPriceTouched();
      expect(c.priceError, isNotNull);
      expect(c.canUseSuggestedPrice, isTrue);

      c.useSuggestedPrice();

      expect(c.priceInput, '6000');
      expect(c.priceError, isNull);
      // Nothing left to restore, so the shortcut hides itself.
      expect(c.canUseSuggestedPrice, isFalse);
    });

    test('maps the server range rejection to the SAME Arabic message',
        () async {
      // The admin may have re-priced the corridor since this form loaded, so
      // the server can reject a price the client thought was fine.
      final api = FakeDriverTripApi()
        ..postError = const ApiException(
          'السعر يجب أن يكون بين 8000 و 20000 دينار للمقعد.',
          statusCode: 400,
          code: 'TRIP_PRICE_OUT_OF_RANGE',
          details: {'minPricePerSeat': 8000, 'maxPricePerSeat': 20000},
        );
      final c = await ready(api);

      expect(await c.submit(), isFalse);

      // Under the price field (where the fix is), not in the generic banner…
      expect(c.error, isNull);
      // …and re-rendered in Arabic-Indic, with the SERVER's bounds.
      expect(c.priceError, contains('٨٬٠٠٠'));
      expect(c.priceError, contains('٢٠٬٠٠٠'));
      expect(c.priceError, isNot(contains('8000')));
    });

    test('editing the price clears the stale server rejection', () async {
      final api = FakeDriverTripApi()
        ..postError = const ApiException(
          'out of range',
          statusCode: 400,
          code: 'TRIP_PRICE_OUT_OF_RANGE',
          details: {'minPricePerSeat': 8000, 'maxPricePerSeat': 20000},
        );
      final c = await ready(api);
      await c.submit();
      expect(c.priceError, isNotNull);

      c.setPriceInput('9000');

      // The rejection described a value they have now changed.
      expect(c.priceError, isNull);
    });

    test('a non-price 400 still surfaces in the general error banner',
        () async {
      final api = FakeDriverTripApi()
        ..postError = const ApiException(
          'هذا الممر غير مفعّل حالياً.',
          statusCode: 400,
        );
      final c = await ready(api);

      expect(await c.submit(), isFalse);
      expect(c.error, contains('غير مفعّل'));
      expect(c.priceError, isNull);
    });
  });

  group('default city pair at full-grid scale', () {
    test('opens on the flagship pair, not whichever sorts first', () async {
      // 306 corridors means the API's first row is alphabetical accident.
      final api = FakeDriverTripApi()
        ..corridors = const [
          Corridor(
            id: 'c-amarah',
            originCity: 'Amarah',
            destCity: 'Baghdad',
            active: true,
            suggestedPricePerSeat: 30000,
            minPricePerSeat: 18000,
            maxPricePerSeat: 48000,
          ),
          najafKarbala,
          karbalaNajaf,
        ];
      final c = _controller(api);

      await c.loadCorridors();

      expect(c.origin, 'Najaf');
      expect(c.dest, 'Karbala');
      // …and the price prefills from the flagship corridor, not the accident.
      expect(c.priceInput, '6000');
    });

    test('falls back to the first active corridor when the flagship is gone',
        () async {
      final api = FakeDriverTripApi()
        ..corridors = const [
          Corridor(
            id: 'c-amarah',
            originCity: 'Amarah',
            destCity: 'Baghdad',
            active: true,
            suggestedPricePerSeat: 30000,
            minPricePerSeat: 18000,
            maxPricePerSeat: 48000,
          ),
        ];
      final c = _controller(api);

      await c.loadCorridors();

      expect(c.origin, 'Amarah');
      expect(c.dest, 'Baghdad');
      expect(c.priceInput, '30000');
      expect(c.canSubmit, isTrue);
    });

    test('a deactivated flagship is skipped, not selected', () async {
      // loadCorridors filters inactive first, so an admin disabling
      // Najaf→Karbala must not leave the form pointing at a dead corridor.
      final api = FakeDriverTripApi()
        ..corridors = const [
          Corridor(
            id: 'c1',
            originCity: 'Najaf',
            destCity: 'Karbala',
            active: false,
            suggestedPricePerSeat: 12000,
            minPricePerSeat: 7000,
            maxPricePerSeat: 19000,
          ),
          Corridor(
            id: 'c-amarah',
            originCity: 'Amarah',
            destCity: 'Baghdad',
            active: true,
            suggestedPricePerSeat: 30000,
            minPricePerSeat: 18000,
            maxPricePerSeat: 48000,
          ),
        ];
      final c = _controller(api);

      await c.loadCorridors();

      expect(c.origin, 'Amarah');
      expect(c.matchedCorridor?.active, isTrue);
    });
  });
}
