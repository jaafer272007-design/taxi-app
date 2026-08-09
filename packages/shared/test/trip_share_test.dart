import 'package:flutter_test/flutter_test.dart';
import 'package:shared/shared.dart';

/// The share message is the actual product of «شارك رحلتي»: it is what reaches
/// a person who does not have the app, on a phone we do not control, in a font
/// we did not choose. No golden can cover that, so the text itself is pinned
/// here.
void main() {
  TripShareDetails details({
    String? driverName = 'علي حسن',
    String? make = 'Toyota',
    String? model = 'Corolla',
    String? color = 'أبيض',
    String? plate = '12345 بغداد',
    String? origin = 'Najaf',
    String? dest = 'Karbala',
    int seatCount = 3,
  }) =>
      TripShareDetails(
        originCity: origin,
        destCity: dest,
        // 04:30 UTC = 07:30 Baghdad.
        departureTime: DateTime.utc(2026, 7, 20, 4, 30),
        seatCount: seatCount,
        driverName: driverName,
        vehicleMake: make,
        vehicleModel: model,
        vehicleColor: color,
        plate: plate,
      );

  group('what the recipient reads', () {
    test('carries the plate — the one item that identifies the car', () {
      final msg = buildTripShareMessage(details());
      expect(msg, contains('رقم اللوحة: 12345 بغداد'));
    });

    test('names the driver and describes the car', () {
      final msg = buildTripShareMessage(details());
      expect(msg, contains('السائق: علي حسن'));
      expect(msg, contains('السيارة: Toyota Corolla أبيض'));
    });

    test('renders the route in Arabic, joined by a WORD not an arrow', () {
      final msg = buildTripShareMessage(details());
      expect(msg, contains('من النجف إلى كربلاء'));
      // The bundled Cairo has no arrow glyph and the recipient's font is
      // unknown — an arrow is a tofu box waiting to happen (CLAUDE.md).
      expect(msg, isNot(contains('→')));
      expect(msg, isNot(contains('←')));
    });

    test('states the departure in Baghdad time, Arabic-Indic', () {
      final msg = buildTripShareMessage(details());
      expect(msg, contains('الانطلاق يوم ٢٠ تموز الساعة ٠٧:٣٠'));
    });

    test('states the seat count as a phrase', () {
      expect(buildTripShareMessage(details()), contains('حجزت ٣ مقاعد'));
      // The Arabic dual carries no digit at all — the trap that hides numeral
      // bugs in every fixture built with 2 (CLAUDE.md).
      expect(buildTripShareMessage(details(seatCount: 2)), contains('حجزت مقعدان'));
    });
  });

  group('the ٠-dot hazard, on someone else’s phone', () {
    // `٠` IS a dot, and a bidi-neutral separator can be reordered onto the far
    // side of a number. There is no golden for WhatsApp, so the guard is that
    // the message never produces the shape at all.
    test('no dot-like glyph is ever adjacent to an Arabic-Indic digit', () {
      final msg = buildTripShareMessage(details());
      const dots = ['·', '•', '.', '∙', '‧', '⋅'];
      for (var i = 0; i < msg.length - 1; i++) {
        final a = msg[i];
        final b = msg[i + 1];
        final aDot = dots.contains(a);
        final bDot = dots.contains(b);
        final aDigit = RegExp(r'[٠-٩]').hasMatch(a);
        final bDigit = RegExp(r'[٠-٩]').hasMatch(b);
        expect(aDot && bDigit, isFalse, reason: 'dot before a numeral at $i: "$msg"');
        expect(aDigit && bDot, isFalse, reason: 'numeral before a dot at $i: "$msg"');
      }
    });

    test('no LABEL colon sits immediately before a numeral', () {
      // The distinction is the whole point, and it is why this is a lookbehind
      // rather than a plain `:\s*[٠-٩]`:
      //
      //   SAFE   «الساعة ٠٧:٣٠» — the colon sits BETWEEN two digit runs, so it
      //          is inside one directional run and cannot be reordered out.
      //   UNSAFE «الانطلاق: ٢٠ تموز» — a bidi-NEUTRAL colon with Arabic text on
      //          one side and a numeral on the other resolves to whichever side
      //          the paragraph direction puts it, and `٠` is drawn as a dot.
      //
      // So: a colon NOT preceded by a digit, followed by an Arabic-Indic digit.
      final msg = buildTripShareMessage(details());
      expect(RegExp(r'(?<![٠-٩0-9]):\s*[٠-٩]').hasMatch(msg), isFalse, reason: msg);
      // …and prove the regex can still see the unsafe shape.
      expect(RegExp(r'(?<![٠-٩0-9]):\s*[٠-٩]').hasMatch('الانطلاق: ٢٠ تموز'), isTrue);
    });

    test('the plate keeps its Western digits — it is an identifier', () {
      // Same class as a phone number and a coordinate: it is matched against a
      // metal plate, and Iraqi plates are stamped in Western digits.
      final msg = buildTripShareMessage(details(plate: '12345'));
      expect(msg, contains('رقم اللوحة: 12345'));
      expect(msg, isNot(contains('١٢٣٤٥')));
    });
  });

  group('missing pieces drop their line rather than printing null', () {
    test('no vehicle row at all', () {
      final msg = buildTripShareMessage(
        details(make: null, model: null, color: null, plate: null),
      );
      expect(msg, isNot(contains('السيارة')));
      expect(msg, isNot(contains('رقم اللوحة')));
      expect(msg.toLowerCase(), isNot(contains('null')));
      // Still worth sending: route and time survive.
      expect(msg, contains('من النجف إلى كربلاء'));
    });

    test('a partial vehicle keeps the parts it has', () {
      final msg = buildTripShareMessage(details(model: null, color: null));
      expect(msg, contains('السيارة: Toyota'));
    });

    test('no driver name, no corridor', () {
      final msg = buildTripShareMessage(
        details(driverName: null, origin: null, dest: null),
      );
      expect(msg, isNot(contains('السائق')));
      expect(msg, isNot(contains('الطريق')));
      expect(msg.toLowerCase(), isNot(contains('null')));
    });
  });

  group('the WhatsApp hand-off', () {
    test('addresses NOBODY — the rider picks the recipient in WhatsApp', () {
      final uri = ContactLink.whatsAppShare('مرحباً');
      expect(uri.host, 'wa.me');
      // No number in the path is the point: `wa.me/9647…` opens a chat with
      // THAT person, and there is no code path here that could produce one.
      // (`Uri.parse` normalises the bare `wa.me/?text=` path to `/`.)
      expect(uri.path, anyOf('', '/'));
      expect(RegExp(r'\d').hasMatch(uri.path), isFalse);
      expect(uri.queryParameters['text'], 'مرحباً');
    });

    test('encodes spaces as %20, never as +', () {
      // Uri(queryParameters:) would produce `+`, which WhatsApp renders
      // literally — a shared message full of plus signs.
      final uri = ContactLink.whatsAppShare('a b');
      expect(uri.toString(), contains('%20'));
      expect(uri.toString(), isNot(contains('+')));
    });

    test('keeps the newlines that separate the fields', () {
      final uri = ContactLink.whatsAppShare(buildTripShareMessage(details()));
      expect(uri.toString(), contains('%0A'));
      // Round-trips back to the exact message.
      expect(uri.queryParameters['text'], buildTripShareMessage(details()));
    });
  });
}
