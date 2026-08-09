import 'dart:math' as math;

import 'package:shared/shared.dart';

/// One stop on a pool: a rider's pickup and dropoff, and how many seats they
/// hold. **No name and no phone** — the board is browsed before any commitment,
/// and the server does not send contact details until a claim exists.
class PoolStop {
  const PoolStop({
    required this.seatCount,
    required this.pickup,
    required this.dropoff,
  });

  final int seatCount;
  final LocationPoint pickup;
  final LocationPoint dropoff;

  factory PoolStop.fromJson(Map<String, dynamic> json) => PoolStop(
        seatCount: (json['seatCount'] as num?)?.toInt() ?? 1,
        pickup: _point(json['pickup']),
        dropoff: _point(json['dropoff']),
      );
}

LocationPoint _point(Object? raw) {
  final m = raw as Map<String, dynamic>? ?? const {};
  return LocationPoint(
    lat: (m['lat'] as num?)?.toDouble() ?? 0,
    lng: (m['lng'] as num?)?.toDouble() ?? 0,
    label: m['label'] as String? ?? '',
  );
}

/// A claimable pool as it appears on the driver's board (GET /pools/board).
///
/// Everything here answers one question — **is this worth driving?** — so the
/// model carries the numbers the driver compares rather than the rows the
/// database happens to hold.
class BoardPool {
  const BoardPool({
    required this.id,
    required this.corridorId,
    required this.originCity,
    required this.destCity,
    required this.windowStart,
    required this.windowEnd,
    required this.totalSeats,
    required this.riderCount,
    required this.pricePerSeat,
    required this.estimatedFare,
    required this.stops,
  });

  final String id;
  final String corridorId;
  final String originCity;
  final String destCity;

  /// Earliest and latest departure that suits EVERY rider in the pool — it is
  /// the intersection of their windows, so any instant inside it is agreed by
  /// construction. The driver picks within it; there is no single time to show.
  final DateTime windowStart;
  final DateTime windowEnd;

  /// Seats already requested. Never more than the driver's own capacity — the
  /// server filters the board by the vehicle before it is ever sent.
  final int totalSeats;
  final int riderCount;
  final int pricePerSeat;

  /// Cash in hand if the driver takes it exactly as it stands.
  final int estimatedFare;

  final List<PoolStop> stops;

  /// What a FULL car pays at this price — the other half of the decision.
  ///
  /// Takes the capacity from the caller rather than storing it: the number is a
  /// property of the driver's vehicle, not of the pool, and a pool does not
  /// know whose board it is on.
  int fullCarFare(int capacity) => pricePerSeat * capacity;

  /// Seats that would still be sellable to ordinary riders after claiming.
  int emptySeats(int capacity) => math.max(0, capacity - totalSeats);

  /// How far apart the pickup points are, in metres — the widest gap between
  /// any two of them.
  ///
  /// This is NOT route optimisation (explicitly out of scope): it computes no
  /// order and suggests no path. It answers the one question a driver asks
  /// before committing — "are these stops near each other or across town?" —
  /// and leaves the decision entirely to them.
  double get pickupSpreadMetres => _spread(stops.map((s) => s.pickup));

  double get dropoffSpreadMetres => _spread(stops.map((s) => s.dropoff));

