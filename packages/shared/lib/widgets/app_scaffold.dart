import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A themed [Scaffold] wrapper: token background, an optional titled app bar,
/// safe-area handling, and consistent horizontal content padding. RTL is
/// inherited from the app's [Directionality] (set to RTL at the root).
class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    required this.body,
    this.title,
    this.actions,
    this.leading,
    this.bottomBar,
    this.floatingActionButton,
    this.padded = true,
    this.scrollable = false,
    this.backgroundColor,
  });

  final Widget body;
  final String? title;
  final List<Widget>? actions;
  final Widget? leading;

  /// Pinned bottom bar (e.g. a primary action), kept above the safe area.
  final Widget? bottomBar;
  final Widget? floatingActionButton;

  /// Apply the standard horizontal content padding.
  final bool padded;

  /// Wrap [body] in a scroll view.
  final bool scrollable;

  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;

    Widget content = body;
    if (padded) {
      content = Padding(
        padding: EdgeInsets.symmetric(horizontal: space.lg),
        child: content,
      );
    }
    if (scrollable) {
      content = SingleChildScrollView(
        padding: EdgeInsets.symmetric(vertical: space.lg),
        child: content,
      );
    }

    return Scaffold(
      backgroundColor: backgroundColor ?? colors.background,
      appBar: title == null
          ? null
          : AppBar(
              title: Text(title!),
              actions: actions,
              leading: leading,
            ),
      body: SafeArea(
        top: title == null,
        child: content,
      ),
      bottomNavigationBar: switch (bottomBar) {
        null => null,
        // Shrink-wrap vertically: the Scaffold hands the bottom slot a maxHeight
        // of the whole screen, and an expand:true AppButton (whose inner
        // Container is center-aligned) would otherwise fill that entire height.
        // MainAxisSize.min gives the bar unbounded height so it takes only its
        // natural height and sits pinned at the bottom.
        final Widget bar => SafeArea(
            minimum: EdgeInsets.all(space.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [bar],
            ),
          ),
      },
      floatingActionButton: floatingActionButton,
    );
  }
}
