import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/app_avatar.dart';
import '../widgets/app_button.dart';
import '../widgets/app_icons.dart';
import '../widgets/app_text_field.dart';
import '../widgets/rating_stars.dart';

/// Show the rate-a-person sheet. [onSubmit] performs the `POST /ratings` call
/// and returns null on success or a ready-to-show Arabic error; on success the
/// sheet dismisses itself.
///
/// ONE implementation for both directions. It started as the driver's
/// `rate_rider_sheet.dart`, and when the rider gained a rating path the choice
/// was to copy it or to lift it — the same choice the onboarding screens faced,
/// with the same answer (CLAUDE.md → the shared onboarding note). A duplicated
/// sheet means every fix has to be applied twice, and a fix that lands in only
/// one is invisible until it bites.
///
/// Only the words differ, so only the words are parameters.
Future<void> showRateSheet(
  BuildContext context, {
  required String title,
  required String name,
  required String commentHint,
  required Future<String?> Function(int score, String? comment) onSubmit,
}) {
  final colors = context.colors;
  final radii = context.radii;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: colors.surface,
    shape: RoundedRectangleBorder(borderRadius: radii.sheetTop),
    builder: (_) => RateSheet(
      title: title,
      name: name,
      commentHint: commentHint,
      onSubmit: onSubmit,
    ),
  );
}

/// The rate sheet body (public so golden tests can render it directly).
class RateSheet extends StatefulWidget {
  const RateSheet({
    super.key,
    required this.title,
    required this.name,
    required this.commentHint,
    required this.onSubmit,
  });

  /// The small line above the name — «قيّم الراكب» or «قيّم السائق».
  final String title;

  /// Who is being rated.
  final String name;

  /// Placeholder for the optional comment field.
  final String commentHint;

  final Future<String?> Function(int score, String? comment) onSubmit;

  @override
  State<RateSheet> createState() => _RateSheetState();
}

class _RateSheetState extends State<RateSheet> {
  final _comment = TextEditingController();
  int _score = 0;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_score < 1 || _submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final err = await widget.onSubmit(_score, _comment.text);
    if (!mounted) return;
    if (err == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _submitting = false;
      _error = err;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;

    return Padding(
      // Lift above the keyboard when the comment field is focused.
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.all(space.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: space.xl2,
                  height: space.xs,
                  decoration: BoxDecoration(
                    color: colors.border,
                    borderRadius: context.radii.pillAll,
                  ),
                ),
              ),
              SizedBox(height: space.lg),
              Row(
                children: [
                  AppAvatar(name: widget.name, size: space.xl2),
                  SizedBox(width: space.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.title,
                            style: context.text.caption
                                .copyWith(color: colors.textMuted)),
                        Text(widget.name,
                            style: context.text.title
                                .copyWith(color: colors.textPrimary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: space.lg),
              Center(
                child: RatingStars(
                  value: _score.toDouble(),
                  size: space.xl2,
                  onRate:
                      _submitting ? null : (v) => setState(() => _score = v),
                ),
              ),
              SizedBox(height: space.lg),
              AppTextField(
                label: 'تعليق (اختياري)',
                hint: widget.commentHint,
                controller: _comment,
                enabled: !_submitting,
                maxLength: 500,
                keyboardType: TextInputType.multiline,
              ),
              if (_error != null) ...[
                SizedBox(height: space.sm),
                Text(_error!,
                    style: context.text.caption.copyWith(color: colors.danger)),
              ],
              SizedBox(height: space.lg),
              AppButton(
                label: 'إرسال التقييم',
                icon: AppIcons.star,
                loading: _submitting,
                // Disabled until a star is picked: a rating with no score is
                // the one thing this sheet cannot send.
                onPressed: _score < 1 ? null : _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
