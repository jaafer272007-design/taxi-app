import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rider/auth/name_screen.dart';
import 'package:shared/shared.dart';

import 'support/fakes.dart';

void main() {
  AuthController makeAuth(FakeAuthApi api) {
    final auth = AuthController(api: api, tokenStore: InMemoryTokenStore('jwt'));
    addTearDown(auth.dispose);
    return auth;
  }

  testWidgets('renders the name field and both gender segments', (tester) async {
    final api = FakeAuthApi();
    final auth = makeAuth(api);
    await tester.pumpWidget(wrapApp(const NameScreen(), auth));

    expect(find.text('الاسم الكامل'), findsOneWidget);
    expect(find.text('الجنس'), findsOneWidget);
    expect(find.text('رجل'), findsOneWidget);
    expect(find.text('امرأة'), findsOneWidget);
  });

  testWidgets('a name without a gender shows an error and does not submit',
      (tester) async {
    final api = FakeAuthApi();
    final auth = makeAuth(api);
    await tester.pumpWidget(wrapApp(const NameScreen(), auth));

    await tester.enterText(find.byType(TextField), 'علي حسن');
    await tester.tap(find.text('متابعة'));
    await tester.pump();

    expect(find.text('اختر الجنس للمتابعة.'), findsOneWidget);
    expect(api.lastGender, isNull);
    expect(auth.status, isNot(AuthStatus.authenticated));
  });

  testWidgets('name + gender submits the profile and enters the app',
      (tester) async {
    final api = FakeAuthApi();
    final auth = makeAuth(api);
    await tester.pumpWidget(wrapApp(const NameScreen(), auth));

    await tester.enterText(find.byType(TextField), 'سارة كريم');
    await tester.tap(find.text('امرأة'));
    await tester.pump();
    await tester.tap(find.text('متابعة'));
    await tester.pumpAndSettle();

    expect(api.lastName, 'سارة كريم');
    expect(api.lastGender, Gender.female);
    expect(auth.status, AuthStatus.authenticated);
  });
}
