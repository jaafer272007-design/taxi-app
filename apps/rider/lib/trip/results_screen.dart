import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import 'trip_details_screen.dart';
import 'trip_search_controller.dart';
import 'widgets/trip_card.dart';
import 'widgets/trip_state_views.dart';

/// Results of the current search: cards, or loading / empty / error.
class ResultsScreen extends StatelessWidget {
  const ResultsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<TripSearchController>();
    final origin = c.origin;
    final dest = c.dest;
    final title = (origin == null || dest == null)
        ? 'الرحلات المتاحة'
        : '${cityArName(origin)} إلى ${cityArName(dest)}';

    // Clearing filters only helps when a corridor actually serves this pair; if
    // there's no corridor yet, keep the plain "no route" message (clearing
    // filters wouldn't change anything).
    final corridorServed = c.matchedCorridor != null;

    return AppScaffold(
      title: title,
      padded: false,
      body: switch (c.status) {
        TripSearchStatus.loading => const _Padded(child: TripLoadingList()),
        TripSearchStatus.error => TripErrorView(
            message: c.error ?? 'حدث خطأ. حاول مرة أخرى.',
            onRetry: () => c.search(),
          ),
        TripSearchStatus.empty => TripEmptyView(
            tripType: corridorServed ? c.tripType : null,
            driverGender: corridorServed ? c.driverGender : null,
            onClearFilters: (corridorServed && c.hasActiveFilters)
                ? () {
                    c.clearFilters();
                    c.search();
                  }
                : null,
          ),
        TripSearchStatus.results => _ResultsList(controller: c),
        TripSearchStatus.initial => const SizedBox.shrink(),
      },
    );
  }
}

class _Padded extends StatelessWidget {
  const _Padded({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.symmetric(horizontal: context.space.lg),
        child: child,
      );
}

/// The result cards, under a sort control.
///
/// The sort bar sits INSIDE the scroll view, not pinned above it: with a
/// typical handful of trips per route it would otherwise eat permanent vertical
/// space on a 390×844 phone to solve a problem that doesn't exist. It scrolls
/// away with the first card and is one flick back.
class _ResultsList extends StatelessWidget {
  const _ResultsList({required this.controller});

  final TripSearchController controller;

  @override
  Widget build(BuildContext context) {
    final space = context.space;
    final trips = controller.results;

    return ListView.separated(
      padding: EdgeInsets.all(space.lg),
      // One extra leading item: the sort bar.
      itemCount: trips.length + 1,
      separatorBuilder: (_, __) => SizedBox(height: space.md),
      itemBuilder: (context, i) {
        if (i == 0) {
          return _SortBar(
            value: controller.sort,
            onChanged: controller.setSort,
            count: trips.length,
          );
        }
        final trip = trips[i - 1];
        return TripCard(
          trip: trip,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => TripDetailsScreen(trip: trip),
            ),
          ),
        );
      },
    );
  }
}

/// "N trips · [by time | cheapest]".
///
/// Sorting by price only became meaningful once drivers set their own prices —
/// before that every trip on a route cost the same. The count is on the same
/// line because it answers the question the rider asks first ("how many?")
/// without a second row of chrome.
class _SortBar extends StatelessWidget {
  const _SortBar({
    required this.value,
    required this.onChanged,
    required this.count,
  });

  final TripSort value;
  final ValueChanged<TripSort> onChanged;
  final int count;

  @override
  Widget build(BuildContext context) {
    final space = context.space;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          formatTrips(count),
          style: context.text.label.copyWith(color: context.colors.textSecondary),
        ),
        SizedBox(height: space.sm),
        AppSegmentedControl<TripSort>(
          value: value,
          segments: const [
            AppSegment(value: TripSort.departure, label: 'الأقرب موعداً'),
            AppSegment(value: TripSort.price, label: 'الأرخص'),
          ],
          onChanged: onChanged,
        ),
      ],
    );
  }
}
