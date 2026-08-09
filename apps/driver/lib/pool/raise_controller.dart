import 'package:flutter/foundation.dart';
import 'package:shared/shared.dart';

import 'pool_api.dart';
import 'pool_models.dart';

/// The pool behind ONE claimed trip: the raise rules, the proposal, and the
/// waiting state afterwards.
///
/// Scoped to the trip detail screen and disposed with it. A driver-posted trip
/// simply resolves to [pool] == null and the screen shows nothing extra — the
/// app asks about every trip without knowing in advance which came from a pool.
class RaiseController extends ChangeNotifier {
  RaiseController({required PoolApi api, required this.tripId}) : _api = api;

  final PoolApi _api;
  final String tripId;

  DriverPool? _pool;
  bool _loading = false;
  bool _hasLoaded = false;
  bool _proposing = false;
  String? _error;

  DriverPool? get pool => _pool;
  bool get loading => _loading;
  bool get hasLoaded => _hasLoaded;
  bool get proposing => _proposing;
  String? get error => _error;

  /// True when this trip came from a pool at all.
  bool get isPooled => _pool != null;

  /// A proposal is open and riders are still answering.
  bool get isWaiting => _pool?.raise?.isWaiting ?? false;

  /// Something on this screen can still change on its own — an open raise is
  /// resolved by the server when its deadline passes, with no action from the
  /// driver, so the screen has to keep asking.
  bool get isLive => isWaiting;

  Future<void> refreshSilently() => load(silent: true);

  Future<void> load({bool silent = false}) async {
    if (!silent) {
      _loading = true;
      _error = null;
      notifyListeners();
    }
    try {
      _pool = await _api.forTrip(tripId);
      _error = null;
    } on ApiException catch (e) {
      // Silent failures leave the last good state on screen and say nothing —
      // this panel is secondary to the trip itself, and a driver mid-pickup
      // does not need a banner about it.
      if (!silent) _error = e.message;
    } catch (_) {
      if (!silent) _error = 'تعذّر تحميل حالة التجمّع.';
    } finally {
      _loading = false;
      _hasLoaded = true;
      notifyListeners();
    }
  }

  /// Propose [newPricePerSeat]. Returns null on success, else the message.
  ///
  /// Reloads either way: on success the screen becomes the waiting state, and
  /// on failure the reason may be that the server's view moved (the trip
  /// filled, the deadline passed) — in which case the panel should stop
  /// offering the action it just refused.
  Future<String?> propose(int newPricePerSeat) async {
    final pool = _pool;
    if (pool == null || _proposing) return null;
    _proposing = true;
    notifyListeners();
    try {
      await _api.proposeRaise(pool.poolId, newPricePerSeat);
      return null;
    } on ApiException catch (e) {
      // Every refusal here is specific and actionable — over the cap, already
      // proposed, past the deadline, trip full — so the server's own sentence
      // is what the driver needs, not a generic one.
      return e.message;
    } catch (_) {
      return 'تعذّر إرسال الاقتراح. حاول مرة أخرى.';
    } finally {
      _proposing = false;
      notifyListeners();
      await load(silent: true);
    }
  }
}
