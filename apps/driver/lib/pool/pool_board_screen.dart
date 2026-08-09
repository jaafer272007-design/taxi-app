import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import 'pool_board_controller.dart';
import 'pool_models.dart';

/// «التجمّعات» — the board of claimable pools.
///
/// ## The other way a driver gets work
///
/// Phase 1 has the driver announce a trip and wait. This is the reverse: riders
/// have already asked, the system has already grouped them, and the driver
/// takes the whole group in one tap. So it sits **beside posting a trip** in the
/// same tab rather than in a section of its own — they are alternatives for one
/// intent, and a driver deciding how to fill their morning should see both
/// without navigating.
///
/// ## Why it polls
///
/// A pool leaves this board the moment another driver claims it, and nothing
/// the reader does causes that. A stale board therefore sends drivers to tap a
/// claim that is already gone — the refusal is honest, but the wasted tap is
/// ours. [kPoolBoardPollInterval] while the tab is on screen.
class PoolBoardScreen extends StatefulWidget {
  const PoolBoardScreen({super.key, required this.onClaimed, this.header});

  /// Called with the new trip's id once a claim succeeds — the shell switches
  /// to رحلاتي, because that is where the thing now lives.
  final ValueChanged<String> onClaimed;

  /// Optional bar pinned under the app bar — the shell's mode selector.
  final Widget? header;

  @override
  State<PoolBoardScreen> createState() => _PoolBoardScreenState();
}

class _PoolBoardScreenState extends State<PoolBoardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final c = context.read<PoolBoardController>();
      if (!c.hasLoaded) c.load();
    });
  }

  Future<void> _onClaim(PoolBoardController c, BoardPool pool) async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: 'استلام التجمّع؟',
      message: 'ستصير رحلة باسمك تبدأ الساعة ${formatTime(pool.windowStart)}، '
          'ومعك ${formatSeats(pool.totalSeats)} محجوزة سلفاً. '
          'تجدها بعدها في «رحلاتي» مثل أي رحلة تنشرها.',
      confirmLabel: 'استلم',
      cancelLabel: 'تراجع',
    );
    if (!confirmed || !mounted) return;

    final result = await c.claim(pool.id);
    if (!mounted) return;

    switch (result) {
      case ClaimWon(:final tripId):
        _snack('استلمت التجمّع. صار رحلة في «رحلاتي».');
        widget.onClaimed(tripId);
      case ClaimRefused(:final refusal, :final message):
        // Each refusal is a DIFFERENT instruction: look elsewhere, wait, or
        // this was never yours. The server classified it; the app must not
        // flatten that back into one sentence.
        _showRefusal(refusal, message);
    }
  }

  void _showRefusal(ClaimRefusal refusal, String serverMessage) {
    final (String title, String body) = switch (refusal) {
      ClaimRefusal.alreadyClaimed => (
          'استلمه سائق آخر',
          'سبقك سائق آخر إلى هذا التجمّع. ما زالت هناك تجمّعات أخرى على اللوحة.',
        ),
      ClaimRefusal.gone => (
          'لم يعد هذا التجمّع قائماً',
          'انتهت مهلته قبل أن يستلمه أحد. حدّثنا اللوحة لك.',
        ),
      ClaimRefusal.notViable => (
          'انخفض عدد الركّاب',
          'ألغى أحد الركّاب طلبه فنزل التجمّع تحت الحد المجدي. قد يعود إن انضم راكب آخر.',
        ),
      ClaimRefusal.exceedsCapacity => (
          'أكبر من سعة سيارتك',
          'عدد المقاعد المطلوبة يتجاوز ما تحمله سيارتك.',
        ),
      ClaimRefusal.other => ('تعذّر الاستلام', serverMessage),
    };

    showAppConfirmDialog(
      context,
      title: title,
      message: body,
      confirmLabel: 'حسناً',
      // No second choice: there is nothing to confirm, only something to read.
      cancelLabel: null,
    );
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<PoolBoardController>();

    return PollingScope(
      interval: kPoolBoardPollInterval,
      // Always, while this tab is on screen: an empty board is exactly the
      // state a driver is waiting to change, and a pool can both appear and be
      // taken while they watch.
      refreshWhenVisible: true,
      onPoll: c.refreshSilently,
      child: AppScaffold(
        title: 'التجمّعات',
        header: widget.header,
        padded: false,
        body: _body(c),
      ),
    );
  }

  Widget _body(PoolBoardController c) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: context.space.lg),
      child: switch (c.status) {
        PoolBoardStatus.loading =>
          Center(child: CircularProgressIndicator(color: context.colors.primary)),
        PoolBoardStatus.error => _BoardError(
            message: c.error ?? 'حدث خطأ. حاول مرة أخرى.',
            onRetry: c.load,
          ),
        PoolBoardStatus.loaded => c.isEmpty
            ? _BoardEmpty(onRefresh: c.refreshSilently)
            : _BoardList(controller: c, onClaim: _onClaim),
      },
    );
  }
}

