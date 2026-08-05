import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared/shared.dart';

import 'support/contact_fakes.dart';

/// [ContactRow] — what each button actually launches, and what the number looks
/// like on screen.
void main() {
  Future<void> host(
    WidgetTester tester,
    LinkLauncher launcher, {
    String phone = '+9647701234567',
    String? name = 'علي حسن',
    ValueChanged<String>? onUnavailable,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: ContactRow(
              phone: phone,
              launcher: launcher,
              name: name,
              roleLabel: 'السائق',
              onUnavailable: onUnavailable,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('اتصال launches tel: with the country code', (t) async {
    final launcher = FakeLinkLauncher();
    await host(t, launcher);

    t.widget<AppButton>(find.widgetWithText(AppButton, 'اتصال')).onPressed!();
    await t.pump();

    expect(launcher.last.toString(), 'tel:+9647701234567');
  });

  testWidgets('واتساب launches wa.me with NO plus sign', (t) async {
    final launcher = FakeLinkLauncher();
    await host(t, launcher);

    t.widget<AppButton>(find.widgetWithText(AppButton, 'واتساب')).onPressed!();
    await t.pump();

    expect(launcher.last.toString(), 'https://wa.me/9647701234567');
  });

  testWidgets('renders the number in Western digits, forced LTR', (t) async {
    await host(t, FakeLinkLauncher());

    final text = t.widget<Text>(find.text('+964 770 123 4567'));
    expect(text.textDirection, TextDirection.ltr);
  });

  testWidgets('says so when the device cannot open WhatsApp', (t) async {
    // A tap that silently does nothing is indistinguishable from a tap that did
    // not register, and the rider tries again instead of calling.
    String? message;
    await host(t, FakeLinkLauncher.deaf(), onUnavailable: (m) => message = m);

    t.widget<AppButton>(find.widgetWithText(AppButton, 'واتساب')).onPressed!();
    await t.pump();

    expect(message, contains('واتساب'));
  });

  testWidgets('falls back to the role when the profile has no name', (t) async {
    await host(t, FakeLinkLauncher(), name: null);

    expect(find.text('السائق'), findsOneWidget);
  });

  testWidgets('never puts a dot beside an Arabic-Indic numeral', (t) async {
    // The standing rule. This row is all-Western by design, but the sweep is
    // cheap and the next edit might not be.
    await host(t, FakeLinkLauncher());

    final offenders = t
        .widgetList<Text>(find.byType(Text))
        .map((w) => w.data)
        .whereType<String>()
        .where((s) => RegExp(r'·\s*[٠-٩]|[٠-٩]\s*·').hasMatch(s));

    expect(offenders, isEmpty);
  });
}
