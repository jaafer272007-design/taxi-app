import '../booking/booking_models.dart' show GeoPoint;

/// What the rider is waiting for — **decided by the server**, never re-derived.
///
/// Telling «ننتظر ركّاباً» from «ننتظر سائقاً» needs `POOL_MIN_SEATS`, a policy
/// number. Comparing a seat count against a `2` written in Dart would give the
/// policy two homes, and the first time the threshold moved the app would start
/// lying to the rider. Same locked rule as «قادمة»/«سابقة»: the server decides,
/// the app files the card where it is told.
enum SeatRequestStage {
  /// The pool has not reached the viable minimum yet.
  waitingForRiders,

  /// Enough seats; now it needs a driver to claim it from the board.
  waitingForDriver,

  /// The claiming driver proposed a higher price and this rider has not
  /// answered. The only stage that asks the rider to *do* something.
  raisePending,

  /// A driver claimed it — there is a real booking now.
  claimed,

  /// The rider cancelled before it was claimed.
  cancelled,

  /// The rider declined a price raise and was released.
  declined,

  /// The window passed with no driver, or a raise failed to reach the minimum.
  expired,

  /// An old app meeting a newer server. Renders as neutral rather than wrong.
  unknown,
}

SeatRequestStage seatRequestStageFrom(String? raw) => switch (raw) {
      'WAITING_FOR_RIDERS' => SeatRequestStage.waitingForRiders,
      'WAITING_FOR_DRIVER' => SeatRequestStage.waitingForDriver,
      'RAISE_PENDING' => SeatRequestStage.raisePending,
      'CLAIMED' => SeatRequestStage.claimed,
      'CANCELLED' => SeatRequestStage.cancelled,
      'DECLINED' => SeatRequestStage.declined,
      'EXPIRED' => SeatRequestStage.expired,
      _ => SeatRequestStage.unknown,
    };

extension SeatRequestStageX on SeatRequestStage {
  /// Still going somewhere — drives both the list section and whether to poll.
  bool get isLive =>
      this == SeatRequestStage.waitingForRiders ||
      this == SeatRequestStage.waitingForDriver ||
      this == SeatRequestStage.raisePending;

  /// Over, one way or another.
  bool get isTerminal =>
      this == SeatRequestStage.cancelled ||
      this == SeatRequestStage.declined ||
      this == SeatRequestStage.expired;

  /// Only a request nobody has claimed can be cancelled AS A REQUEST. Once
  /// claimed it is a booking, and cancelling it goes through the booking rules
  /// — the server refuses anything else.
  bool get canCancel =>
      this == SeatRequestStage.waitingForRiders ||
      this == SeatRequestStage.waitingForDriver;
}

/// The driver's proposal to raise the price of a pool the rider already joined.
class SeatRequestRaise {
  const SeatRequestRaise({
    required this.oldPricePerSeat,
    required this.newPricePerSeat,
    required this.respondBy,
    this.myResponse,
  });

  final int oldPricePerSeat;
  final int newPricePerSeat;

  /// After this instant, no answer counts as a decline. Shown to the rider as
  /// a plain time, never as a pressure countdown.
  final DateTime respondBy;

  /// `'ACCEPTED'` / `'DECLINED'` / null when they have not answered.
  final String? myResponse;

  bool get answered => myResponse != null;
  bool get accepted => myResponse == 'ACCEPTED';

  /// Extra per seat. Arithmetic, not policy — safe to compute here.
  int get differencePerSeat => newPricePerSeat - oldPricePerSeat;

  factory SeatRequestRaise.fromJson(Map<String, dynamic> json) => SeatRequestRaise(
        oldPricePerSeat: (json['oldPricePerSeat'] as num).toInt(),
        newPricePerSeat: (json['newPricePerSeat'] as num).toInt(),
        respondBy: DateTime.parse(json['respondBy'] as String),
        myResponse: json['myResponse'] as String?,
      );
}

/// One rider-initiated seat request (GET /seat-requests/mine).
class SeatRequest {
  const SeatRequest({
    required this.id,
    required this.stage,
    required this.seatCount,
    required this.windowStart,
    required this.windowEnd,
    required this.pickup,
    required this.dropoff,
    required this.originCity,
    required this.destCity,
    required this.createdAt,
    this.pricePerSeat,
    this.poolSeats,
    this.bookingId,
    this.tripId,
    this.raise,
  });

