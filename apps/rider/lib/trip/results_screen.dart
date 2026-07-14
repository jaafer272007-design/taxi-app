import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import 'trip_details_screen.dart';
import 'trip_format.dart';
import 'trip_models.dart';
import 'trip_search_controller.dart';
import 'widgets/trip_card.dart';
import 'widgets/trip_state_views.dart';

/// Results of the current search: cards, or loading / empty / error.
class ResultsScreen extends StatelessWidget {
  const ResultsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<TripSearchController>();
    final corridor = c.corridor;
    final title = corridor == null
        ? 'الرحلات المتاحة'
        : '${cityAr(corridor.originCity)} إلى ${cityAr(corridor.destCity)}';

    return AppScaffold(
      title: title,
      padded: false,
      body: switch (c.status) {
        TripSearchStatus.loading => const _Padded(child: TripLoadingList()),
        TripSearchStatus.error => TripErrorView(
            message: c.error ?? 'حدث خطأ. حاول مرة أخرى.',
            onRetry: () => c.search(),
          ),
        TripSearchStatus.empty => const TripEmptyView(),
        TripSearchStatus.results => _ResultsList(trips: c.results),
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

class _ResultsList extends StatelessWidget {
  const _ResultsList({required this.trips});

  final List<TripSummary> trips;

  @override
  Widget build(BuildContext context) {
    final space = context.space;
    return ListView.separated(
      padding: EdgeInsets.all(space.lg),
      itemCount: trips.length,
      separatorBuilder: (_, __) => SizedBox(height: space.md),
      itemBuilder: (context, i) => TripCard(
        trip: trips[i],
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => TripDetailsScreen(trip: trips[i]),
          ),
        ),
      ),
    );
  }
}
