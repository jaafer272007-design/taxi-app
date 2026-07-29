import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import 'driver_trip_api.dart';
import 'driver_trip_models.dart';
import 'my_trips_controller.dart';
import 'trip_detail_controller.dart';
import 'trip_detail_screen.dart';

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

/// A posted trip in the Masar anatomy: a status stripe along the top edge, the
/// route on the rail, and the two numbers a driver actually scans for — when it
/// leaves and how full it is.
///
/// The seat state is drawn with [SeatGlyphs] rather than spelled as "٢/٤ متاح":
/// on this screen the driver is checking *fill*, and a fill state reads faster
/// as a picture than as a fraction.
class _TripCard extends StatelessWidget {
  const _TripCard({required this.trip, required this.corridor});

  final DriverTrip trip;
  final Corridor? corridor;

  /// Hand-off stripe thickness.
  static const double _stripe = 4;

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
    final typeBadge = tripTypeBadge(trip.tripType);
    final done = trip.status == TripStatus.completed ||
        trip.status == TripStatus.settled ||
        trip.status == TripStatus.cancelled;

    return ClipRRect(
      borderRadius: context.radii.cardAll,
      child: AppCard(
        onTap: () => _open(context),
        muted: done,
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Decorative and redundant with the status pill below it, so it is
            // deliberately not held to 4.5:1 — nothing here is colour-only.
            Container(height: _stripe, color: _statusTone(trip.status, colors)),
            Padding(
              padding: EdgeInsets.all(space.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RouteRail(
                    variant: RouteRailVariant.compact,
                    origin: _EndpointRow(
                      city: corridor?.originCity,
                      trailing: Text(
                        formatTime(trip.departureTime),
                        style: context.text.h2.tabular
                            .copyWith(color: colors.textPrimary),
                      ),
                    ),
                    destination: _EndpointRow(
                      city: corridor?.destCity,
                      trailing: tripStatusBadge(trip.status),
                    ),
                  ),
                  if (typeBadge != null) ...[
                    SizedBox(height: space.md),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: typeBadge,
                    ),
                  ],
                  SizedBox(height: space.md),
                  Divider(height: 1, color: colors.border),
                  SizedBox(height: space.md),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: SeatAvailability(
                          total: trip.seatsTotal,
                          available: trip.seatsAvailable,
                          compact: true,
                        ),
                      ),
                      SizedBox(width: space.sm),
                      Text(
                        formatPrice(trip.pricePerSeat),
                        style: context.text.title.tabular
                            .copyWith(color: colors.primary),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A city on the trip rail with its time / status on the trailing edge.
class _EndpointRow extends StatelessWidget {
  const _EndpointRow({required this.city, required this.trailing});

  final String? city;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            city == null ? 'رحلة' : cityArName(city!),
            style: context.text.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        SizedBox(width: context.space.sm),
        trailing,
      ],
    );
  }
}

Color _statusTone(TripStatus status, AppColors c) => switch (status) {
      TripStatus.open => c.success,
      TripStatus.locked => c.warning,
      TripStatus.enRoute => c.info,
      TripStatus.completed || TripStatus.settled => c.borderStrong,
      TripStatus.cancelled => c.danger,
      TripStatus.unknown => c.borderStrong,
    };

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
                color: colors.primaryTonal,
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
                color: colors.dangerTonal,
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
