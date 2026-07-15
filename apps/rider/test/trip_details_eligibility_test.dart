import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rider/trip/trip_details_screen.dart';
import 'package:rider/trip/trip_models.dart';
import 'package:shared/shared.dart';

import 'support/fakes.dart';
import 'support/trip_fakes.dart';

void main() {
  Future<AuthController> authWith(Gender gender) async {
    final api = FakeAuthApi()..meResult = fakeUser(name: 'راكب', gender: gender);
    final auth = AuthController(api: api, tokenStore: InMemoryTokenStore('jwt'));
    addTearDown(auth.dispose);
    await auth.bootstrap();
    return auth;
  }

  Widget host(AuthController auth, Widget child) =>
      ChangeNotifierProvider<AuthController>.value(
        value: auth,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          home:
              Directionality(textDirection: TextDirection.rtl, child: child),
        ),
      );

  testWidgets('male rider cannot book a women/family trip: disabled + note',
      (tester) async {
    final auth = await authWith(Gender.male);
    await tester.pumpWidget(host(
      auth,
      TripDetailsScreen(trip: tripFixture(tripType: TripType.womenFamily)),
    ));

    expect(find.textContaining('مخصّصة للركّاب من النساء'), findsOneWidget);
    final btn = tester.widget<AppButton>(
      find.widgetWithText(AppButton, 'رحلة نسائية-عائلية'),
    );
    expect(btn.onPressed, isNull);
  });

  testWidgets('female rider can book a women/family trip', (tester) async {
    final auth = await authWith(Gender.female);
    await tester.pumpWidget(host(
      auth,
      TripDetailsScreen(trip: tripFixture(tripType: TripType.womenFamily)),
    ));

    final btn = tester.widget<AppButton>(
      find.widgetWithText(AppButton, 'احجز مقعد'),
    );
    expect(btn.onPressed, isNotNull);
    expect(find.textContaining('مخصّصة للركّاب من النساء'), findsNothing);
  });

  testWidgets('any rider can book a general trip', (tester) async {
    final auth = await authWith(Gender.male);
    await tester.pumpWidget(host(auth, TripDetailsScreen(trip: tripFixture())));

    final btn = tester.widget<AppButton>(
      find.widgetWithText(AppButton, 'احجز مقعد'),
    );
    expect(btn.onPressed, isNotNull);
  });
}
