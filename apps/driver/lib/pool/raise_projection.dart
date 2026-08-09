import 'dart:math' as math;

/// What a proposed raise is actually worth, in the three ways it can land.
///
/// A driver proposing a higher price is trading **certainty for money**, and
/// the trade is not obviously good: riders who decline are released, so more
/// per seat can mean less in total. The screen must not make them do that
/// arithmetic under a deadline, and it must not show only the flattering
/// number.
///
/// Pure — no Flutter, no API — because these are the figures the whole decision
/// rests on and they deserve a unit test rather than a screenshot.
class RaiseProjection {
  const RaiseProjection({
    required this.seatsTaken,
    required this.currentPrice,
    required this.newPrice,
    required this.minSeats,
  });

  /// Seats currently held by pooled riders.
  final int seatsTaken;
  final int currentPrice;
  final int newPrice;

  /// The viability floor: below this many accepted seats the pool ends.
  final int minSeats;

  /// Cash if nothing changes — the number to beat.
  int get takeNow => seatsTaken * currentPrice;

  /// Cash if every rider accepts. The best case, and the least likely one.
  int get takeIfAllAccept => seatsTaken * newPrice;

  /// Cash if only the bare minimum accepts and the rest are released.
  ///
  /// This is the case that decides whether proposing is wise, which is why it
  /// is on screen next to the optimistic one rather than in a footnote.
  int get takeIfMinimumAccepts => math.min(seatsTaken, minSeats) * newPrice;

  /// True when even the worst surviving case still beats doing nothing.
  bool get minimumStillBeatsNow => takeIfMinimumAccepts > takeNow;

  /// True when the minimum case is a real loss — the driver would carry fewer
  /// riders for less money than they hold right now.
  bool get minimumIsWorseThanNow => takeIfMinimumAccepts < takeNow;

  /// Seats released if only the minimum accepts.
  int get seatsLostAtMinimum => math.max(0, seatsTaken - minSeats);

  /// Whether the pool can survive ANY decline at all.
  ///
  /// With exactly [minSeats] seats held, one decline ends the trip for
  /// everyone — the driver is not risking a smaller fare, they are risking the
  /// whole journey, and that is a different sentence.
  bool get anyDeclineEndsTrip => seatsTaken <= minSeats;
}
