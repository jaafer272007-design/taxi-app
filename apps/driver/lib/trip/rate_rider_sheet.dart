import 'package:flutter/material.dart';
import 'package:shared/shared.dart';

/// Rate a rider. The sheet itself is [RateSheet] in `packages/shared` — this is
/// the driver-side copy for it, and nothing more.
Future<void> showRateRiderSheet(
  BuildContext context, {
  required String riderName,
  required Future<String?> Function(int score, String? comment) onSubmit,
}) =>
    showRateSheet(
      context,
      title: 'قيّم الراكب',
      name: riderName,
      commentHint: 'كيف كانت الرحلة مع هذا الراكب؟',
      onSubmit: onSubmit,
    );
