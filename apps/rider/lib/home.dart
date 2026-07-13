import 'package:flutter/material.dart';
import 'package:shared/shared.dart';

/// Temporary placeholder home for the rider app.
///
/// Real rider screens come next (screen by screen). For now this just confirms
/// the design system + theme wiring are live: it reads only tokens, and the
/// badge reflects the currently-applied theme (which follows the system setting
/// by default). This is NOT the settings screen — there is no mode toggle here.
class RiderHome extends StatelessWidget {
  const RiderHome({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'الراكب',
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(AppIcons.car, size: context.space.xl4, color: context.colors.primary),
            SizedBox(height: context.space.lg),
            Text('تطبيق الراكب', style: context.text.h1),
            SizedBox(height: context.space.sm),
            Text(
              'الشاشات قادمة قريباً',
              style: context.text.body.copyWith(color: context.colors.textSecondary),
            ),
            SizedBox(height: context.space.xl),
            AppBadge(
              label: context.isDark ? 'الوضع الداكن' : 'الوضع الفاتح',
              tone: AppBadgeTone.info,
              icon: AppIcons.info,
            ),
          ],
        ),
      ),
    );
  }
}
