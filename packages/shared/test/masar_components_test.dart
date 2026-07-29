import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared/shared.dart';

/// Behaviour of the Masar signature components (PR 2).
void main() {
  Widget host(Widget child) => MaterialApp(
        theme: AppTheme.light(),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: Center(child: child)),
        ),
      );

  group('SeatGlyphs', () {
    testWidgets('is announced as availability out of the total',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(const SeatGlyphs(total: 4, available: 3)));
      // The glyph strip is decorative to a screen reader; the count is spoken.
      expect(find.bySemanticsLabel('٣ مقاعد متاحة من ٤'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('is exactly `total` glyphs wide', (tester) async {
      await tester.pumpWidget(host(const SeatGlyphs(total: 4, available: 3)));
      // 4 glyphs at 13 wide with three 5px gaps.
      expect(tester.getSize(find.byType(SeatGlyphs)).width,
          closeTo(4 * 13 + 3 * 5, 0.5));
    });

    test('label uses Arabic-Indic digits and the dual form', () {
      expect(SeatGlyphs.label(0), 'لا مقاعد متاحة');
      expect(SeatGlyphs.label(1), 'مقعد واحد فقط');
      // Arabic has a dual — two seats is not "٢ مقاعد".
      expect(SeatGlyphs.label(2), 'مقعدان متاحان');
      expect(SeatGlyphs.label(3), '٣ مقاعد متاحة');
      expect(SeatGlyphs.label(4), '٤ مقاعد متاحة');
    });

    test('scarcity is exactly the last seat', () {
      expect(SeatGlyphs.isScarce(0), isFalse);
      expect(SeatGlyphs.isScarce(1), isTrue);
      expect(SeatGlyphs.isScarce(2), isFalse);
    });

    testWidgets('clamps an out-of-range availability', (tester) async {
      await tester.pumpWidget(host(const SeatGlyphs(total: 3, available: 9)));
      expect(tester.takeException(), isNull);
    });

    testWidgets('SeatAvailability shows the label beside the glyphs',
        (tester) async {
      await tester
          .pumpWidget(host(const SeatAvailability(total: 4, available: 1)));
      expect(find.text('مقعد واحد فقط'), findsOneWidget);
      expect(find.byType(SeatGlyphs), findsOneWidget);
    });
  });

  group('RouteRail', () {
    testWidgets('renders both endpoints\' content', (tester) async {
      await tester.pumpWidget(host(const SizedBox(
        width: 300,
        child: RouteRail(
          origin: Text('النجف'),
          destination: Text('كربلاء'),
        ),
      )));
      expect(find.text('النجف'), findsOneWidget);
      expect(find.text('كربلاء'), findsOneWidget);
    });

    testWidgets('lays out in RTL without overflowing', (tester) async {
      await tester.pumpWidget(host(const SizedBox(
        width: 320,
        child: RouteRail(
          divided: true,
          origin: Text('النجف'),
          destination: Text('كربلاء'),
        ),
      )));
      expect(tester.takeException(), isNull);
    });

    testWidgets('both variants build', (tester) async {
      for (final v in RouteRailVariant.values) {
        await tester.pumpWidget(host(SizedBox(
          width: 300,
          child: RouteRail(
            variant: v,
            origin: const Text('أ'),
            destination: const Text('ب'),
          ),
        )));
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('FloatingPillNav', () {
    const items = [
      FloatingPillNavItem(icon: AppIcons.search, label: 'ابحث'),
      FloatingPillNavItem(icon: AppIcons.seat, label: 'حجوزاتي'),
      FloatingPillNavItem(icon: AppIcons.user, label: 'حسابي'),
    ];

    testWidgets('renders every tab label', (tester) async {
      await tester.pumpWidget(host(
        FloatingPillNav(items: items, currentIndex: 0, onSelect: (_) {}),
      ));
      for (final i in items) {
        expect(find.text(i.label), findsOneWidget);
      }
    });

    testWidgets('reports the tapped index', (tester) async {
      int? picked;
      await tester.pumpWidget(host(
        FloatingPillNav(
          items: items,
          currentIndex: 0,
          onSelect: (i) => picked = i,
        ),
      ));
      await tester.tap(find.text('حسابي'));
      expect(picked, 2);
    });

    testWidgets('every tab meets the 48dp minimum target', (tester) async {
      await tester.pumpWidget(host(
        FloatingPillNav(items: items, currentIndex: 1, onSelect: (_) {}),
      ));
      for (final i in items) {
        final size = tester.getSize(
          find.ancestor(
            of: find.text(i.label),
            matching: find.byType(ConstrainedBox),
          ).first,
        );
        expect(size.width, greaterThanOrEqualTo(48.0),
            reason: '${i.label} tab is only ${size.width}dp wide');
        expect(size.height, greaterThanOrEqualTo(48.0),
            reason: '${i.label} tab is only ${size.height}dp tall');
      }
    });

    testWidgets('marks the current tab selected for assistive tech',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(
        FloatingPillNav(items: items, currentIndex: 1, onSelect: (_) {}),
      ));
      expect(
        find.bySemanticsLabel('حجوزاتي'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('also fits four tabs (the driver shell)', (tester) async {
      await tester.pumpWidget(host(
        FloatingPillNav(
          currentIndex: 3,
          onSelect: (_) {},
          items: const [
            FloatingPillNavItem(icon: AppIcons.plusCircle, label: 'انشر'),
            FloatingPillNavItem(icon: AppIcons.route, label: 'رحلاتي'),
            FloatingPillNavItem(icon: AppIcons.wallet, label: 'أرباحي'),
            FloatingPillNavItem(icon: AppIcons.user, label: 'حسابي'),
          ],
        ),
      ));
      expect(tester.takeException(), isNull);
    });
  });
}
