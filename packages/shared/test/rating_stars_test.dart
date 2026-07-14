import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared/shared.dart';

void main() {
  group('ratingStarFills', () {
    test('4.9 → four full stars and a nearly-full fifth (not empties)', () {
      expect(ratingStarFills(4.9), [1.0, 1.0, 1.0, 1.0, closeTo(0.9, 1e-9)]);
    });

    test('3.5 → three full, one half, one empty', () {
      expect(ratingStarFills(3.5), [1.0, 1.0, 1.0, 0.5, 0.0]);
    });

    test('5.0 → all five full', () {
      expect(ratingStarFills(5.0), [1.0, 1.0, 1.0, 1.0, 1.0]);
    });

    test('0.0 → all five empty', () {
      expect(ratingStarFills(0.0), [0.0, 0.0, 0.0, 0.0, 0.0]);
    });

    test('clamps out-of-range values', () {
      expect(ratingStarFills(-2), [0.0, 0.0, 0.0, 0.0, 0.0]);
      expect(ratingStarFills(7), [1.0, 1.0, 1.0, 1.0, 1.0]);
    });

    test('honours a custom star count', () {
      expect(ratingStarFills(2.25, count: 3), [1.0, 1.0, 0.25]);
    });
  });

  group('RatingStars widget', () {
    Widget host(Widget child) => MaterialApp(
          theme: AppTheme.light(),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(body: Center(child: child)),
          ),
        );

    testWidgets('renders one painted star cell per count', (tester) async {
      await tester.pumpWidget(host(const RatingStars(value: 4.9)));
      // Each star is drawn by its own CustomPaint; assert there are `count`.
      expect(
        find.descendant(
          of: find.byType(RatingStars),
          matching: find.byType(CustomPaint),
        ),
        findsNWidgets(5),
      );
    });

    testWidgets('interactive stars report a 1-based rating on tap',
        (tester) async {
      int? tapped;
      await tester.pumpWidget(
        host(RatingStars(value: 0, onRate: (v) => tapped = v)),
      );
      await tester.pumpAndSettle(); // let the route entrance transition finish
      // Tapping the first star cell (scoped to the widget) reports 1.
      await tester.tap(
        find
            .descendant(
              of: find.byType(RatingStars),
              matching: find.byType(GestureDetector),
            )
            .first,
      );
      expect(tapped, 1);
    });
  });
}
