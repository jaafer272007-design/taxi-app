import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rider/booking/my_bookings_controller.dart';
import 'package:rider/booking/my_bookings_screen.dart';
import 'package:shared/shared.dart';

import 'support/booking_fakes.dart';
import 'support/pool_fakes.dart';
import 'support/fakes.dart';

/// The two optional safety features, at the layer where they break.
///
/// The acceptance criteria here are mostly NEGATIVE — "a rider who saves no
/// emergency contact sees no emergency UI anywhere", "the app never sends to
/// anyone on its own" — and a negative is exactly the kind of guarantee that
/// stops holding silently. So each one is asserted rather than assumed.
///
/// The share and call actions both end in a URL handed to another app. That URL
/// is the part that actually fails, and it fails on the user's phone and
/// nowhere else — which is why `LinkLauncher` is an interface and why these
/// tests read `launcher.opened` instead of mocking a platform channel.
void main() {
  const contact = EmergencyContact(name: 'أم علي', phone: '+9647701112233');

  /// One upcoming booking; [tripStatus] decides whether the trip is under way.
  Future<Widget> host(
    FakeLinkLauncher launcher, {
    EmergencyContact? emergencyContact,
    String tripStatus = 'OPEN',
    int seatCount = 3,
  }) async {
    final api = FakeBookingApi()
      ..listMineResult = [
        mineFixture(
          id: 'b1',
          seatCount: seatCount,
          fare: 6000 * seatCount,
          upcoming: true,
          tripStatus: tripStatus,
          driverName: 'علي حسن',
        ),
      ];
    final c = MyBookingsController(api: api);
    await c.load();
    final auth = await signedInAuth(emergencyContact: emergencyContact);
    return MultiProvider(
      providers: [
        Provider<LinkLauncher>.value(value: launcher),
        ChangeNotifierProvider<MyBookingsController>.value(value: c),
        seatRequestsProvider(),
        ChangeNotifierProvider<AuthController>.value(value: auth),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: MyBookingsScreen(),
        ),
      ),
    );
  }

  group('شارك رحلتي', () {
    testWidgets('opens WhatsApp with the plate in the message, addressed to '
        'nobody', (t) async {
      final launcher = FakeLinkLauncher();
      await t.pumpWidget(await host(launcher));
      await t.pump();

      await t.tap(find.text('شارك رحلتي'));
      await t.pumpAndSettle();

      // The preview comes FIRST. Nothing has left the phone yet.
      expect(launcher.opened, isEmpty);
      expect(find.textContaining('التطبيق لا يرسلها لأحد'), findsOneWidget);

      await t.tap(find.text('إرسال عبر واتساب'));
      await t.pumpAndSettle();

      expect(launcher.opened, hasLength(1));
      final uri = launcher.opened.single;
      expect(uri.host, 'wa.me');
      // No recipient in the path — the rider picks one in WhatsApp itself.
      expect(RegExp(r'\d').hasMatch(uri.path), isFalse);

      final text = uri.queryParameters['text']!;
      // The plate is the item that makes this message worth sending.
      expect(text, contains('رقم اللوحة: E2E-1001'));
      expect(text, contains('السائق: علي حسن'));
      expect(text, contains('السيارة: Toyota Corolla أبيض'));
      expect(text, contains('من النجف إلى كربلاء'));
      expect(text, contains('حجزت ٣ مقاعد'));
    });

    testWidgets('the copy fallback puts the same message on the clipboard',
        (t) async {
      // Capture the real platform call rather than an injected seam: this is
      // the actual channel `Clipboard.setData` uses.
      String? copied;
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(() => t.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));

      final launcher = FakeLinkLauncher();
      await t.pumpWidget(await host(launcher));
      await t.pump();
      await t.tap(find.text('شارك رحلتي'));
      await t.pumpAndSettle();

      await t.tap(find.text('نسخ النص'));
      await t.pumpAndSettle();

      expect(copied, isNotNull);
      expect(copied, contains('رقم اللوحة: E2E-1001'));
      // Confirmed on screen: the clipboard gives no feedback of its own, so
      // without this the button looks broken.
      expect(find.text('تم نسخ النص'), findsOneWidget);
      // A copy is not a send.
      expect(launcher.opened, isEmpty);
    });

    testWidgets('a phone with no WhatsApp says so and keeps the sheet open',
        (t) async {
      final launcher = FakeLinkLauncher.deaf();
      await t.pumpWidget(await host(launcher));
      await t.pump();
      await t.tap(find.text('شارك رحلتي'));
      await t.pumpAndSettle();
      await t.tap(find.text('إرسال عبر واتساب'));
      await t.pumpAndSettle();

      // Points at the fallback rather than dead-ending.
      expect(find.textContaining('يمكنك نسخ النص'), findsOneWidget);
      expect(find.text('نسخ النص'), findsOneWidget);
    });
  });

  group('اتصال طارئ', () {
    testWidgets('a rider who saved nothing sees NO emergency UI at all',
        (t) async {
      final launcher = FakeLinkLauncher();
      // Even mid-trip — the trip being under way is not, on its own, a reason
      // to show anything.
      await t.pumpWidget(await host(launcher, tripStatus: 'EN_ROUTE'));
      await t.pump();

      expect(find.textContaining('اتصال طارئ'), findsNothing);
      // Not a disabled button, not an empty state, and no invitation to set
      // one up. The rest of the card is untouched.
      expect(find.textContaining('جهة اتصال'), findsNothing);
      expect(find.text('شارك رحلتي'), findsOneWidget);
    });

    testWidgets('with a contact saved it still stays hidden before departure',
        (t) async {
      final launcher = FakeLinkLauncher();
      await t.pumpWidget(
          await host(launcher, emergencyContact: contact, tripStatus: 'OPEN'));
      await t.pump();

      expect(find.textContaining('اتصال طارئ'), findsNothing);
    });

    testWidgets('appears once the trip is EN_ROUTE and dials the saved number',
        (t) async {
      final launcher = FakeLinkLauncher();
      await t.pumpWidget(await host(launcher,
          emergencyContact: contact, tripStatus: 'EN_ROUTE'));
      await t.pump();

      // Named, so the rider is not guessing who it calls under pressure.
      expect(find.text('اتصال طارئ — أم علي'), findsOneWidget);

      await t.tap(find.text('اتصال طارئ — أم علي'));
      await t.pumpAndSettle();

      // E164 with the `+`: a local-format number dials fine inside Iraq and
      // fails from a roaming SIM.
      expect(launcher.opened.single, Uri.parse('tel:+9647701112233'));
    });

    testWidgets('a LOCKED trip has not started, so no emergency action',
        (t) async {
      // The departNow trap in its exact shape: a «الآن» trip's departureTime is
      // already in the past, and once its window shuts the trip goes LOCKED
      // with the driver still not moving. Anything keyed off the clock would
      // light this up.
      final launcher = FakeLinkLauncher();
      await t.pumpWidget(await host(launcher,
          emergencyContact: contact, tripStatus: 'LOCKED'));
      await t.pump();

      expect(find.textContaining('اتصال طارئ'), findsNothing);
      // …and cancelling is still allowed here, which is the other half of that
      // rule (CANCELLABLE_BEFORE = OPEN | LOCKED).
      expect(find.text('إلغاء الحجز'), findsOneWidget);
    });

    testWidgets('an EN_ROUTE trip offers no cancel — the server would refuse',
        (t) async {
      final launcher = FakeLinkLauncher();
      await t.pumpWidget(await host(launcher,
          emergencyContact: contact, tripStatus: 'EN_ROUTE'));
      await t.pump();

      expect(find.text('إلغاء الحجز'), findsNothing);
      expect(find.text('تعديل عدد المقاعد'), findsNothing);
    });
  });
}
