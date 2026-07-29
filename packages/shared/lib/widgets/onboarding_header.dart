import 'package:flutter/material.dart';

import '../format/numerals.dart';
import '../theme/app_theme.dart';

/// Consistent header for the onboarding screens: an optional logo/icon badge,
/// a title and one supporting line. Token-based. Shared by rider & driver — each
/// app supplies its own copy (title/subtitle/icon).
///
/// Pass [step] / [totalSteps] to print "الخطوة ١ من ٣" above the title. Sign-up
/// is the one flow a user has never seen before, and knowing there are three
/// screens rather than an unbounded queue is most of what makes it tolerable.
class OnboardingHeader extends StatelessWidget {
  const OnboardingHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.icon,
    this.step,
    this.totalSteps,
  });

  final String title;
  final String subtitle;
  final IconData? icon;

  /// 1-based position in the onboarding flow.
  final int? step;
  final int? totalSteps;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    final step = this.step;
    final total = totalSteps;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (step != null && total != null) ...[
          Text(
            'الخطوة ${formatCount(step)} من ${formatCount(total)}',
            style: context.text.label.copyWith(color: colors.primary),
          ),
          SizedBox(height: space.md),
        ],
        if (icon != null) ...[
          Container(
            width: space.xl4 + space.xl2, // 64
            height: space.xl4 + space.xl2,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.primaryTonal,
              borderRadius: context.radii.cardAll,
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
