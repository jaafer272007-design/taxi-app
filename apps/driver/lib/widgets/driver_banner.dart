import 'package:flutter/material.dart';
import 'package:shared/shared.dart';

/// Semantic tone for [DriverBanner].
enum BannerTone { info, warning, danger, success }

/// A full-width, tone-tinted message banner (errors, reassurance, hints). Token
/// only. Reused across the driver onboarding + post-trip screens.
class DriverBanner extends StatelessWidget {
  const DriverBanner({
    super.key,
    required this.message,
    this.tone = BannerTone.info,
    this.icon,
  });

  final String message;
  final BannerTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    final (Color tint, IconData fallbackIcon) = switch (tone) {
      BannerTone.info => (colors.info, AppIcons.info),
      BannerTone.warning => (colors.warning, AppIcons.warning),
      BannerTone.danger => (colors.danger, AppIcons.danger),
      BannerTone.success => (colors.success, AppIcons.success),
    };

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(space.lg),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.12),
        borderRadius: context.radii.mdAll,
        border: Border.all(color: tint.withValues(alpha: 0.30)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon ?? fallbackIcon, size: space.lg, color: tint),
          SizedBox(width: space.sm),
          Expanded(
            child: Text(
              message,
              style: context.text.body.copyWith(color: colors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
