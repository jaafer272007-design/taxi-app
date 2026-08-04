import 'package:driver/trip/driver_trip_models.dart';
import 'package:driver/trip/post_trip_controller.dart';
import 'package:driver/trip/post_trip_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import 'support/driver_fakes.dart';

void main() {
  Future<PostTripController> controller() async {
    final api = FakeDriverTripApi()
      ..corridors = const [najafKarbala, karbalaNajaf];
    final c = PostTripController(api: api, maxSeats: 4);
    await c.loadCorridors();
    return c;
  }

  Widget host(PostTripController c) =>
      ChangeNotifierProvider<PostTripController>.value(
        value: c,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: PostTripScreen(onPosted: () {}),
          ),
        ),
      );

  testWidgets('shows the trip-type selector with the general helper by default',
      (tester) async {
    final c = await controller();
    await tester.pumpWidget(host(c));

    expect(find.text('نوع الرحلة'), findsOneWidget);
    expect(find.text('عامة'), findsOneWidget);
    expect(find.text('نسائية-عائلية'), findsOneWidget);
    expect(find.text('متاحة لجميع الركّاب.'), findsOneWidget);
    expect(c.tripType, TripType.general);
  });

  testWidgets('selecting نسائية-عائلية surfaces the women/family rule',
      (tester) async {
    final c = await controller();
    await tester.pumpWidget(host(c));

    await tester.tap(find.text('نسائية-عائلية'));
    await tester.pump();

    expect(c.tripType, TripType.womenFamily);
    expect(find.textContaining('كل الركّاب يجب أن يكنّ نساءً'), findsOneWidget);
  });

  group('the price the driver sets', () {
    testWidgets('prefills the suggestion in WESTERN digits', (tester) async {
      final c = await controller();
      await tester.pumpWidget(host(c));

      // The field the driver types in: `6000`, never `٦٠٠٠`.
      expect(find.widgetWithText(TextField, '6000'), findsOneWidget);
    });

    testWidgets('shows the suggestion and range without being asked',
        (tester) async {
      final c = await controller();
      await tester.pumpWidget(host(c));

      expect(
        find.textContaining('المعتاد على هذا المسار: ٦٬٠٠٠'),
        findsOneWidget,
      );
      expect(find.textContaining('المسموح: ٣٬٠٠٠ – ١٢٬٠٠٠'), findsOneWidget);
    });

    testWidgets('never puts a dot beside an Arabic-Indic numeral', (tester) async {
      // `٠` IS a dot, so "· ٣" reads as "٣٠" — a driver offering 3 seats saw
      // "٣٠ مقاعد". Being bidi-neutral, the dot can also be reordered onto the
      // wrong side of the number. Guard every rendered string on this screen.
      final c = await controller();
      c.setSeatCount(3);
      await tester.pumpWidget(host(c));

      final offenders = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .whereType<String>()
          .where((s) => RegExp(r'·\s*[٠-٩]|[٠-٩]\s*·').hasMatch(s))
          .toList();

      expect(offenders, isEmpty,
          reason: 'a middle dot touches an Arabic-Indic digit in: $offenders');
    });

    testWidgets('the seat line reads as 3 seats, not 30', (tester) async {
      final c = await controller();
      c.setSeatCount(3);
      await tester.pumpWidget(host(c));

      expect(find.text('إذا امتلأت ٣ مقاعد'), findsOneWidget);
    });

    testWidgets('the full-car total follows what is typed, live',
        (tester) async {
      final c = await controller();
      c.setSeatCount(3);
      await tester.pumpWidget(host(c));

      await tester.enterText(find.byType(TextField), '9000');
      await tester.pump();

      // 9,000 × 3 seats, in Arabic-Indic — no blur needed to see it.
      expect(find.text('٢٧٬٠٠٠ د.ع'), findsOneWidget);
    });

    testWidgets('stays quiet mid-typing, then names the range on blur',
        (tester) async {
      final c = await controller();
      await tester.pumpWidget(host(c));

      await tester.enterText(find.byType(TextField), '9');
      await tester.pump();
      // 9 IQD is out of range, but they are clearly still typing.
      expect(find.textContaining('السعر يجب أن يكون بين'), findsNothing);

      // Blur. enterText focuses the field, so dropping focus is the real
      // "driver moved on" signal the validation waits for.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();

      expect(
        find.textContaining('السعر يجب أن يكون بين ٣٬٠٠٠ و١٢٬٠٠٠'),
        findsOneWidget,
      );
    });

    testWidgets('withholds the total while the price is unusable',
        (tester) async {
      final c = await controller();
      c.setSeatCount(3);
      await tester.pumpWidget(host(c));

      await tester.enterText(find.byType(TextField), '9');
      await tester.pump();

      // An em dash, not a confident number derived from a rejected price.
      expect(find.text('—'), findsOneWidget);
    });

    testWidgets('"use the usual price" restores the suggestion',
        (tester) async {
      final c = await controller();
      await tester.pumpWidget(host(c));

      await tester.enterText(find.byType(TextField), '11000');
      await tester.pump();

      // The card sits at the bottom of a scroll view on a 800×600 test surface.
      final shortcut = find.textContaining('استخدم السعر المعتاد');
      await tester.ensureVisible(shortcut);
      await tester.pump();
      await tester.tap(shortcut);
      await tester.pump();

      expect(c.enteredPrice, 6000);
      expect(find.widgetWithText(TextField, '6000'), findsOneWidget);
      // Nothing left to restore → the shortcut goes away.
      expect(find.textContaining('استخدم السعر المعتاد'), findsNothing);
    });
  });
}
