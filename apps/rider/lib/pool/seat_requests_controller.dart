import 'package:flutter/foundation.dart';
import 'package:shared/shared.dart';

import 'seat_request_api.dart';
import 'seat_request_models.dart';

enum SeatRequestsStatus { loading, error, loaded }

/// The rider's own seat requests: load, cancel, answer a raise.
///
/// Deliberately a SEPARATE controller from `MyBookingsController` even though
/// both feed one screen. They are two endpoints with two failure modes, and a
/// dead `/seat-requests/mine` must not be able to take the bookings list — the
/// thing riders actually depend on — down with it.
class SeatRequestsController extends ChangeNotifier {
  SeatRequestsController({required SeatRequestApi api}) : _api = api;

  final SeatRequestApi _api;

  SeatRequestsStatus _status = SeatRequestsStatus.loading;
  List<SeatRequest> _requests = const [];
  String? _error;
  bool _hasLoaded = false;
  final Set<String> _busy = {};

  SeatRequestsStatus get status => _status;
  String? get error => _error;
  bool get hasLoaded => _hasLoaded;

  /// Everything, newest first, as the server ordered it.
  List<SeatRequest> get all => _requests;

  /// The ones still going somewhere. These are what the rider checks for.
  List<SeatRequest> get live => _requests.where((r) => r.stage.isLive).toList();

  /// An open raise waiting on this rider. At most one matters at a time: the
  /// screen surfaces it above everything else because it is the only thing
  /// here with a deadline attached.
  SeatRequest? get pendingRaise {
    for (final r in _requests) {
      if (r.stage == SeatRequestStage.raisePending && r.raise != null) return r;
    }
    return null;
  }

  bool isBusy(String id) => _busy.contains(id);

  /// True while anything here is worth re-asking the server about.
  bool get hasLiveRequests => live.isNotEmpty;

  /// Background refresh: no spinner, and **on failure the last good list stays
  /// on screen and nothing is reported**. The rider did not ask for it.
  Future<void> refreshSilently() => load(silent: true);

  Future<void> load({bool silent = false}) async {
    if (!silent) {
      _status = SeatRequestsStatus.loading;
      _error = null;
      notifyListeners();
    }
    try {
      _requests = await _api.listMine();
      _status = SeatRequestsStatus.loaded;
      _error = null;
    } on ApiException catch (e) {
      if (!silent) {
        _error = e.message;
        _status = SeatRequestsStatus.error;
      }
    } catch (_) {
      if (!silent) {
        _error = 'تعذّر تحميل طلباتك. حاول مرة أخرى.';
        _status = SeatRequestsStatus.error;
      }
    } finally {
      _hasLoaded = true;
      notifyListeners();
    }
  }

  /// Cancel a request nobody has claimed. Returns null on success, else the
  /// message to show.
  Future<String?> cancel(String id) async {
    if (_busy.contains(id)) return null;
    _busy.add(id);
    notifyListeners();
    try {
      await _api.cancel(id);
      await load(silent: true);
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'تعذّر إلغاء الطلب. حاول مرة أخرى.';
    } finally {
      _busy.remove(id);
      notifyListeners();
    }
  }

  /// Answer a price raise. Returns null on success, else the message.
  ///
  /// Reloads either way, because the answer changes the stage — accepting
  /// turns it back into a plain confirmed booking, declining ends it — and a
  /// screen still offering the choice after it was made is worse than a slow
  /// one.
  Future<String?> respondToRaise(String id, {required bool accept}) async {
    if (_busy.contains(id)) return null;
    _busy.add(id);
    notifyListeners();
    try {
      await _api.respondToRaise(id, accept: accept);
      await load(silent: true);
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'تعذّر إرسال ردّك. حاول مرة أخرى.';
    } finally {
      _busy.remove(id);
      notifyListeners();
    }
  }
}
