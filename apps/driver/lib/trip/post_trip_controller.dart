import 'package:flutter/foundation.dart';
import 'package:shared/shared.dart';

import 'driver_trip_api.dart';
import 'driver_trip_models.dart';

/// Departure mode for a new trip.
enum DepartMode { now, scheduled }

enum CorridorsLoad { loading, error, ready }

/// Drives the post-a-trip form: corridor selection, departure mode (now vs
/// scheduled), seat count (capped at the vehicle's seats), and submitting.
class PostTripController extends ChangeNotifier {
  PostTripController({required DriverTripApi api, required int maxSeats})
      : _api = api,
        _maxSeats = maxSeats < 1 ? 1 : maxSeats;

  final DriverTripApi _api;
  final int _maxSeats;

  CorridorsLoad _corridorsLoad = CorridorsLoad.loading;
  List<Corridor> _corridors = const []; // active only
  String? _origin;
  String? _dest;
  String? _corridorsError;

  DepartMode _mode = DepartMode.now;
  DateTime? _scheduledAt;
  int _seatCount = 1;
  TripType _tripType = TripType.general;

  // ── price (the driver sets it; the corridor only brackets it) ──
  /// Exactly what the driver typed, in WESTERN digits. Kept as a string so the
  /// field never fights the keyboard: a half-typed "1" of "12000" stays "1"
  /// rather than being reformatted mid-keystroke.
  String _priceInput = '';

  /// The corridor the current [_priceInput] was prefilled for. A different
  /// corridor means a different route, so the price is re-prefilled — carrying a
  /// Najaf→Baghdad price over to Najaf→Karbala would be meaningless.
  String? _pricedCorridorId;

  /// False until the driver leaves the field or presses submit. Flagging "out of
  /// range" while they are still typing the first digit of a valid price is the
  /// classic inline-validation mistake, so the error stays hidden until then.
  bool _priceTouched = false;

  /// A range rejection that came back from the server (the admin may have
  /// re-priced the corridor since this form loaded). Cleared the moment the
  /// driver edits the price, since it describes a value they've now changed.
  String? _serverPriceError;

  bool _submitting = false;
  String? _error;
  DriverTrip? _posted;

  CorridorsLoad get corridorsLoad => _corridorsLoad;
  List<Corridor> get corridors => _corridors;
  String? get origin => _origin;
  String? get dest => _dest;
  String? get corridorsError => _corridorsError;
  DepartMode get mode => _mode;
  DateTime? get scheduledAt => _scheduledAt;
  int get seatCount => _seatCount;
  TripType get tripType => _tripType;
  int get maxSeats => _maxSeats;
  bool get submitting => _submitting;
  String? get error => _error;
  DriverTrip? get posted => _posted;

  /// The active corridor serving the picked (origin, dest), or null — the driver
  /// can only post once the admin has created a corridor for this pair.
  Corridor? get matchedCorridor {
    final o = _origin;
    final d = _dest;
    if (o == null || d == null) return null;
    for (final c in _corridors) {
      if (c.originCity == o && c.destCity == d) return c;
    }
    return null;
  }

  /// Both cities chosen and distinct, but no active corridor serves them yet.
  bool get noCorridorForPair =>
      _origin != null &&
      _dest != null &&
      _origin != _dest &&
      matchedCorridor == null;

  /// The raw text in the price field (Western digits — the locked input rule).
  String get priceInput => _priceInput;

  /// The driver's price as a number, or null when the field is empty or not a
  /// positive whole number of dinars.
  int? get enteredPrice {
    final digits = toWesternDigits(_priceInput).trim();
    if (digits.isEmpty) return null;
    final value = int.tryParse(digits);
    if (value == null || value <= 0) return null;
    return value;
  }

  /// The admin's suggestion for the matched corridor (IQD), or 0 if none.
  int get suggestedPrice => matchedCorridor?.suggestedPricePerSeat ?? 0;

