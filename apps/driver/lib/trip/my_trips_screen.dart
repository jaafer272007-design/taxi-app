import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import 'driver_trip_api.dart';
import 'driver_trip_models.dart';
import 'my_trips_controller.dart';
import 'trip_detail_controller.dart';
import 'trip_detail_screen.dart';
import 'trip_format.dart';

/// "رحلاتي": the driver's posted trips (GET /trips/mine), newest first, each with
/// route, time, seats, price and a status pill.
class MyTripsScreen extends StatefulWidget {
  const MyTripsScreen({super.key});

  @override
  State<MyTripsScreen> createState() => _MyTripsScreenState();
}

class _MyTripsScreenState extends State<MyTripsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final c = context.read<MyTripsController>();
      if (!c.hasLoaded) c.load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<MyTripsController>();

    return AppScaffold(
      title: 'رحلاتي',
      padded: false,
      body: switch (c.status) {
        MyTripsStatus.loading =>
          Center(child: CircularProgressIndicator(color: context.colors.primary)),
        MyTripsStatus.error => _ErrorView(
            message: c.error ?? 'حدث خطأ. حاول مرة أخرى.',
            onRetry: c.load,
          ),
        MyTripsStatus.loaded =>
          c.isEmpty ? const _EmptyView() : _TripsList(controller: c),
      },
    );
  }
}

class _TripsList extends StatelessWidget {
  const _TripsList({required this.controller});

  final MyTripsController controller;

  @override
  Widget build(BuildContext context) {
    final space = context.space;
    final trips = controller.trips;
    return RefreshIndicator(
      color: context.colors.primary,
      onRefresh: controller.load,
      child: ListView.separated(
        padding: EdgeInsets.all(space.lg),
        itemCount: trips.length,
        separatorBuilder: (_, __) => SizedBox(height: space.md),
        itemBuilder: (_, i) => _TripCard(
          trip: trips[i],
          corridor: controller.corridorFor(trips[i].corridorId),
        ),
      ),
    );
  }
}

class _TripCard extends StatelessWidget {
  const _TripCard({required this.trip, required this.corridor});

  final DriverTrip trip;
  final Corridor? corridor;

  /// Open the trip detail (bookings + lifecycle). Refreshes the list on return
  /// so any status change (started/completed/cancelled) shows immediately.
  Future<void> _open(BuildContext context) async {
    final api = context.read<DriverTripApi>();
    final myTrips = context.read<MyTripsController>();
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ChangeNotifierProvider<TripDetailController>(
        create: (_) =>
            TripDetailController(api: api, trip: trip, corridor: corridor),
        child: const TripDetailScreen(),
      ),
    ));
    await myTrips.load();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    final route = corridor == null
        ? 'رحلة'
        : '${cityAr(corridor!.originCity)} إلى ${cityAr(corridor!.destCity)}';

    return AppCard(
      onTap: () => _open(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(route,
                    style: context.text.title.copyWith(color: colors.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              SizedBox(width: space.sm),
              tripStatusPill(trip.status),
            ],
          ),
          SizedBox(height: space.md),
          Row(
            children: [
              Icon(AppIcons.clock, size: space.lg, color: colors.textMuted),
              SizedBox(width: space.sm),
              Text(formatTime(trip.departureTime),
                  style: context.text.body.tabular
                      .copyWith(color: colors.textSecondary)),
              SizedBox(width: space.lg),
              Icon(AppIcons.seat, size: space.lg, color: colors.textMuted),
              SizedBox(width: space.sm),
              Text('${trip.seatsAvailable}/${trip.seatsTotal} متاح',
                  style: context.text.body.tabular
                      .copyWith(color: colors.textSecondary)),
            ],
          ),
          SizedBox(height: space.md),
          Divider(height: 1, color: colors.border),
          SizedBox(height: space.md),
          Row(
            children: [
              Text(formatPrice(trip.pricePerSeat),
                  style: context.text.title.tabular.copyWith(color: colors.primary)),
              Text(' / للمقعد',
                  style: context.text.caption.copyWith(color: colors.textMuted)),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: space.xl4 + space.xl2,
              height: space.xl4 + space.xl2,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(AppIcons.route, color: colors.primary, size: space.xl2),
            ),
            SizedBox(height: space.lg),
            Text('لا توجد رحلات بعد',
                style: context.text.title, textAlign: TextAlign.center),
            SizedBox(height: space.sm),
            Text('انشر رحلتك الأولى من تبويب «انشر رحلة».',
                style: context.text.body.copyWith(color: colors.textSecondary),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: space.xl4 + space.xl2,
              height: space.xl4 + space.xl2,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.danger.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(AppIcons.warning, color: colors.danger, size: space.xl2),
            ),
            SizedBox(height: space.lg),
            Text(message, style: context.text.title, textAlign: TextAlign.center),
            SizedBox(height: space.xl),
            AppButton(label: 'إعادة المحاولة', expand: false, onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}
