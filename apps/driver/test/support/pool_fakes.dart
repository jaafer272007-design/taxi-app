import 'dart:async';

import 'package:driver/pool/pool_api.dart';
import 'package:driver/pool/pool_models.dart';
import 'package:driver/pool/raise_controller.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared/shared.dart';

/// A scriptable fake of [PoolApi] — no real network.
class FakePoolApi implements PoolApi {
  // board
  List<BoardPool> boardResult = const [];
  Object? boardError;
  int boardCalls = 0;

  // claim
  final List<String> claimCalls = [];
  String claimResult = 'trip_1';

  /// Thrown by `claim`. Set an [ApiException] with a `code` to exercise a
  /// particular refusal — that code is the whole point of the branch.
  Object? claimError;

  /// Held open to keep a claim in flight (the double-tap guard).
  Completer<void>? claimGate;

  // forTrip
  DriverPool? forTripResult;
  Object? forTripError;
  int forTripCalls = 0;

  // proposeRaise
  final List<({String poolId, int price})> raiseCalls = [];
  Object? raiseError;

  @override
  Future<List<BoardPool>> board() async {
    boardCalls++;
    if (boardError != null) throw boardError!;
    return boardResult;
  }

  @override
  Future<String> claim(String poolId) async {
    claimCalls.add(poolId);
    if (claimGate != null) await claimGate!.future;
    if (claimError != null) throw claimError!;
    return claimResult;
  }

  @override
  Future<DriverPool?> forTrip(String tripId) async {
    forTripCalls++;
    if (forTripError != null) throw forTripError!;
    return forTripResult;
  }

  @override
  Future<void> proposeRaise(String poolId, int newPricePerSeat) async {
    raiseCalls.add((poolId: poolId, price: newPricePerSeat));
    if (raiseError != null) throw raiseError!;
  }
}

/// A claimable pool with sane defaults.
///
/// [totalSeats] defaults to **3**: `formatSeats` returns the Arabic dual
/// «مقعدان» at 2 and the singular at 1, neither of which carries a digit at
/// all, so a fixture below 3 renders clean even when the ٠-dot bug is present.
BoardPool boardPoolFixture({
  String id = 'pool_1',
  String originCity = 'Najaf',
  String destCity = 'Karbala',
  DateTime? windowStart,
  DateTime? windowEnd,
  int totalSeats = 3,
  int riderCount = 2,
  int pricePerSeat = 6000,
  List<PoolStop>? stops,
}) {
  final start = windowStart ?? DateTime(2026, 8, 12, 7, 30);
  return BoardPool(
    id: id,
    corridorId: 'c1',
    originCity: originCity,
    destCity: destCity,
    windowStart: start,
    windowEnd: windowEnd ?? start.add(const Duration(hours: 3)),
    totalSeats: totalSeats,
    riderCount: riderCount,
    pricePerSeat: pricePerSeat,
    estimatedFare: pricePerSeat * totalSeats,
    stops: stops ??
        const [
          PoolStop(
            seatCount: 2,
            pickup: LocationPoint(
                lat: 31.999, lng: 44.315, label: 'حي السلام'),
            dropoff:
                LocationPoint(lat: 32.616, lng: 44.024, label: 'حي الحسين'),
          ),
          PoolStop(
            seatCount: 1,
            pickup:
                LocationPoint(lat: 32.004, lng: 44.319, label: 'شارع الكوفة'),
            dropoff:
                LocationPoint(lat: 32.618, lng: 44.028, label: 'باب بغداد'),
          ),
        ],
  );
}

/// The pool behind a claimed trip.
DriverPool driverPoolFixture({
  String poolId = 'pool_1',
  String tripId = 'trip_1',
  int pricePerSeat = 6000,
  int maxPricePerSeat = 12000,
  int seatsTaken = 3,
  int seatsTotal = 4,
  int minSeats = 2,
  DateTime? raiseDeadline,
  int responseMinutes = 10,
  bool canPropose = true,
  String? blockedReason,
  PoolRaise? raise,
}) {
  final start = DateTime(2026, 8, 12, 7, 30);
  return DriverPool(
    poolId: poolId,
    tripId: tripId,
    pricePerSeat: pricePerSeat,
    maxPricePerSeat: maxPricePerSeat,
    seatsTaken: seatsTaken,
    seatsTotal: seatsTotal,
    minSeats: minSeats,
    raiseDeadline: raiseDeadline ?? DateTime(2026, 8, 12, 7, 0),
    responseMinutes: responseMinutes,
    canPropose: canPropose,
    blockedReason: blockedReason,
    windowStart: start,
    windowEnd: start.add(const Duration(hours: 3)),
    raise: raise,
  );
}

/// An open raise with a mixed set of answers — the waiting state.
PoolRaise raiseFixture({
  int oldPricePerSeat = 6000,
  int newPricePerSeat = 9000,
  DateTime? respondBy,
  bool resolved = false,
  RaiseOutcome outcome = RaiseOutcome.pending,
  List<RaiseResponseRow>? responses,
}) {
  final rows = responses ??
      const [
        RaiseResponseRow(
          riderName: 'أبو حسن',
          seatCount: 2,
          response: RaiseResponse.accepted,
          released: false,
        ),
        RaiseResponseRow(
          riderName: 'سارة',
          seatCount: 1,
          response: RaiseResponse.awaiting,
          released: false,
        ),
      ];
  int seats(RaiseResponse r) => rows
      .where((row) => row.response == r)
      .fold(0, (sum, row) => sum + row.seatCount);
  return PoolRaise(
    oldPricePerSeat: oldPricePerSeat,
    newPricePerSeat: newPricePerSeat,
    respondBy: respondBy ?? DateTime(2026, 8, 12, 7, 15),
    resolved: resolved,
    outcome: outcome,
    acceptedSeats: seats(RaiseResponse.accepted),
    declinedSeats: seats(RaiseResponse.declined),
    pendingSeats: seats(RaiseResponse.awaiting),
    responses: rows,
  );
}

/// The provider the driver's trip detail screen reads its pool from.
///
/// Defaults to **no pool**, which is what every test that is not about pooling
/// wants: `RaisePanel` renders nothing and the screen is exactly what it was
/// before Phase 2 existed.
SingleChildWidget raiseProvider({DriverPool? pool, String tripId = 'trip_1'}) {
  final api = FakePoolApi()..forTripResult = pool;
  return ChangeNotifierProvider<RaiseController>(
    create: (_) => RaiseController(api: api, tripId: tripId)..load(),
  );
}
