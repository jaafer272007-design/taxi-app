import 'dart:async';

import 'package:rider/booking/booking_api.dart';
import 'package:rider/booking/booking_models.dart';

/// A scriptable fake of [BookingApi] for tests — no real network.
class FakeBookingApi implements BookingApi {
  // create
  int createCalls = 0;
  int? lastSeatCount;
  GeoPoint? lastPickup;
  GeoPoint? lastDropoff;
  Booking? createResult;
  Object? createError;

  /// When set, `create` awaits this before returning — lets a test hold a
  /// booking in flight to exercise the double-submit guard.
  Completer<void>? createGate;

  // listMine
  List<Booking> listMineResult = const [];
  Object? listMineError;

  // cancel
  int cancelCalls = 0;
  String? lastCancelledId;
  Booking? cancelResult;
  Object? cancelError;

  @override
  Future<Booking> create({
    required String tripId,
    required GeoPoint pickup,
    required GeoPoint dropoff,
    required int seatCount,
  }) async {
    createCalls++;
    lastSeatCount = seatCount;
    lastPickup = pickup;
    lastDropoff = dropoff;
    if (createGate != null) await createGate!.future;
    if (createError != null) throw createError!;
    return createResult ??
        bookingFixture(seatCount: seatCount, fare: 6000 * seatCount);
  }

  @override
  Future<List<Booking>> listMine() async {
    if (listMineError != null) throw listMineError!;
    return listMineResult;
  }

  @override
  Future<Booking> cancel(String bookingId) async {
    cancelCalls++;
    lastCancelledId = bookingId;
    if (cancelError != null) throw cancelError!;
    return cancelResult ??
        bookingFixture(id: bookingId, status: BookingStatus.cancelled);
  }
}

// ── fixtures ───────────────────────────────────────────────────────────────

Booking bookingFixture({
  String id = 'b1',
  int seatCount = 1,
  int fare = 6000,
  BookingStatus status = BookingStatus.confirmed,
  String pickupLabel = 'حي السلام',
  String dropoffLabel = 'قرب المستشفى',
  BookingTrip? trip,
  bool? upcoming,
}) {
  return Booking(
    id: id,
    seatCount: seatCount,
    fare: fare,
    status: status,
    pickupLabel: pickupLabel,
    dropoffLabel: dropoffLabel,
    trip: trip,
    upcoming: upcoming,
  );
}

/// A booking that carries its trip + corridor, as GET /bookings/mine returns.
Booking mineFixture({
  String id = 'b1',
  int seatCount = 2,
  int fare = 12000,
  BookingStatus status = BookingStatus.confirmed,
  bool upcoming = true,
  int hourUtc = 4,
  int minute = 30,
  String originCity = 'Najaf',
  String destCity = 'Karbala',
}) {
  return bookingFixture(
    id: id,
    seatCount: seatCount,
    fare: fare,
    status: status,
    upcoming: upcoming,
    trip: BookingTrip(
      id: 't-$id',
      departureTime: DateTime.utc(2026, 7, 20, hourUtc, minute),
      corridor: BookingCorridor(originCity: originCity, destCity: destCity),
    ),
  );
}