/// How often the board re-asks.
///
/// 20 seconds, the same beat as رحلاتي: what changes is another driver claiming,
/// and the cost of being late is a wasted tap rather than a missed booking.
const Duration kPoolBoardPollInterval = Duration(seconds: 20);

class _BoardList extends StatelessWidget {
  const _BoardList({required this.controller, required this.onClaim});

  final PoolBoardController controller;
  final Future<void> Function(PoolBoardController, BoardPool) onClaim;

  @override
  Widget build(BuildContext context) {
    final space = context.space;
    final pools = controller.pools;

    return RefreshIndicator(
      color: context.colors.primary,
      onRefresh: controller.refreshSilently,
      child: ListView.separated(
        padding: EdgeInsets.only(
          top: space.md,
          bottom: space.xl4,
        ),
        itemCount: pools.length + 1,
        separatorBuilder: (_, __) => SizedBox(height: space.md),
        itemBuilder: (context, i) {
          if (i == 0) return const _BoardIntro();
          final pool = pools[i - 1];
          return PoolCard(
            pool: pool,
            capacity: controller.vehicleSeats,
            claiming: controller.isClaiming(pool.id),
            onClaim: controller.busy
                ? null
                : () => onClaim(controller, pool),
          );
        },
      ),
    );
  }
}

/// One line saying what these are, once, at the top.
class _BoardIntro extends StatelessWidget {
  const _BoardIntro();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: EdgeInsets.only(bottom: context.space.xs),
      child: Text(
        'ركّاب طلبوا مقاعد على هذه المسارات وجمعناهم. استلم التجمّع فيصير رحلتك.',
        style: context.text.caption.copyWith(color: colors.textSecondary),
      ),
    );
  }
}

/// A claimable pool, built to answer one question: **is this worth driving?**
///
/// The answer needs four things at a glance, and they are the four blocks
/// below: where and when, how full, what it pays, and whether the stops are
/// practical. Anything else would be decoration on a decision screen.
class PoolCard extends StatelessWidget {
  const PoolCard({
    super.key,
    required this.pool,
    required this.capacity,
    this.onClaim,
    this.claiming = false,
  });

  final BoardPool pool;

  /// The driver's own seat count — what "a full car" means here.
  final int capacity;

  final VoidCallback? onClaim;
  final bool claiming;

