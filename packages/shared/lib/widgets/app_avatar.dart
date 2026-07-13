import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A circular avatar showing the initials derived from a name. No network
/// images in Phase 1 — initials on a tinted primary fill.
class AppAvatar extends StatelessWidget {
  const AppAvatar({
    super.key,
    required this.name,
    this.size = 40,
  });

  final String name;
  final double size;

  String get _initials {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '؟';
    if (parts.length == 1) {
      final p = parts.first;
      return p.characters.take(2).toString();
    }
    return (parts.first.characters.take(1).toString() +
        parts.last.characters.take(1).toString());
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      // Scale the token text style to the avatar rather than hardcoding a size:
      // the initials fill ~40% of the diameter at any size.
      child: FractionallySizedBox(
        widthFactor: 0.5,
        heightFactor: 0.5,
        child: FittedBox(
          fit: BoxFit.contain,
          child: Text(
            _initials,
            style: context.text.label.copyWith(
              color: colors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