  /// Inclusive bounds the driver's price must fall in (IQD).
  int get minPrice => matchedCorridor?.minPricePerSeat ?? 0;
  int get maxPrice => matchedCorridor?.maxPricePerSeat ?? 0;

  /// True once the price is a positive integer inside the corridor's band.
  bool get priceValid {
    final price = enteredPrice;
    if (price == null || matchedCorridor == null) return false;
    return price >= minPrice && price <= maxPrice;
  }

  /// The Arabic error under the price field, or null when there is nothing to
  /// say YET — the field is untouched, or the price is fine.
  ///
  /// The out-of-range text names the actual range, in Arabic-Indic numerals: an
  /// error that only says "invalid" leaves the driver guessing at the fix.
  String? get priceError {
    if (_serverPriceError != null) return _serverPriceError;
    if (!_priceTouched || matchedCorridor == null) return null;
    final price = enteredPrice;
    if (price == null) return 'أدخل سعر المقعد بالدينار.';
    if (price < minPrice || price > maxPrice) {
      return _rangeMessage(minPrice, maxPrice);
    }
    return null;
  }

  /// The one phrasing of "your price is outside the allowed range", used by both
  /// the client-side check and the server's rejection so the driver never sees
  /// the same problem described two different ways.
  String _rangeMessage(int min, int max) => min == max
      ? 'السعر على هذا المسار ثابت: ${formatPrice(min)}.'
      : 'السعر يجب أن يكون بين ${formatIqd(min)} و${formatPrice(max)}.';

  /// True when a one-tap "use the usual price" shortcut would actually change
  /// something — hidden when the field already holds the suggestion.
  bool get canUseSuggestedPrice =>
      matchedCorridor != null && enteredPrice != suggestedPrice;

  /// What a full car pays at the entered price, or null while the price is not
  /// usable. A total computed from a rejected price is worse than no total.
  int? get fullCarTotal => priceValid ? enteredPrice! * _seatCount : null;

  bool get canDecrement => _seatCount > 1;
  bool get canIncrement => _seatCount < _maxSeats;

  bool get canSubmit =>
      !_submitting &&
      matchedCorridor != null &&
      priceValid &&
      (_mode == DepartMode.now || _scheduledAt != null);

  /// Load active corridors once (idempotent); defaults the from/to cities to the
  /// first served corridor.
  Future<void> loadCorridors() async {
    if (_corridors.isNotEmpty) return;
    _corridorsLoad = CorridorsLoad.loading;
    _corridorsError = null;
    notifyListeners();
    try {
      final all = await _api.getCorridors();
      _corridors = all.where((c) => c.active).toList();
      if (_origin == null && _dest == null && _corridors.isNotEmpty) {
        // Prefer the flagship pair over whichever corridor happens to sort
        // first — with all 306 pairs served, "first" is alphabetical accident.
        final preferred = _corridors.firstWhere(
          (c) =>
              c.originCity == kDefaultOriginCity &&
              c.destCity == kDefaultDestCity,
          orElse: () => _corridors.first,
        );
        _origin = preferred.originCity;
        _dest = preferred.destCity;
      }
      // Corridors only just arrived, so this is the first moment the default
      // route resolves to a corridor with a suggestion to prefill.
      _syncPriceToCorridor();
      _corridorsLoad = CorridorsLoad.ready;
    } on ApiException catch (e) {
      _corridorsError = e.message;
      _corridorsLoad = CorridorsLoad.error;
    } catch (_) {
      _corridorsError = 'تعذّر تحميل المسارات. حاول مرة أخرى.';
      _corridorsLoad = CorridorsLoad.error;
    } finally {
      notifyListeners();
    }
  }

  void setOrigin(String city) {
    _origin = city;
    _syncPriceToCorridor();
    notifyListeners();
  }

  void setDest(String city) {
    _dest = city;
    _syncPriceToCorridor();
    notifyListeners();
  }

  /// Swap the from/to cities.
  void swapCities() {
    final o = _origin;
    _origin = _dest;
    _dest = o;
    _syncPriceToCorridor();
    notifyListeners();
  }

