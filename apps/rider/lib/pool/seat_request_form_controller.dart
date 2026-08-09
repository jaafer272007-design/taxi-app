import 'package:flutter/material.dart';
import 'package:shared/shared.dart';

import '../booking/booking_models.dart';
import 'seat_request_api.dart';
import 'seat_request_models.dart';

/// Fills in one seat request: the window, the seats, the two points.
///
/// The window is the whole reason pooling can work at all — two riders match
/// when their windows overlap — so the form asks for **earliest and latest**,
/// never a single time. A single time would pool almost nobody, and a rider
/// whose request never matched would have no way to understand why.
class SeatRequestFormController extends ChangeNotifier {
  SeatRequestFormController({
    required SeatRequestApi api,
    required this.corridorId,
    required this.originCity,
    required this.destCity,
    required this.pricePerSeat,
    DateTime? day,
  })  : _api = api,
        _day = day ?? _today() {
    // Sensible default points: the city centres, exactly as the booking form
    // does, so the map opens somewhere recognisable rather than at Null Island.
    _pickup = cityCenter(originCity);
    _dropoff = cityCenter(destCity);
  }

  final SeatRequestApi _api;

  final String corridorId;
  final String originCity;
  final String destCity;

  /// The corridor's suggested price — what the rider will pay per seat unless
  /// they later accept a raise. Shown BEFORE they commit; never a surprise.
  final int pricePerSeat;

  DateTime _day;
  TimeOfDay _from = const TimeOfDay(hour: 7, minute: 0);
  TimeOfDay _to = const TimeOfDay(hour: 10, minute: 0);
  int _seatCount = 1;

  late GeoPoint _pickup;
  late GeoPoint _dropoff;
  bool _pickupSet = false;
  bool _dropoffSet = false;

  bool _submitting = false;
  String? _error;
  SeatRequest? _result;

  DateTime get day => _day;
  TimeOfDay get from => _from;
  TimeOfDay get to => _to;
  int get seatCount => _seatCount;
  GeoPoint get pickup => _pickup;
  GeoPoint get dropoff => _dropoff;
  bool get pickupSet => _pickupSet;
  bool get dropoffSet => _dropoffSet;
  bool get submitting => _submitting;
  String? get error => _error;
  SeatRequest? get result => _result;

  int get totalFare => pricePerSeat * _seatCount;

  DateTime get windowStart => _at(_from);
  DateTime get windowEnd => _at(_to);

  /// Both points marked and the window the right way round. The server
  /// re-validates all of it — this only stops the rider submitting something
  /// it will refuse.
  bool get canSubmit =>
      _pickupSet &&
      _dropoffSet &&
      windowEnd.isAfter(windowStart) &&
      !_submitting;

  /// Why the CTA is disabled, in the rider's words. A disabled button with no
  /// explanation is the thing people file bug reports about.
  String? get blockedReason {
    if (!windowEnd.isAfter(windowStart)) {
      return 'اجعل «حتى» بعد «من».';
    }
    if (!_pickupSet) return 'حدّد نقطة الانطلاق على الخريطة.';
    if (!_dropoffSet) return 'حدّد نقطة النزول على الخريطة.';
    return null;
  }

  void setDay(DateTime value) {
    _day = DateTime(value.year, value.month, value.day);
    notifyListeners();
  }

  void setWindow(TimeOfDay from, TimeOfDay to) {
    _from = from;
    _to = to;
    notifyListeners();
  }

  void setSeatCount(int value) {
    _seatCount = value.clamp(1, 4);
    notifyListeners();
  }

  void setPickupPoint(GeoPoint point) {
    _pickup = point;
    _pickupSet = true;
    notifyListeners();
  }

  void setDropoffPoint(GeoPoint point) {
    _dropoff = point;
    _dropoffSet = true;
    notifyListeners();
  }

  Future<bool> submit() async {
    if (!canSubmit) return false;
    _submitting = true;
    _error = null;
    notifyListeners();
    try {
      _result = await _api.create(SeatRequestDraft(
        corridorId: corridorId,
        windowStart: windowStart,
        windowEnd: windowEnd,
        pickup: _pickup,
        dropoff: _dropoff,
        seatCount: _seatCount,
      ));
      return true;
    } on ApiException catch (e) {
      // The server's own words: a blocked rider, an overlapping request, a
      // window it refuses. All of them say something the rider can act on.
      _error = e.message;
      return false;
    } catch (_) {
      _error = 'تعذّر إرسال الطلب. حاول مرة أخرى.';
      return false;
    } finally {
      _submitting = false;
      notifyListeners();
    }
  }

  DateTime _at(TimeOfDay t) =>
      DateTime(_day.year, _day.month, _day.day, t.hour, t.minute);

  static DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }
}