  @override
  Widget build(BuildContext context) {
    final space = context.space;
    final empty = pool.emptySeats(capacity);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RouteRail(
            variant: RouteRailVariant.compact,
            origin: _RailRow(
              city: pool.originCity,
              trailing: AppBadge(
                label: formatSeats(pool.totalSeats),
                tone: AppBadgeTone.info,
                icon: AppIcons.seat,
              ),
            ),
            destination: _RailRow(city: pool.destCity, trailing: null),
          ),
          SizedBox(height: space.md),

          // The WINDOW, never a single time: the pool's window is the
          // intersection of its riders', so any instant inside suits all of
          // them — and the driver is the one who picks.
          _MetaRow(
            icon: AppIcons.clock,
            text: '${formatDayShortBaghdad(pool.windowStart)} بين '
                '${formatTime(pool.windowStart)} و${formatTime(pool.windowEnd)}',
          ),
          SizedBox(height: space.xs),
          _MetaRow(
            icon: AppIcons.users,
            // «و» binds the two counts into one Arabic phrase; a dot-like
            // separator beside an Arabic-Indic digit reads as an extra zero.
            text: '${formatRiders(pool.riderCount)} و${formatSeats(pool.totalSeats)}'
                '${empty > 0 ? ' — يبقى ${formatSeats(empty)} للبيع' : ' — تملأ سيارتك'}',
          ),

          SizedBox(height: space.md),
          _TakeBlock(pool: pool, capacity: capacity),

          SizedBox(height: space.md),
          _StopsBlock(pool: pool),

          if (onClaim != null || claiming) ...[
            SizedBox(height: space.md),
            AppButton(
              label: 'استلم التجمّع',
              icon: AppIcons.check,
              loading: claiming,
              onPressed: onClaim,
            ),
          ],
        ],
      ),
    );
  }
}

/// What it pays now, and what it pays full.
///
/// Both, side by side, because they answer different questions: the first is
/// what the driver is being offered, the second is the ceiling they are driving
/// toward — and the gap between them is exactly what the raise flow later acts
/// on. Showing only one of them would make the offer look better or worse than
/// it is.
class _TakeBlock extends StatelessWidget {
  const _TakeBlock({required this.pool, required this.capacity});

  final BoardPool pool;
  final int capacity;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    final full = pool.fullCarFare(capacity);
    // When the pool already fills the car the two numbers are identical, and
    // printing «لك الآن ٢٤٬٠٠٠» above «لو امتلأت السيارة ٢٤٬٠٠٠» is a line that
    // asks the driver to compare a number with itself. The meta row above
    // already says «تملأ سيارتك».
    final showsCeiling = full > pool.estimatedFare;

    return Container(
      padding: EdgeInsets.all(space.md),
      decoration: BoxDecoration(
        // Opaque tonal — an alpha tint measures differently against the page
        // background than inside a card.
        color: colors.primaryTonal,
        borderRadius: context.radii.cardAll,
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('لك الآن', style: context.text.body),
              Text(
                formatPrice(pool.estimatedFare),
                style: context.text.title.tabular
                    .copyWith(color: colors.textPrimary),
              ),
            ],
          ),
          if (showsCeiling) ...[
            SizedBox(height: space.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'لو امتلأت السيارة',
                  style:
                      context.text.body.copyWith(color: colors.textSecondary),
                ),
                Text(
                  formatPrice(full),
                  style: context.text.bodyStrong.tabular
                      .copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ],
          SizedBox(height: space.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'سعر المقعد',
                style: context.text.caption.copyWith(color: colors.textMuted),
              ),
              Text(
                formatPrice(pool.pricePerSeat),
                style: context.text.caption.tabular
                    .copyWith(color: colors.textMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Where the riders are, and whether that is practical.
///
/// The driver is deciding whether the stops are worth the detour, so the card
/// shows the actual neighbourhood names plus **one honest measure of spread**.
/// It is not route optimisation — there is no order here and no suggested
/// path — it is the single fact a driver would otherwise have to work out by
/// opening each point on a map.
class _StopsBlock extends StatelessWidget {
  const _StopsBlock({required this.pool});

  final BoardPool pool;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    final spread = spreadOf(
      pool.pickupSpreadMetres,
      stopCount: pool.stops.length,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(AppIcons.mapPin, size: space.lg, color: colors.textMuted),
            SizedBox(width: space.sm),
            Expanded(
              child: Text(
                _spreadLabel(spread, pool.pickupSpreadMetres),
                style: context.text.caption.copyWith(color: colors.textSecondary),
              ),
            ),
          ],
        ),
        SizedBox(height: space.sm),
        for (final stop in pool.stops) ...[
          _StopRow(stop: stop),
          if (stop != pool.stops.last) SizedBox(height: space.xs),
        ],
      ],
    );
  }
}

