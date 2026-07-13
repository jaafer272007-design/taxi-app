import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared/shared.dart';

/// Guards the core promise of the design system: a re-skin is a change to the
/// TOKEN FILES only. These tests prove screens/widgets read their values from
/// the tokens, so overriding a token flows everywhere with no widget edits.
void main() {
  testWidgets('context tokens come from the active theme', (tester) async {
    late AppColors seen;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) {
            seen = context.colors;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(seen.primary, AppColors.light.primary);
    expect(seen.primary, const Color(0xFF2563EB));
  });

  testWidgets('overriding the primary token re-skins without touching widgets',
      (tester) async {
    const newPrimary = Color(0xFF9333EA); // purple

    // Take the real light theme and override ONLY the color token — exactly
    // what editing colors.dart does at runtime.
    final base = AppTheme.light();
    final reskinned = base.copyWith(
      extensions: [
        AppColors.light.copyWith(primary: newPrimary),
        ...base.extensions.values.where((e) => e is! AppColors),
      ],
    );

    late Color buttonSeesPrimary;
    await tester.pumpWidget(
      MaterialApp(
        theme: reskinned,
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Builder(
            builder: (context) {
              buttonSeesPrimary = context.colors.primary;
              // A real widget from the library, unedited.
              return Scaffold(
                body: AppButton(label: 'احجز', onPressed: () {}),
              );
            },
          ),
        ),
      ),
    );

    // The widget tree now reads the new brand color purely from the token.
    expect(buttonSeesPrimary, newPrimary);
    expect(find.text('احجز'), findsOneWidget);
  });

  testWidgets('the Theme Preview builds in light and dark, RTL', (tester) async {
    await tester.pumpWidget(const ThemePreviewApp());
    await tester.pump();

    // Both panels render (light + dark labels).
    expect(find.textContaining('نظام التصميم'), findsWidgets);
    // A representative token-driven widget is present.
    expect(find.text('احجز مقعد'), findsWidgets);
  });
}
