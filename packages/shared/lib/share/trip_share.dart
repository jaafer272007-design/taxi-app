import '../constants/iraqi_cities.dart';
import '../format/numerals.dart';

/// Everything «شارك رحلتي» puts in front of the rider before they send it.
///
/// Every field is nullable except the route, because this is assembled from a
/// live API payload: a driver with no vehicle row, a trip with no corridor, a
/// name that was never set. A share that silently prints "null" into a message
/// a rider is about to send their family is worse than one that omits the line.
class TripShareDetails {
  const TripShareDetails({
    required this.originCity,
    required this.destCity,
    required this.departureTime,
    required this.seatCount,
    this.driverName,
    this.vehicleMake,
    this.vehicleModel,
    this.vehicleColor,
    this.plate,
  });

  /// Stored city KEYS (`Najaf`), not display names — the builder translates.
  final String? originCity;
  final String? destCity;
  final DateTime departureTime;
  final int seatCount;

  final String? driverName;
  final String? vehicleMake;
  final String? vehicleModel;
  final String? vehicleColor;

  /// The plate, exactly as registered. **The single most useful item here** —
  /// it is what lets someone identify this car in a rank of identical white
  /// Corollas.
  final String? plate;

  /// `Toyota Corolla أبيض`, dropping whichever parts are missing.
  String? get vehicleLine {
    final parts = [vehicleMake, vehicleModel, vehicleColor]
        .map((p) => p?.trim() ?? '')
        .where((p) => p.isNotEmpty);
    return parts.isEmpty ? null : parts.join(' ');
  }
}

/// The Arabic message the rider sends to whoever they choose.
///
/// ## Why this is a pure function and not string interpolation at the call site
///
/// It is the actual product of the feature — the thing that reaches a person
/// who does not have the app — so it is the thing to unit-test. Every rule it
/// encodes is invisible until it renders wrong on somebody else's phone.
///
/// ## The numerals, and why they are not uniform
///
/// * The **time** and the **seat count** are quantities to read, so they are
///   Arabic-Indic per the locked rule.
/// * The **plate is left exactly as registered** — Western digits and all. It
///   is an IDENTIFIER to be matched against a metal plate, in the same class as
///   a phone number and a coordinate (see `docs/PHASE1_BUILD_BRIEF.md` →
///   `trip-contacts`). Iraqi plates are stamped in Western digits; converting
///   them would hand the reader a string that does not match the car.
///
/// ## The ٠-dot hazard, in a place no golden can catch it
///
/// This text is rendered by WhatsApp, on a device we do not control, in a font
/// we did not choose. So the message never puts a dot-like separator next to an
/// Arabic-Indic digit — no `·`, and no `:` immediately before a numeral either.
/// Fields are joined with strong Arabic words («الساعة», «يوم», «من … إلى») and
/// each sits on its OWN LINE, so a bidi reorder can never drag a neighbouring
/// glyph into a number. `٠٧:٣٠` is safe as-is: that colon sits between two
/// digit runs, which is one directional run.
///
/// Cities are joined with «إلى» rather than an arrow, for the same reason the
/// app never draws one: the bundled Cairo has no arrow glyph, and we cannot
/// know what the recipient's phone will substitute.
String buildTripShareMessage(TripShareDetails d) {
  final lines = <String>[
    'أنا الآن في رحلة عبر تطبيق تكسي المشترك، وهذي تفاصيلها:',
    '',
  ];

  final driver = d.driverName?.trim();
  if (driver != null && driver.isNotEmpty) {
    lines.add('السائق: $driver');
  }

  final vehicle = d.vehicleLine;
  if (vehicle != null) {
    lines.add('السيارة: $vehicle');
  }

  final plate = d.plate?.trim();
  if (plate != null && plate.isNotEmpty) {
    lines.add('رقم اللوحة: $plate');
  }

  final origin = d.originCity?.trim();
  final dest = d.destCity?.trim();
  if (origin != null && origin.isNotEmpty && dest != null && dest.isNotEmpty) {
    lines.add('الطريق: من ${cityArName(origin)} إلى ${cityArName(dest)}');
  }

  // «يوم … الساعة …» — the joining words are load-bearing, not decoration:
  // they keep a bidi-neutral character away from every numeral.
  lines.add(
    'الانطلاق يوم ${formatDayShortBaghdad(d.departureTime)} '
    'الساعة ${formatTime(d.departureTime)}',
  );

  // «حجزت ٣ مقاعد», not «المقاعد: ٣» — same reason, and it reads like a
  // sentence a person would actually write.
  lines.add('حجزت ${formatSeats(d.seatCount)}');

  return lines.join('\n');
}
