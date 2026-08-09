import 'dart:async';

import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:rider/booking/booking_models.dart';
import 'package:rider/pool/seat_request_api.dart';
import 'package:rider/pool/seat_request_models.dart';
import 'package:rider/pool/seat_requests_controller.dart';

/// A scriptable fake of [SeatRequestApi] — no real network.
class FakeSeatRequestApi implements SeatRequestApi {
  // create
  int createCalls = 0;
  SeatRequestDraft? lastDraft;
  SeatRequest? createResult;
  Object? createError;

  /// When set, `create` awaits this before returning — lets a test hold a
  /// submission in flight to exercise the double-submit guard.
  Completer<void>? createGate;

  // listMine
  List<SeatRequest> listMineResult = const [];
  Object? listMineError;
  int listMineCalls = 0;

  // cancel
  final List<String> cancelCalls = [];
  Object? cancelError;

  // respondToRaise
  final List<({String id, bool accept})> raiseResponses = [];
  Object? respondError;

  @override
  Future<SeatRequest> create(SeatRequestDraft draft) async {
    createCalls++;
    lastDraft = draft;
    if (createGate != null) await createGate!.future;
    if (createError != null) throw createError!;
    return createResult ?? seatRequestFixture();
  }

  @override
  Future<List<SeatRequest>> listMine() async {
    listMineCalls++;
    if (listMineError != null) throw listMineError!;
    return listMineResult;
  }

  @override
  Future<void> cancel(String id) async {
    cancelCalls.add(id);
    if (cancelError != null) throw cancelError!;
  }

  @override
  Future<void> respondToRaise(String id, {required bool accept}) async {
    raiseResponses.add((id: id, accept: accept));
    if (respondError != null) throw respondError!;
  }
}

/// The provider حجوزاتي reads its seat requests from.
///
/// Defaults to an empty list, which is what every test that is NOT about
/// pooling wants: the section renders nothing and the bookings list is exactly
/// what it was before Phase 2 existed.
SingleChildWidget seatRequestsProvider({List<SeatRequest> requests = const []}) {
  final api = FakeSeatRequestApi()..listMineResult = requests;
  return ChangeNotifierProvider<SeatRequestsController>(
    create: (_) => SeatRequestsController(api: api)..load(),
  );
}

/// A seat request with sane defaults; override only what a test is about.
///
/// [seatCount] defaults to **3** deliberately: `formatSeats` returns the Arabic
/// dual at 2 and the singular at 1, neither of which carries a digit at all, so
/// a fixture below 3 renders clean even when the ٠-dot bug is present.
SeatRequest seatRequestFixture({
  String id = 'sr_1',
  SeatRequestStage stage = SeatRequestStage.waitingForRiders,
  int seatCount = 3,
  DateTime? windowStart,
  DateTime? windowEnd,
  String originCity = 'Najaf',
  String destCity = 'Karbala',
  int? pricePerSeat = 6000,
  int? poolSeats,
  String? bookingId,
  String? tripId,
  SeatRequestRaise? raise,
}) {
  final start = windowStart ?? DateTime(2026, 8, 12, 7, 30);
  return SeatRequest(
    id: id,
    stage: stage,
    seatCount: seatCount,
    windowStart: start,
    windowEnd: windowEnd ?? start.add(const Duration(hours: 3)),
    pickup: const GeoPoint(lat: 31.999, lng: 44.315, label: 'كراج النجف'),
    dropoff: const GeoPoint(lat: 32.616, lng: 44.024, label: 'مرآب كربلاء'),
    originCity: originCity,
    destCity: destCity,
    createdAt: start.subtract(const Duration(hours: 2)),
    pricePerSeat: pricePerSeat,
    poolSeats: poolSeats,
    bookingId: bookingId,
    tripId: tripId,
    raise: raise,
  );
}

/// An open raise the rider has not answered.
SeatRequestRaise raiseFixture({
  int oldPricePerSeat = 6000,
  int newPricePerSeat = 9000,
  DateTime? respondBy,
  String? myResponse,
}) =>
    SeatRequestRaise(
      oldPricePerSeat: oldPricePerSeat,
      newPricePerSeat: newPricePerSeat,
      respondBy: respondBy ?? DateTime(2026, 8, 12, 7, 15),
      myResponse: myResponse,
    );
