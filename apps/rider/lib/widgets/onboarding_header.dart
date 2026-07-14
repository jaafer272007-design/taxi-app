import 'package:flutter/material.dart';
import 'package:shared/shared.dart';

/// Consistent header for the onboarding screens: an optional logo/icon badge,
/// a title and one supporting line. Token-based.
class OnboardingHeader extends StatelessWidget {
  const OnboardingHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.icon,
  });

  final String title;
  final String subtitle;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null) ...[
          Container(
            width: space.xl4 + space.xl2, // 64
            height: space.xl4 + space.xl2,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.12),
              borderRadius: context.radii.lgAll,
            ),
            child: Icon(icon, color: colors.primary, size: space.xl4),
          ),
          SizedBox(height: space.xl),
        ],
        Text(title, style: context.text.h1),
        SizedBox(height: space.sm),
        Text(
          subtitle,
          style: context.text.body.copyWith(color: colors.textSecondary),
        ),
      ],
    );
  }
}
