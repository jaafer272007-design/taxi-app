import 'package:flutter/material.dart';
import 'package:shared/shared.dart';

/// Semantic tone for [DriverBanner].
enum BannerTone { info, warning, danger, success }

/// A full-width, tone-tinted message banner (errors, reassurance, hints). Token
/// only. Reused across the driver onboarding + post-trip screens.
///
/// The fill is the opaque `*Tonal` token, not the tone at 12%: this banner
/// appears on the page background, inside cards, and on the recessed surface,
/// and a live alpha tint measures a different ratio on each of them. The message
/// takes the tone's own ink, which is the pairing `contrast_test.dart` enforces.
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
    final (Color ink, Color fill, IconData fallbackIcon) = switch (tone) {
      BannerTone.info => (colors.info, colors.infoTonal, AppIcons.info),
      BannerTone.warning =>
        (colors.warning, colors.warningTonal, AppIcons.warning),
      BannerTone.danger => (colors.danger, colors.dangerTonal, AppIcons.danger),
      BannerTone.success =>
        (colors.success, colors.successTonal, AppIcons.success),
    };

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(space.lg),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: context.radii.fieldLgAll,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon ?? fallbackIcon, size: space.lg, color: ink),
          SizedBox(width: space.sm),
          Expanded(
            child: Text(
              message,
              style: context.text.body.copyWith(color: ink),
            ),
          ),
        ],
      ),
    );
  }
}
