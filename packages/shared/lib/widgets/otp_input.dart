import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// A row of single-digit boxes for entering an OTP. Token-styled (mirrors the
/// design system's input styling), auto-advances on entry, and steps back on
/// backspace. Digits read left-to-right even on the RTL page.
class OtpInput extends StatefulWidget {
  const OtpInput({
    super.key,
    this.length = 6,
    required this.onChanged,
    this.onCompleted,
    this.hasError = false,
    this.enabled = true,
    this.autofocus = true,
  });

  final int length;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onCompleted;
  final bool hasError;
  final bool enabled;
  final bool autofocus;

  @override
  State<OtpInput> createState() => _OtpInputState();
}

class _OtpInputState extends State<OtpInput> {
  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(widget.length, (_) => TextEditingController());
    _focusNodes = List.generate(widget.length, (_) => FocusNode());
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  String get _code => _controllers.map((c) => c.text).join();

  void _handleChanged(int index, String value) {
    if (value.length > 1) {
      _distribute(value); // pasted / autofilled multi-digit
      return;
    }
    if (value.isNotEmpty && index < widget.length - 1) {
      _focusNodes[index + 1].requestFocus();
    }
    _emit();
  }

  void _distribute(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    for (var i = 0; i < widget.length; i++) {
      _controllers[i].text = i < digits.length ? digits[i] : '';
    }
    final next = digits.length.clamp(0, widget.length - 1);
    _focusNodes[next].requestFocus();
    _emit();
  }

  void _emit() {
    final code = _code;
    widget.onChanged(code);
    if (code.length == widget.length) {
      widget.onCompleted?.call(code);
    }
  }

  KeyEventResult _handleKey(int index, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _controllers[index].text.isEmpty &&
        index > 0) {
      _focusNodes[index - 1].requestFocus();
      _controllers[index - 1].clear();
      _emit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final radii = context.radii;
    final space = context.space;
    final cellWidth = space.xl4 + space.sm; // 48
    final cellHeight = space.xl4 + space.lg; // 56
    final borderColor = widget.hasError ? colors.danger : colors.border;

    OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
          borderRadius: radii.mdAll,
          borderSide: BorderSide(color: color, width: width),
        );

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < widget.length; i++)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: space.xs),
              child: SizedBox(
                width: cellWidth,
                height: cellHeight,
                child: Focus(
                  onKeyEvent: (_, event) => _handleKey(i, event),
                  child: TextField(
                    controller: _controllers[i],
                    focusNode: _focusNodes[i],
                    enabled: widget.enabled,
                    autofocus: widget.autofocus && i == 0,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    maxLength: 1,
                    style: context.text.h2.copyWith(color: colors.textPrimary),
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (v) => _handleChanged(i, v),
                    decoration: InputDecoration(
                      counterText: '',
                      filled: true,
                      fillColor: colors.surface,
                      contentPadding: EdgeInsets.zero,
                      enabledBorder: border(borderColor, 1),
                      focusedBorder: border(
                        widget.hasError ? colors.danger : colors.primary,
                        1.6,
                      ),
                      disabledBorder: border(colors.border, 1),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
