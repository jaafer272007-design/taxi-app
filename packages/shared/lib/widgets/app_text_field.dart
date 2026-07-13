import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// The standard labelled text field: label above, input with token styling,
/// and a helper/error line below. Error state recolors the border and message.
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    this.label,
    this.hint,
    this.helper,
    this.error,
    this.controller,
    this.keyboardType,
    this.obscureText = false,
    this.prefixIcon,
    this.suffixIcon,
    this.onChanged,
    this.onSubmitted,
    this.inputFormatters,
    this.enabled = true,
    this.maxLength,
    this.textInputAction,
    this.autofocus = false,
  });

  final String? label;
  final String? hint;
  final String? helper;

  /// When non-null, the field renders in its error state.
  final String? error;

  final TextEditingController? controller;
  final TextInputType? keyboardType;
  final bool obscureText;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final List<TextInputFormatter>? inputFormatters;
  final bool enabled;
  final int? maxLength;
  final TextInputAction? textInputAction;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final radii = context.radii;
    final space = context.space;
    final hasError = error != null && error!.isNotEmpty;

    OutlineInputBorder borderOf(Color color, double width) => OutlineInputBorder(
          borderRadius: radii.mdAll,
          borderSide: BorderSide(color: color, width: width),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          Text(label!, style: context.text.label.copyWith(color: colors.textSecondary)),
          SizedBox(height: space.sm),
        ],
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          obscureText: obscureText,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          inputFormatters: inputFormatters,
          enabled: enabled,
          maxLength: maxLength,
          textInputAction: textInputAction,
          autofocus: autofocus,
          style: context.text.body.copyWith(color: colors.textPrimary),
          cursorColor: colors.primary,
          decoration: InputDecoration(
            isDense: true,
            counterText: '',
            filled: true,
            fillColor: enabled ? colors.surface : colors.surfaceMuted,
            hintText: hint,
            hintStyle: context.text.body.copyWith(color: colors.textMuted),
            contentPadding: EdgeInsets.symmetric(
              horizontal: space.lg,
              vertical: space.md,
            ),
            prefixIcon: prefixIcon == null
                ? null
                : Icon(prefixIcon, size: 20, color: colors.textMuted),
            suffixIcon: suffixIcon,
            enabledBorder: borderOf(hasError ? colors.danger : colors.border, 1),
            focusedBorder:
                borderOf(hasError ? colors.danger : colors.primary, 1.6),
            disabledBorder: borderOf(colors.border, 1),
            errorBorder: borderOf(colors.danger, 1),
            focusedErrorBorder: borderOf(colors.danger, 1.6),
          ),
        ),
        if (hasError) ...[
          SizedBox(height: space.xs),
          Text(error!, style: context.text.caption.copyWith(color: colors.danger)),
        ] else if (helper != null) ...[
          SizedBox(height: space.xs),
          Text(helper!,
              style: context.text.caption.copyWith(color: colors.textMuted)),
        ],
      ],
    );
  }
}
