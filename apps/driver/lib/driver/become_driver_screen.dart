import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import '../widgets/driver_banner.dart';
import 'driver_controller.dart';

/// Intro screen for a logged-in user who is not yet a driver. "ابدأ كسائق"
/// creates the driver profile (PENDING); the gate then advances to the vehicle
/// form.
class BecomeDriverScreen extends StatelessWidget {
  const BecomeDriverScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<DriverController>();
    final space = context.space;

    return AppScaffold(
      title: 'كن سائقاً',
      scrollable: true,
      bottomBar: AppButton(
        label: 'ابدأ كسائق',
        icon: AppIcons.car,
        loading: c.busy,
        onPressed: c.busy ? null : () => c.becomeDriver(),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: space.md),
          const OnboardingHeader(
            icon: AppIcons.car,
            title: 'كن سائقاً',
            subtitle: 'أعلن رحلاتك بين المحافظات واستقبل حجوزات الركّاب.',
          ),
          SizedBox(height: space.xl2),
          const _Benefit(
            icon: AppIcons.route,
            title: 'أعلن رحلة',
            subtitle: 'حدّد المسار والوقت وعدد المقاعد.',
          ),
          const _Benefit(
            icon: AppIcons.users,
            title: 'استقبل ركّاباً',
            subtitle: 'يحجز الركّاب مقاعدهم في رحلتك.',
          ),
          const _Benefit(
            icon: AppIcons.cash,
            title: 'تحصيل نقدي',
            subtitle: 'تستلم الأجرة نقداً عند الرحلة.',
          ),
          SizedBox(height: space.lg),
          const DriverBanner(
            message: 'بعد التسجيل نراجع مستمسكاتك قبل اعتماد حسابك.',
            tone: BannerTone.info,
          ),
          if (c.actionError != null) ...[
            SizedBox(height: space.md),
            DriverBanner(message: c.actionError!, tone: BannerTone.danger),
          ],
        ],
      ),
    );
  }
}

class _Benefit extends StatelessWidget {
  const _Benefit({required this.icon, required this.title, required this.subtitle});

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    return Padding(
      padding: EdgeInsets.only(bottom: space.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: space.xl4,
            height: space.xl4,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.12),
              borderRadius: context.radii.mdAll,
            ),
            child: Icon(icon, color: colors.primary, size: space.xl),
          ),
          SizedBox(width: space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: context.text.bodyStrong),
                SizedBox(height: space.xs),
                Text(
                  subtitle,
                  style: context.text.caption.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
