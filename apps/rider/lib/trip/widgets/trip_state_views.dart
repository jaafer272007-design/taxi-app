import 'package:flutter/material.dart';
import 'package:shared/shared.dart';

import '../trip_models.dart';
import '../trip_search_controller.dart' show RouteRequestStatus;

/// Centered message with an icon badge — base for empty/error states.
class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.icon,
    required this.title,
    this.subtitle,
    this.danger = false,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  /// Draw the badge in the danger tone (a retryable failure) rather than the
  /// neutral primary tone (an ordinary empty result).
  final bool danger;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    // Opaque tonal fills — an alpha tint of the accent measures differently on
    // the page background than it does inside a card.
    final accent = danger ? colors.danger : colors.primary;
    final badge = danger ? colors.dangerTonal : colors.primaryTonal;

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
                color: badge,
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

/// Empty results. When optional filters ([tripType] / [driverGender]) are active
/// and [onClearFilters] is provided, the copy is tailored to the active filter
/// and a one-tap "إزالة الفلاتر" action is offered — female drivers are rare, so
/// a filtered-empty result is common and should feel intentional, not broken.
///
/// On an UNFILTERED empty result it also offers «أبلغنا أنك تريد هذا المسار»
/// ([onRequestRoute]). That is the only place in the app that turns a dead end
/// into information: 306 corridors exist and drivers post on a handful, so this
/// screen is where we find out which of the other 300 anyone actually wants.
/// Optional, one tap, no form — a rider who ignores it loses nothing.
class TripEmptyView extends StatelessWidget {
  const TripEmptyView({
    super.key,
    this.tripType,
    this.driverGender,
    this.onClearFilters,
    this.onRequestRoute,
    this.routeRequestStatus = RouteRequestStatus.idle,
    this.routeRequestError,
    this.onRequestSeat,
  });

  final TripType? tripType;
  final Gender? driverGender;
  final VoidCallback? onClearFilters;

  /// Record demand for the corridor currently searched. `null` hides the
  /// action entirely — there is no disabled state and no upsell.
  final VoidCallback? onRequestRoute;
  final RouteRequestStatus routeRequestStatus;
  final String? routeRequestError;

  /// «اطلب مقعد» — Phase 2. Null hides it entirely.
  ///
  /// It is the PRIMARY action here and «أبلغنا» becomes the quieter one, and
  /// that ordering is the point: asking for a seat can actually produce a trip
  /// on this corridor, while recording demand only tells us to go find drivers
  /// for it later. When the app can offer the thing that helps *this* rider
  /// today, it should lead with it.
  final VoidCallback? onRequestSeat;

  bool get _filtersActive => tripType != null || driverGender != null;

  @override
  Widget build(BuildContext context) {
    if (_filtersActive && onClearFilters != null) {
      final String title;
      if (driverGender == Gender.female) {
        title = 'لا توجد رحلات بسائقة امرأة على هذا المسار حالياً';
      } else if (driverGender == Gender.male) {
        title = 'لا توجد رحلات بسائق رجل على هذا المسار حالياً';
      } else if (tripType == TripType.womenFamily) {
        title = 'لا توجد رحلات نسائية-عائلية على هذا المسار حالياً';
      } else if (tripType == TripType.general) {
        title = 'لا توجد رحلات عامة على هذا المسار حالياً';
      } else {
        title = 'لا توجد رحلات مطابقة للفلاتر';
      }
      return _CenteredMessage(
        icon: AppIcons.search,
        title: title,
        subtitle: 'جرّب إزالة الفلاتر أو تغيير المسار والتاريخ.',
        action: AppButton(
          label: 'إزالة الفلاتر',
          variant: AppButtonVariant.secondary,
          icon: AppIcons.close,
          expand: false,
          onPressed: onClearFilters,
        ),
      );
    }
    // Shown both when a corridor has no trips yet AND when the picked city pair
    // has no corridor at all — either way it's a normal state, not a bug.
    return _CenteredMessage(
      icon: AppIcons.route,
      title: 'لا توجد رحلات متاحة على هذا المسار حالياً',
      subtitle: 'اطلب مقعداً وسنجمعك مع ركّاب آخرين، أو جرّب وقتاً آخر.',
      action: (onRequestSeat == null && onRequestRoute == null)
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onRequestSeat != null)
                  AppButton(
                    label: 'اطلب مقعد',
                    icon: AppIcons.seat,
                    expand: false,
                    onPressed: onRequestSeat,
                  ),
                if (onRequestSeat != null && onRequestRoute != null)
                  SizedBox(height: context.space.sm),
                if (onRequestRoute != null)
                  _RouteRequestAction(
                    status: routeRequestStatus,
                    error: routeRequestError,
                    onPressed: onRequestRoute!,
                    // Demoted to a text action once «اطلب مقعد» is present:
                    // one screen gets one primary, and the secondary should
                    // not compete with it.
                    quiet: onRequestSeat != null,
                  ),
              ],
            ),
    );
  }
}

/// The «أبلغنا أنك تريد هذا المسار» action and its three answers.
///
/// The confirmation REPLACES the button rather than sitting beside it: the
/// question has been answered, and leaving a live button under «سنخبرك» invites
/// a second tap that does nothing visible.
class _RouteRequestAction extends StatelessWidget {
  const _RouteRequestAction({
    required this.status,
    required this.error,
    required this.onPressed,
    this.quiet = false,
  });

  final RouteRequestStatus status;
  final String? error;
  final VoidCallback onPressed;

  /// Render as the quieter of two actions — a ghost button rather than a
  /// secondary one — when «اطلب مقعد» is also on screen.
  final bool quiet;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;

    if (status == RouteRequestStatus.sent) {
      return Container(
        padding: EdgeInsets.symmetric(horizontal: space.lg, vertical: space.md),
        decoration: BoxDecoration(
          // Opaque tonal fill — an alpha tint measures differently against the
          // page background than inside a card.
          color: colors.successTonal,
          borderRadius: context.radii.cardAll,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(AppIcons.success, color: colors.success, size: space.lg),
            SizedBox(width: space.sm),
            Flexible(
              child: Text(
                // No timeframe is promised, because we do not have one. The
                // honest sentence is the whole point of the confirmation.
                'سنخبرك عندما تتوفر رحلات على هذا المسار',
                style: context.text.body.copyWith(color: colors.success),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppButton(
          label: 'أبلغنا أنك تريد هذا المسار',
          variant:
              quiet ? AppButtonVariant.ghost : AppButtonVariant.secondary,
          icon: AppIcons.bell,
          expand: false,
          loading: status == RouteRequestStatus.sending,
          onPressed: onPressed,
        ),
        if (status == RouteRequestStatus.failed && error != null) ...[
          SizedBox(height: space.sm),
          Text(
            // The rider asked for this, so a failure is theirs to see — unlike
            // a background refresh, which fails in silence.
            error!,
            style: context.text.caption.copyWith(color: colors.danger),
            textAlign: TextAlign.center,
          ),
        ],
      ],
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
      danger: true,
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
        borderRadius: context.radii.chipAll,
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
