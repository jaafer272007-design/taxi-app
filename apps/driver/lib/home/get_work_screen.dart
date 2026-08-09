import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import '../pool/pool_board_controller.dart';
import '../pool/pool_board_screen.dart';
import '../trip/post_trip_screen.dart';

/// «العمل» — the two ways a driver gets work, on one surface.
///
/// Phase 1: announce a trip and wait for riders to find it. Phase 2: take a
/// group of riders who have already asked. They are alternatives for the same
/// intent — *how do I fill this morning?* — so the driver should be able to
/// compare them without navigating, and should never have to remember that the
/// other one exists.
///
/// ## Why a segmented control and not a sixth tab
///
/// [FloatingPillNav] asserts a maximum of five destinations and the driver
/// already has five. That constraint forced the question, and the answer turned
/// out to be the better model anyway: a nav tab says "a different place", while
/// these two are one place with two ways in. The tab badge carries the board's
/// size, so a driver who has never opened it still learns pools exist — and
/// that there are some right now — without being sent a nudge.
class GetWorkScreen extends StatefulWidget {
  const GetWorkScreen({super.key, required this.onWorkStarted});

  /// Called once the driver has work — a trip posted, or a pool claimed. The
  /// shell switches to رحلاتي, because that is where the thing now lives, and
  /// both paths end in exactly the same place.
  final VoidCallback onWorkStarted;

  @override
  State<GetWorkScreen> createState() => _GetWorkScreenState();
}

enum WorkMode { post, board }

class _GetWorkScreenState extends State<GetWorkScreen> {
  WorkMode _mode = WorkMode.post;

  @override
  Widget build(BuildContext context) {
    final board = context.watch<PoolBoardController>();
    final header = _ModeBar(
      mode: _mode,
      poolCount: board.count,
      onChanged: (m) => setState(() => _mode = m),
    );

    // IndexedStack, not a switch: flipping back to «انشر رحلة» must not throw
    // away a half-filled form, and flipping to the board must not re-fetch it.
    return IndexedStack(
      index: _mode.index,
      children: [
        TickerMode(
          enabled: _mode == WorkMode.post,
          child: PostTripScreen(
            onPosted: widget.onWorkStarted,
            header: header,
          ),
        ),
        TickerMode(
          // The board polls; the form does not. Gating on the selected MODE as
          // well as the selected TAB is what stops it ticking while the driver
          // is filling in a trip on the other half of this same screen.
          enabled: _mode == WorkMode.board,
          child: PoolBoardScreen(
            onClaimed: (_) => widget.onWorkStarted(),
            header: header,
          ),
        ),
      ],
    );
  }
}

/// The mode selector, identical in both modes so it never appears to move.
class _ModeBar extends StatelessWidget {
  const _ModeBar({
    required this.mode,
    required this.poolCount,
    required this.onChanged,
  });

  final WorkMode mode;
  final int poolCount;
  final ValueChanged<WorkMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return AppSegmentedControl<WorkMode>(
      value: mode,
      onChanged: onChanged,
      segments: [
        const AppSegment(
          value: WorkMode.post,
          label: 'انشر رحلة',
          icon: AppIcons.plusCircle,
        ),
        AppSegment(
          value: WorkMode.board,
          // The count rides in the label so an unopened board still advertises
          // itself. «التجمّعات ٣» — a word then a digit, with no separator
          // between them: a dot-like glyph beside an Arabic-Indic numeral reads
          // as an extra ٠.
          label: poolCount > 0 ? 'التجمّعات ${formatCount(poolCount)}' : 'التجمّعات',
          icon: AppIcons.users,
        ),
      ],
    );
  }
}
