import 'package:flutter/material.dart';
import 'package:shared/shared.dart';

/// Centered message with an icon badge — base for empty/error states.
class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.icon,
    required this.title,
    this.subtitle,
    this.tone,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? tone;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    final accent = tone ?? colors.primary;

    return Center(
      child: Padding(
        padding: EdgeInsets.all(space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: space.xl4 + space.xl2, // 64
              height: space.xl4 + space.xl2,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: accent, size: space.xl2),
            ),
            SizedBox(height: space.lg),
            Text(
              title,
              style: context.text.title,
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              SizedBox(height: space.sm),
              Text(
                subtitle!,
                style: context.text.body.copyWith(color: colors.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[
              SizedBox(height: space.xl),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// No trips for the chosen corridor.
class TripEmptyView extends StatelessWidget {
  const TripEmptyView({super.key});

  @override
  Widget build(BuildContext context) {
    return const _CenteredMessage(
      icon: AppIcons.route,
      title: 'لا توجد رحلات متاحة على هذا المسار',
      subtitle: 'جرّب تاريخاً آخر أو اعكس الاتجاه.',
    );
  }
}

/// Retryable error (network / server).
class TripErrorView extends StatelessWidget {
  const TripErrorView({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _CenteredMessage(
      icon: AppIcons.warning,
      tone: context.colors.danger,
      title: message,
      action: AppButton(
        label: 'إعادة المحاولة',
        expand: false,
        onPressed: onRetry,
      ),
    );
  }
}

class _SkeletonBox extends StatelessWidget {
  const _SkeletonBox({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: context.colors.surfaceMuted,
        borderRadius: context.radii.smAll,
      ),
    );
  }
}

/// Placeholder card shown while results load.
class TripCardSkeleton extends StatelessWidget {
  const TripCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final space = context.space;
    return AppCard(
      elevated: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _SkeletonBox(width: space.xl2, height: space.xl2),
              SizedBox(width: space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SkeletonBox(width: space.xl4 * 3, height: space.md),
                    SizedBox(height: space.sm),
                    _SkeletonBox(width: space.xl4 * 2, height: space.md),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: space.lg),
          _SkeletonBox(width: double.infinity, height: space.md),
          SizedBox(height: space.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _SkeletonBox(width: space.xl4 * 2, height: space.lg),
              _SkeletonBox(width: space.xl4 * 2.5, height: space.xl),
            ],
          ),
        ],
      ),
    );
  }
}

/// A few skeleton cards for the loading state.
class TripLoadingList extends StatelessWidget {
  const TripLoadingList({super.key, this.count = 3});

  final int count;

  @override
  Widget build(BuildContext context) {
    final space = context.space;
    return ListView.separated(
      padding: EdgeInsets.symmetric(vertical: space.lg),
      itemCount: count,
      separatorBuilder: (_, __) => SizedBox(height: space.md),
      itemBuilder: (_, __) => const TripCardSkeleton(),
    );
  }
}