  /// The driver types a price. Western digits only — see [priceInput].
  ///
  /// Deliberately does NOT set [_priceTouched]: the error appears on blur or
  /// submit, never mid-keystroke. The "if the car fills" total still recomputes
  /// live, because feedback and validation are different things.
  void setPriceInput(String raw) {
    if (_priceInput == raw) return;
    _priceInput = raw;
    _serverPriceError = null; // it described the value they just changed
    notifyListeners();
  }

  /// The driver left the price field — now it is fair to show an error.
  void markPriceTouched() {
    if (_priceTouched) return;
    _priceTouched = true;
    notifyListeners();
  }

  /// One tap to take the admin's suggestion, so the safe choice is the cheapest
  /// one to make.
  void useSuggestedPrice() {
    final corridor = matchedCorridor;
    if (corridor == null) return;
    _priceInput = '${corridor.suggestedPricePerSeat}';
    _priceTouched = false; // a value we chose for them can't be their mistake
    _serverPriceError = null;
    notifyListeners();
  }

  /// Re-prefill the price whenever the matched corridor changes (including to
  /// none). Called by every mutation that can change which corridor is matched.
  void _syncPriceToCorridor() {
    final corridor = matchedCorridor;
    if (corridor?.id == _pricedCorridorId) return;
    _pricedCorridorId = corridor?.id;
    _priceInput = corridor == null ? '' : '${corridor.suggestedPricePerSeat}';
    _priceTouched = false;
    _serverPriceError = null;
  }

  void setMode(DepartMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
  }

  void setTripType(TripType type) {
    if (_tripType == type) return;
    _tripType = type;
    notifyListeners();
  }

  void setScheduledAt(DateTime? at) {
    _scheduledAt = at;
    notifyListeners();
  }

  void setSeatCount(int value) {
    final clamped = value.clamp(1, _maxSeats).toInt();
    if (clamped == _seatCount) return;
    _seatCount = clamped;
    notifyListeners();
  }

  void incrementSeat() => setSeatCount(_seatCount + 1);
  void decrementSeat() => setSeatCount(_seatCount - 1);

  /// Submit the trip. Returns true on success ([posted] then set).
  ///
  /// Pressing submit counts as touching the price, so a driver who never
  /// entered the field still gets told what is wrong instead of watching a
  /// disabled button do nothing.
  Future<bool> submit() async {
    if (_submitting) return false;
    if (!canSubmit) {
      _priceTouched = true;
      notifyListeners();
      return false;
    }
    _submitting = true;
    _error = null;
    notifyListeners();
    try {
      _posted = await _api.postTrip(
        corridorId: matchedCorridor!.id,
        seatsTotal: _seatCount,
        pricePerSeat: enteredPrice!,
        departNow: _mode == DepartMode.now,
        departureTime: _mode == DepartMode.scheduled ? _scheduledAt : null,
        tripType: _tripType,
      );
      return true;
    } on ApiException catch (e) {
      // The server is the authority on the range — the corridor may have been
      // re-priced by the admin since this form loaded. Show its rejection under
      // the price field (where the fix is), phrased exactly like the client-side
      // one, and with the bounds re-rendered in Arabic-Indic numerals.
      if (e.code == _kPriceOutOfRange) {
        _serverPriceError = _rangeMessage(
          e.detailInt('minPricePerSeat') ?? minPrice,
          e.detailInt('maxPricePerSeat') ?? maxPrice,
        );
        _priceTouched = true;
      } else {
        _error = e.message;
      }
      return false;
    } catch (_) {
      _error = 'حدث خطأ غير متوقع. حاول مرة أخرى.';
      return false;
    } finally {
      _submitting = false;
      notifyListeners();
    }
  }
}

/// The backend's code for a price outside the corridor's band (see
/// `services/api/src/trip/trip-errors.ts`).
const String _kPriceOutOfRange = 'TRIP_PRICE_OUT_OF_RANGE';