/// The spread as a sentence. Distances are rounded to whole kilometres — a
/// driver deciding whether to take a job does not need metres, and a precise
/// number would imply a precision the straight-line measure does not have.
String _spreadLabel(StopSpread spread, double metres) => switch (spread) {
      StopSpread.single => 'نقطة صعود واحدة',
      StopSpread.tight => 'نقاط الصعود متقاربة',
      StopSpread.moderate =>
        'نقاط الصعود متباعدة نحو ${formatCount((metres / 1000).round())} كم',
      StopSpread.wide =>
        'نقاط الصعود متباعدة نحو ${formatCount((metres / 1000).round())} كم — تحقّق قبل الاستلام',
    };

class _StopRow extends StatelessWidget {
  const _StopRow({required this.stop});

  final PoolStop stop;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    final pickup = stop.pickup.label.trim();
    final dropoff = stop.dropoff.label.trim();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The seat count as a small chip, so a two-seat rider reads as one
        // group rather than as two lines.
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: space.sm,
            vertical: space.xs,
          ),
          decoration: BoxDecoration(
            color: colors.surfaceMuted,
            borderRadius: context.radii.chipAll,
          ),
          child: Text(
            formatCount(stop.seatCount),
            style: context.text.caption.tabular.copyWith(color: colors.textSecondary),
          ),
        ),
        SizedBox(width: space.sm),
        Expanded(
          child: Text(
            // The WORD «إلى» — the bundled Cairo has no arrow glyph, so an
            // «→» here ships a tofu box.
            '${pickup.isEmpty ? 'نقطة صعود' : pickup} إلى '
            '${dropoff.isEmpty ? 'نقطة نزول' : dropoff}',
            style: context.text.caption.copyWith(color: colors.textSecondary),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _RailRow extends StatelessWidget {
  const _RailRow({required this.city, required this.trailing});

  final String city;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            city.isEmpty ? 'مسار' : cityArName(city),
            style: context.text.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (trailing != null) ...[
          SizedBox(width: context.space.sm),
          trailing!,
        ],
      ],
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    return Row(
      children: [
        Icon(icon, size: space.lg, color: colors.textMuted),
        SizedBox(width: space.sm),
        Expanded(
          child: Text(
            text,
            style: context.text.body.copyWith(color: colors.textSecondary),
          ),
        ),
      ],
    );
  }
}

/// Nothing to claim right now.
///
/// It says what would make one appear rather than just reporting emptiness: a
/// driver who reads "لا توجد" and nothing else has no idea whether the feature
/// is broken or the morning is quiet.
class _BoardEmpty extends StatelessWidget {
  const _BoardEmpty({required this.onRefresh});

  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;

    return RefreshIndicator(
      color: colors.primary,
      onRefresh: onRefresh,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(space.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: space.xl4 + space.xl2,
                      height: space.xl4 + space.xl2,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: colors.primaryTonal,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(AppIcons.users,
                          color: colors.primary, size: space.xl2),
                    ),
                    SizedBox(height: space.lg),
                    Text('لا توجد تجمّعات جاهزة الآن',
                        style: context.text.title,
                        textAlign: TextAlign.center),
                    SizedBox(height: space.sm),
                    Text(
                      'التجمّع يظهر هنا عندما يطلب ركّاب مقاعد على نفس المسار '
                      'وفي أوقات متقاربة. يمكنك نشر رحلة الآن بدل الانتظار.',
                      style: context.text.body
                          .copyWith(color: colors.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BoardError extends StatelessWidget {
  const _BoardError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: space.xl4 + space.xl2,
              height: space.xl4 + space.xl2,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.dangerTonal,
                shape: BoxShape.circle,
              ),
              child: Icon(AppIcons.warning, color: colors.danger, size: space.xl2),
            ),
            SizedBox(height: space.lg),
            Text(message, style: context.text.title, textAlign: TextAlign.center),
            SizedBox(height: space.xl),
            AppButton(label: 'إعادة المحاولة', expand: false, onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}
