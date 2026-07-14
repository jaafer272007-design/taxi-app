import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rider/auth/phone_screen.dart';

import 'support/fakes.dart';
import 'package:shared/shared.dart';

void main() {
  testWidgets('invalid phone shows an Arabic error and does not call the API',
      (tester) async {
    final api = FakeAuthApi();
    final auth = AuthController(api: api, tokenStore: InMemoryTokenStore());
    addTearDown(auth.dispose);

    await tester.pumpWidget(wrapApp(const PhoneScreen(), auth));

    await tester.enterText(find.byType(TextField), '12345');
    await tester.tap(find.text('إرسال الرمز'));
    await tester.pump();

    expect(find.textContaining('رقم موبايل عراقي'), findsOneWidget);
    expect(api.requestOtpCalls, 0);
    expect(auth.step, OnboardingStep.phone);
  });
}
