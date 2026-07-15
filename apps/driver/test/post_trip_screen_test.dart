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
}