  factory BoardPool.fromJson(Map<String, dynamic> json) {
    final corridor = json['corridor'] as Map<String, dynamic>? ?? const {};
    return BoardPool(
      id: json['id'] as String,
      corridorId: corridor['id'] as String? ?? '',
      originCity: corridor['originCity'] as String? ?? '',
      destCity: corridor['destCity'] as String? ?? '',
      windowStart: DateTime.parse(json['windowStart'] as String),
      windowEnd: DateTime.parse(json['windowEnd'] as String),
      totalSeats: (json['totalSeats'] as num?)?.toInt() ?? 0,
      riderCount: (json['riderCount'] as num?)?.toInt() ?? 0,
      pricePerSeat: (json['pricePerSeat'] as num?)?.toInt() ?? 0,
      estimatedFare: (json['estimatedFare'] as num?)?.toInt() ?? 0,
      stops: ((json['stops'] as List<dynamic>?) ?? const [])
          .map((e) => PoolStop.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Widest distance between any pair of [points], in metres. 0 for fewer than
/// two points.
double _spread(Iterable<LocationPoint> points) {
  final list = points.where((p) => p.hasCoordinates).toList();
  var worst = 0.0;
  for (var i = 0; i < list.length; i++) {
    for (var j = i + 1; j < list.length; j++) {
      final d = distanceMetres(list[i], list[j]);
      if (d > worst) worst = d;
    }
  }
  return worst;
}

/// Great-circle distance in metres (haversine).
///
/// Iraq's corridors are ~100km, so the spherical error against a proper geodesic
/// is well under a percent — far below the precision of "are these stops near
/// each other".
double distanceMetres(LocationPoint a, LocationPoint b) {
  const earthRadius = 6371000.0;
  final dLat = _rad(b.lat - a.lat);
  final dLng = _rad(b.lng - a.lng);
  final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_rad(a.lat)) *
          math.cos(_rad(b.lat)) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  return 2 * earthRadius * math.asin(math.min(1, math.sqrt(h)));
}

double _rad(double deg) => deg * math.pi / 180;

/// How practical a set of stops is, as one word.
enum StopSpread { single, tight, moderate, wide }

/// Bucket a spread distance. Thresholds are deliberately coarse — the driver is
/// making a yes/no call, not measuring.
StopSpread spreadOf(double metres, {int stopCount = 2}) {
  if (stopCount < 2) return StopSpread.single;
  if (metres < 2000) return StopSpread.tight;
  if (metres < 6000) return StopSpread.moderate;
  return StopSpread.wide;
}

/// Why a claim was refused, as the SERVER classified it.
///
/// Parsed from the error `code`, never from the Arabic text: «استلم سائق آخر»
/// and «انخفض العدد» are opposite instructions to a driver — find another one
/// now versus wait — and a client that told them apart by string matching would
/// break silently the first time the wording improved.
enum ClaimRefusal {
  /// Someone else got there first. Look for another pool.
  alreadyClaimed,

  /// The pool's window shut, or it expired unclaimed. It is gone, not taken.
  gone,

  /// A rider cancelled and the pool fell under the viable minimum. Waiting may
  /// still bring it back.
  notViable,

  /// More seats than this vehicle holds.
  exceedsCapacity,

  /// Anything else — show the server's own message.
  other,
}

ClaimRefusal claimRefusalFrom(String? code) => switch (code) {
      'POOL_ALREADY_CLAIMED' => ClaimRefusal.alreadyClaimed,
      'POOL_EXPIRED' || 'POOL_WINDOW_PASSED' => ClaimRefusal.gone,
      'POOL_NOT_VIABLE' => ClaimRefusal.notViable,
      'POOL_EXCEEDS_CAPACITY' => ClaimRefusal.exceedsCapacity,
      _ => ClaimRefusal.other,
    };

/// One rider's answer to a proposed raise.
enum RaiseResponse { accepted, declined, awaiting }

RaiseResponse raiseResponseFrom(String? raw) => switch (raw) {
      'ACCEPTED' => RaiseResponse.accepted,
      'DECLINED' => RaiseResponse.declined,
      _ => RaiseResponse.awaiting,
    };

/// How a proposed raise ended.
enum RaiseOutcome { pending, accepted, failed }

RaiseOutcome raiseOutcomeFrom(String? raw) => switch (raw) {
      'ACCEPTED' => RaiseOutcome.accepted,
      'FAILED' => RaiseOutcome.failed,
      _ => RaiseOutcome.pending,
    };

/// One member of the pool and where they stand on the raise.
class RaiseResponseRow {
  const RaiseResponseRow({
    required this.riderName,
    required this.seatCount,
    required this.response,
    required this.released,
  });

  final String? riderName;
  final int seatCount;
  final RaiseResponse response;

  /// True once this rider has left the trip — declined and released, or
  /// released because the whole pool failed. Kept on the list deliberately:
  /// "where did the third one go?" is a question the driver asks, and removing
  /// the row makes the answer a disappearance.
  final bool released;

  factory RaiseResponseRow.fromJson(Map<String, dynamic> json) =>
      RaiseResponseRow(
        riderName: json['riderName'] as String?,
        seatCount: (json['seatCount'] as num?)?.toInt() ?? 1,
        response: raiseResponseFrom(json['response'] as String?),
        released: json['released'] as bool? ?? false,
      );
}

/// A proposed raise and where every rider stands on it.
class PoolRaise {
  const PoolRaise({
    required this.oldPricePerSeat,
    required this.newPricePerSeat,
    required this.respondBy,
    required this.resolved,
    required this.outcome,
    required this.acceptedSeats,
    required this.declinedSeats,
    required this.pendingSeats,
    required this.responses,
  });

  final int oldPricePerSeat;
  final int newPricePerSeat;
  final DateTime respondBy;
  final bool resolved;
  final RaiseOutcome outcome;
  final int acceptedSeats;
  final int declinedSeats;
  final int pendingSeats;
  final List<RaiseResponseRow> responses;

  bool get isWaiting => !resolved;

  factory PoolRaise.fromJson(Map<String, dynamic> json) => PoolRaise(
        oldPricePerSeat: (json['oldPricePerSeat'] as num?)?.toInt() ?? 0,
        newPricePerSeat: (json['newPricePerSeat'] as num?)?.toInt() ?? 0,
        respondBy: DateTime.parse(json['respondBy'] as String),
        resolved: json['resolved'] as bool? ?? false,
        outcome: raiseOutcomeFrom(json['outcome'] as String?),
        acceptedSeats: (json['acceptedSeats'] as num?)?.toInt() ?? 0,
        declinedSeats: (json['declinedSeats'] as num?)?.toInt() ?? 0,
        pendingSeats: (json['pendingSeats'] as num?)?.toInt() ?? 0,
        responses: ((json['responses'] as List<dynamic>?) ?? const [])
            .map((e) => RaiseResponseRow.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// The pool behind a claimed trip (GET /pools/mine/:tripId).
///
/// `null` from that endpoint is a correct answer, not an error: a trip the
/// driver posted themselves has no pool, and the app asks about every trip
/// without knowing in advance which came from one.
class DriverPool {
  const DriverPool({
    required this.poolId,
    required this.tripId,
    required this.pricePerSeat,
    required this.maxPricePerSeat,
    required this.seatsTaken,
    required this.seatsTotal,
    required this.minSeats,
    required this.raiseDeadline,
    required this.responseMinutes,
    required this.canPropose,
    required this.blockedReason,
    required this.windowStart,
    required this.windowEnd,
    this.raise,
  });

  final String poolId;
  final String tripId;
  final int pricePerSeat;

  /// The corridor's ceiling — the admin's number, and the hard cap on any
  /// proposal.
  final int maxPricePerSeat;

  final int seatsTaken;
  final int seatsTotal;

  /// The viability floor. Below this many accepted seats the whole pool ends —
  /// which is why the driver has to see it BEFORE proposing.
  final int minSeats;

  /// Last moment a proposal is accepted. Server-computed from the window start
  /// and the blackout, never re-derived here.
  final DateTime raiseDeadline;

  /// How long riders get to answer.
  final int responseMinutes;

  /// Whether `POST /pools/:id/raise` would succeed right now.
  ///
  /// Server-computed from the SAME conditions that endpoint enforces. An action
  /// the UI offers and the server refuses is worse than no action — the same
  /// locked rule as `ratable` on a booking.
  final bool canPropose;

  /// Why not, in the driver's words. Null exactly when [canPropose].
  final String? blockedReason;

  final DateTime windowStart;
  final DateTime windowEnd;

  final PoolRaise? raise;

  int get emptySeats => seatsTotal - seatsTaken;

  /// Cash in hand as things stand.
  int get currentTake => pricePerSeat * seatsTaken;

  factory DriverPool.fromJson(Map<String, dynamic> json) => DriverPool(
        poolId: json['poolId'] as String,
        tripId: json['tripId'] as String,
        pricePerSeat: (json['pricePerSeat'] as num?)?.toInt() ?? 0,
        maxPricePerSeat: (json['maxPricePerSeat'] as num?)?.toInt() ?? 0,
        seatsTaken: (json['seatsTaken'] as num?)?.toInt() ?? 0,
        seatsTotal: (json['seatsTotal'] as num?)?.toInt() ?? 0,
        minSeats: (json['minSeats'] as num?)?.toInt() ?? 2,
        raiseDeadline: DateTime.parse(json['raiseDeadline'] as String),
        responseMinutes: (json['responseMinutes'] as num?)?.toInt() ?? 10,
        canPropose: json['canPropose'] as bool? ?? false,
        blockedReason: json['blockedReason'] as String?,
        windowStart: DateTime.parse(json['windowStart'] as String),
        windowEnd: DateTime.parse(json['windowEnd'] as String),
        raise: json['raise'] == null
            ? null
            : PoolRaise.fromJson(json['raise'] as Map<String, dynamic>),
      );
}
