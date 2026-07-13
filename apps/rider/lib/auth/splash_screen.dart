import 'package:flutter/material.dart';
import 'package:shared/shared.dart';

/// Shown while the session is being restored on launch.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    return AppScaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(AppIcons.car, size: space.xl4 + space.md, color: colors.primary),
            SizedBox(height: space.xl),
            SizedBox(
              width: space.xl2,
              height: space.xl2,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
