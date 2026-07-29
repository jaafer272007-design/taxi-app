import 'package:driver/earnings/earnings_controller.dart';
import 'package:driver/earnings/earnings_screen.dart';
import 'package:driver/trip/driver_trip_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import 'support/driver_fakes.dart';

/// The earnings screen's contract with the driver: **the numbers add up**.
/// A driver holding cash has to be able to check the app against their pocket,
/// so the day headers must be the arithmetic of the rows printed under them.
void main() {
  Widget host(EarningsController c) =>
      ChangeNotifierProvider<EarningsController>.value(
        value: c,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: EarningsScreen(),
          ),
        ),
      );

  Future<EarningsController> loaded() async {
    final ledger = [
      earningsRecordFixture(
          id: 'e1', amount: 12000, dayUtc: 20, hourUtc: 6, minute: 15),
      earningsRecordFixture(
          id: 'e2', amount: 6000, dayUtc: 20, hourUtc: 4, minute: 30),
      earningsRecordFixture(id: 'e3', amount: 30000, dayUtc: 19, hourUtc: 9),
    ];
    final api = FakeDriverTripApi()
      ..earningsByRange = {
        'today': DriverEarnings(total: 18000, records: ledger.take(2).toList()),
        'all': DriverEarnings(total: 48000, records: ledger),
      };
    final c = EarningsController(api: api);
    await c.load();
    return c;
  }

  testWidgets('today\'s take carries its trip count', (t) async {
    await t.pumpWidget(host(await loaded()));
    await t.pump();

    expect(find.text('أرباح اليوم'), findsOneWidget);
    expect(find.text('١٨٬٠٠٠'), findsOneWidget);
    // The denominator: a total with no trip count is unverifiable. Arabic dual.
    expect(find.text('رحلتان · نقداً'), findsOneWidget);
  });

  testWidgets('the ledger is grouped by day and each header sums its own rows',
      (t) async {
    await t.pumpWidget(host(await loaded()));
    await t.pump();

    // Absolute dates, never "اليوم"/"أمس" — a driver reconciles against a
    // calendar, and a relative label would change meaning overnight.
    expect(find.text('٢٠ تموز'), findsOneWidget);
    expect(find.text('١٩ تموز'), findsOneWidget);
    // ٢٠ تموز = 12,000 + 6,000; ١٩ تموز = 30,000.
    expect(find.text('١٨٬٠٠٠ د.ع'), findsWidgets);
    expect(find.text('٣٠٬٠٠٠ د.ع'), findsWidgets);
    // Individual collections, newest first within the day.
    expect(find.text('١٢٬٠٠٠ د.ع'), findsOneWidget);
    expect(find.text('٦٬٠٠٠ د.ع'), findsOneWidget);
    expect(find.text('نقد محصّل'), findsNWidgets(3));
  });

  testWidgets('the all-time strip states how many trips it covers', (t) async {
    await t.pumpWidget(host(await loaded()));
    await t.pump();

    expect(find.text('الإجمالي منذ البداية'), findsOneWidget);
    expect(find.text('٣ رحلات'), findsOneWidget);
    expect(find.text('٤٨٬٠٠٠ د.ع'), findsWidgets);
  });

  testWidgets('says plainly that the app holds no money', (t) async {
    await t.pumpWidget(host(await loaded()));
    await t.pump();

    expect(find.textContaining('التطبيق لا يحتفظ بأي مبلغ لك'), findsOneWidget);
  });

  testWidgets('an empty ledger explains itself instead of showing zeros only',
      (t) async {
    final api = FakeDriverTripApi()
      ..earningsByRange = {
        'today': const DriverEarnings(total: 0, records: []),
        'all': const DriverEarnings(total: 0, records: []),
      };
    final c = EarningsController(api: api);
    await c.load();
    await t.pumpWidget(host(c));
    await t.pump();

    expect(find.text('لا توجد أرباح بعد'), findsOneWidget);
    expect(find.text('ستظهر أرباحك هنا بعد إتمام أول رحلة.'), findsOneWidget);
  });
}
