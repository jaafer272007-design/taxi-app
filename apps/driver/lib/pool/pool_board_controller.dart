import 'package:flutter/foundation.dart';
import 'package:shared/shared.dart';

import 'pool_api.dart';
import 'pool_models.dart';

enum PoolBoardStatus { loading, error, loaded }

/// The outcome of tapping «استلم».
///
/// A claim has three genuinely different endings and the driver's next move
/// differs in each: go to رحلاتي, look for another pool, or wait. Collapsing
/// them into "worked / didn't work" is what would make the loser of a race
/// stare at a generic error.
sealed class ClaimResult {
  const ClaimResult();
}

/// It is yours; [tripId] is the ordinary trip it became.
class ClaimWon extends ClaimResult {
  const ClaimWon(this.tripId);
  final String tripId;
}

/// Refused, with the server's classification and its own message.
class ClaimRefused extends ClaimResult {
  const ClaimRefused(this.refusal, this.message);
  final ClaimRefusal refusal;
  final String message;
}

/// The board of claimable pools.
///
/// Separate from [MyTripsController] on purpose even though claiming moves a
/// row from one to the other: they are two endpoints with two failure modes,
/// and a dead board must not be able to take رحلاتي down with it.
class PoolBoardController extends ChangeNotifier {
  PoolBoardController({required PoolApi api, required this.vehicleSeats})
      : _api = api;

  final PoolApi _api;

  /// The driver's own capacity — what "a full car" means on every card, and the
  /// number the board was already filtered by server-side.
  final int vehicleSeats;

  PoolBoardStatus _status = PoolBoardStatus.loading;
  List<BoardPool> _pools = const [];
  String? _error;
  bool _hasLoaded = false;
  String? _claiming;

  PoolBoardStatus get status => _status;
  List<BoardPool> get pools => _pools;
  String? get error => _error;
  bool get hasLoaded => _hasLoaded;
  bool get isEmpty => _pools.isEmpty;

  /// How many pools are on the board — drawn on the segment so a driver who has
  /// never opened it learns it exists.
  int get count => _pools.length;

  bool isClaiming(String poolId) => _claiming == poolId;

  /// True while a claim is in flight anywhere — every other claim button goes
  /// inert, because two claims from one driver is never what was meant.
  bool get busy => _claiming != null;

  /// Background refresh: no spinner, and on failure the last good board stays
  /// on screen with nothing reported. The driver did not ask for it.
  Future<void> refreshSilently() => load(silent: true);

  Future<void> load({bool silent = false}) async {
    if (!silent) {
      _status = PoolBoardStatus.loading;
      _error = null;
      notifyListeners();
    }
    try {
      _pools = await _api.board();
      _status = PoolBoardStatus.loaded;
      _error = null;
    } on ApiException catch (e) {
      if (!silent) {
        _error = e.message;
        _status = PoolBoardStatus.error;
      }
    } catch (_) {
      if (!silent) {
        _error = 'تعذّر تحميل التجمّعات. حاول مرة أخرى.';
        _status = PoolBoardStatus.error;
      }
    } finally {
      _hasLoaded = true;
      notifyListeners();
    }
  }

  /// Claim [poolId]. Always reloads afterwards, win or lose: either the pool is
  /// gone from the board because it is now the driver's trip, or it is gone
  /// because it is someone else's — and both are things the board must stop
  /// showing.
  Future<ClaimResult> claim(String poolId) async {
    if (_claiming != null) {
      return const ClaimRefused(ClaimRefusal.other, 'جارٍ الاستلام…');
    }
    _claiming = poolId;
    notifyListeners();
    try {
      final tripId = await _api.claim(poolId);
      return ClaimWon(tripId);
    } on ApiException catch (e) {
      return ClaimRefused(claimRefusalFrom(e.code), e.message);
    } catch (_) {
      return const ClaimRefused(
        ClaimRefusal.other,
        'تعذّر استلام التجمّع. حاول مرة أخرى.',
      );
    } finally {
      _claiming = null;
      notifyListeners();
      await load(silent: true);
    }
  }
}
