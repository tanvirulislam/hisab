import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Large amount input. Accepts Latin and Bangla digits, commas and one
/// decimal point. Parsing into paisa happens with `Money.tryParse`.
class AmountField extends StatelessWidget {
  const AmountField({
    super.key,
    required this.controller,
    this.autofocus = false,
    this.errorText,
    this.label,
    this.onSubmitted,
    this.large = true,
  });

  final TextEditingController controller;
  final bool autofocus;
  final String? errorText;
  final String? label;
  final ValueChanged<String>? onSubmitted;
  final bool large;

  static final _allowed = FilteringTextInputFormatter.allow(RegExp(r'[0-9০-৯.,]'));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = large
        ? theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w700)
        : theme.textTheme.titleLarge;
    return TextField(
      controller: controller,
      autofocus: autofocus,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: TextInputAction.done,
      inputFormatters: [_allowed, LengthLimitingTextInputFormatter(16)],
      style: style,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: label,
        hintText: '0',
        errorText: errorText,
        prefixText: '৳ ',
        prefixStyle: style?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        border: large ? InputBorder.none : const OutlineInputBorder(),
      ),
    );
  }
}
