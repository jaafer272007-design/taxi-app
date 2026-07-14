import 'package:flutter/material.dart';
import 'package:shared/shared.dart';

/// Show the rate-a-rider sheet. [onSubmit] performs the POST /ratings call and
/// returns null on success or a ready-to-show Arabic error; on success the sheet
/// dismisses itself.
Future<void> showRateRiderSheet(
  BuildContext context, {
  required String riderName,
  required Future<String?> Function(int score, String? comment) onSubmit,
}) {
  final colors = context.colors;
  final radii = context.radii;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: colors.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(radii.lg)),
    ),
    builder: (_) => RateRiderSheet(riderName: riderName, onSubmit: onSubmit),
  );
}

/// The rate-a-rider sheet body (public so golden tests can render it directly).
class RateRiderSheet extends StatefulWidget {
  const RateRiderSheet({
    super.key,
    required this.riderName,
    required this.onSubmit,
  });

  final String riderName;
  final Future<String?> Function(int score, String? comment) onSubmit;

  @override
  State<RateRiderSheet> createState() => _RateRiderSheetState();
}

class _RateRiderSheetState extends State<RateRiderSheet> {
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
                  AppAvatar(name: widget.riderName, size: space.xl2),
                  SizedBox(width: space.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('قيّم الراكب',
                            style: context.text.caption
                                .copyWith(color: colors.textMuted)),
                        Text(widget.riderName,
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
                  onRate: _submitting
                      ? null
                      : (v) => setState(() => _score = v),
                ),
              ),
              SizedBox(height: space.lg),
              AppTextField(
                label: 'تعليق (اختياري)',
                hint: 'كيف كانت الرحلة مع هذا الراكب؟',
                controller: _comment,
                enabled: !_submitting,
                maxLength: 500,
                keyboardType: TextInputType.multiline,
              ),
              if (_error != null) ...[
                SizedBox(height: space.sm),
                Text(_error!,
                    style:
                        context.text.caption.copyWith(color: colors.danger)),
              ],
              SizedBox(height: space.lg),
              AppButton(
                label: 'إرسال التقييم',
                icon: AppIcons.star,
                loading: _submitting,
                onPressed: _score < 1 ? null : _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