  final String id;
  final SeatRequestStage stage;
  final int seatCount;
  final DateTime windowStart;
  final DateTime windowEnd;
  final GeoPoint pickup;
  final GeoPoint dropoff;
  final String originCity;
  final String destCity;
  final DateTime createdAt;

  /// The price the rider committed to. From the POOL, not the corridor — an
  /// admin re-pricing the corridor afterwards must not change it.
  final int? pricePerSeat;

  /// Seats gathered so far, for «ننتظر ركّاباً».
  final int? poolSeats;

  /// Set once a driver claims: **the bridge into the existing booking UI**.
  /// Without it the app would not know which booking to open, and a claimed
  /// request would become a parallel universe instead of a booking.
  final String? bookingId;
  final String? tripId;

  /// Non-null only while a raise is open and unresolved.
  final SeatRequestRaise? raise;

  /// Total the rider would pay at the committed price.
  int? get totalFare =>
      pricePerSeat == null ? null : pricePerSeat! * seatCount;

  factory SeatRequest.fromJson(Map<String, dynamic> json) {
    final corridor = (json['corridor'] as Map<String, dynamic>?) ?? const {};
    GeoPoint point(String key) {
      final p = (json[key] as Map<String, dynamic>?) ?? const {};
      return GeoPoint(
        lat: (p['lat'] as num?)?.toDouble() ?? 0,
        lng: (p['lng'] as num?)?.toDouble() ?? 0,
        label: p['label'] as String? ?? '',
      );
    }

    return SeatRequest(
      id: json['id'] as String,
      stage: seatRequestStageFrom(json['stage'] as String?),
      seatCount: (json['seatCount'] as num?)?.toInt() ?? 1,
      windowStart: DateTime.parse(json['windowStart'] as String),
      windowEnd: DateTime.parse(json['windowEnd'] as String),
      pickup: point('pickup'),
      dropoff: point('dropoff'),
      originCity: corridor['originCity'] as String? ?? '',
      destCity: corridor['destCity'] as String? ?? '',
      pricePerSeat: (json['pricePerSeat'] as num?)?.toInt(),
      poolSeats: (json['poolSeats'] as num?)?.toInt(),
      bookingId: json['bookingId'] as String?,
      tripId: json['tripId'] as String?,
      raise: json['raise'] == null
          ? null
          : SeatRequestRaise.fromJson(json['raise'] as Map<String, dynamic>),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

/// What the rider fills in to ask for a seat.
class SeatRequestDraft {
  const SeatRequestDraft({
    required this.corridorId,
    required this.windowStart,
    required this.windowEnd,
    required this.pickup,
    required this.dropoff,
    required this.seatCount,
  });

  final String corridorId;
  final DateTime windowStart;
  final DateTime windowEnd;
  final GeoPoint pickup;
  final GeoPoint dropoff;
  final int seatCount;

  Map<String, dynamic> toJson() => {
        'corridorId': corridorId,
        // The wire is always UTC; the form works in the rider's local clock.
        'windowStart': windowStart.toUtc().toIso8601String(),
        'windowEnd': windowEnd.toUtc().toIso8601String(),
        'pickup': pickup.toJson(),
        'dropoff': dropoff.toJson(),
        'seatCount': seatCount,
      };
}

/// Arabic label for a stage. Lives with the model so the list, the detail and
/// any future screen say the same words — a status the rider sees described two
/// ways is a status they cannot trust.
String seatRequestStageLabel(SeatRequestStage stage) => switch (stage) {
      SeatRequestStage.waitingForRiders => 'بانتظار ركّاب آخرين',
      SeatRequestStage.waitingForDriver => 'بانتظار سائق',
      SeatRequestStage.raisePending => 'السائق يقترح سعراً أعلى',
      SeatRequestStage.claimed => 'تأكّدت رحلتك',
      SeatRequestStage.cancelled => 'ألغيت الطلب',
      SeatRequestStage.declined => 'رفضت السعر الجديد',
      SeatRequestStage.expired => 'انتهت المهلة',
      SeatRequestStage.unknown => 'قيد المتابعة',
    };
