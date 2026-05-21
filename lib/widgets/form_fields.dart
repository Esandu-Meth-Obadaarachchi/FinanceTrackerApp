import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_text.dart';
import '../theme/palette.dart';

/// Uppercase field label.
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key, required this.colors, this.trailing});
  final String text;
  final Palette colors;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text(
            text.toUpperCase(),
            style: sans(
              size: 12,
              weight: FontWeight.w600,
              color: colors.sub,
              letterSpacing: 0.6,
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 6), trailing!],
        ],
      ),
    );
  }
}

/// A labelled single-line text field.
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.colors,
    required this.controller,
    this.label,
    this.hint,
    this.prefix,
    this.keyboardType,
    this.autofocus = false,
    this.obscure = false,
    this.onSubmitted,
  });

  final Palette colors;
  final TextEditingController controller;
  final String? label;
  final String? hint;
  final String? prefix;
  final TextInputType? keyboardType;
  final bool autofocus;
  final bool obscure;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final isNumber = keyboardType == TextInputType.number;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) FieldLabel(label!, colors: colors),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          autofocus: autofocus,
          obscureText: obscure,
          onSubmitted: onSubmitted,
          style: (isNumber ? mono(size: 14) : sans(size: 14))
              .copyWith(color: colors.text),
          cursorColor: const Color(0xFF3DEBA8),
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            hintStyle: sans(size: 14, color: colors.muted),
            prefixText: prefix != null ? '$prefix  ' : null,
            prefixStyle: mono(size: 13, color: colors.muted),
            filled: true,
            fillColor: colors.inputBg,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
            border: _border(colors.inputBorder),
            enabledBorder: _border(colors.inputBorder),
            focusedBorder: _border(const Color(0xFF3DEBA8)),
          ),
        ),
      ],
    );
  }

  OutlineInputBorder _border(Color c) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c),
      );
}

/// A labelled dropdown.
class AppDropdown<T> extends StatelessWidget {
  const AppDropdown({
    super.key,
    required this.colors,
    required this.value,
    required this.items,
    required this.onChanged,
    this.label,
  });

  final Palette colors;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) FieldLabel(label!, colors: colors),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: colors.inputBg,
            border: Border.all(color: colors.inputBorder),
            borderRadius: BorderRadius.circular(12),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isExpanded: true,
              dropdownColor: colors.card,
              icon: Icon(Icons.keyboard_arrow_down, color: colors.sub),
              style: sans(size: 14, color: colors.text),
              items: items,
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

/// Tabbed segmented control.
class SegmentedControl<T> extends StatelessWidget {
  const SegmentedControl({
    super.key,
    required this.colors,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final Palette colors;
  final T value;
  final List<({T value, String label})> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: colors.isDark ? const Color(0xFF1A2030) : const Color(0xFFEEF2FA),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          for (final opt in options)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(opt.value),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  decoration: BoxDecoration(
                    color: value == opt.value
                        ? (colors.isDark
                            ? const Color(0xFF232B3E)
                            : Colors.white)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: value == opt.value
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    opt.label,
                    textAlign: TextAlign.center,
                    style: sans(
                      size: 13,
                      weight: value == opt.value
                          ? FontWeight.w600
                          : FontWeight.w500,
                      color: value == opt.value
                          ? colors.text
                          : (colors.isDark
                              ? const Color(0xFF4A5270)
                              : const Color(0xFF7A85A0)),
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

/// Rounded search input.
class SearchField extends StatelessWidget {
  const SearchField({
    super.key,
    required this.colors,
    required this.controller,
    required this.onChanged,
    this.hint = 'Search…',
  });

  final Palette colors;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: sans(size: 14, color: colors.text),
      cursorColor: const Color(0xFF3DEBA8),
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: sans(size: 14, color: colors.muted),
        prefixIcon: Icon(Icons.search, size: 18, color: colors.muted),
        filled: true,
        fillColor: colors.inputBg,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: _b(colors.inputBorder),
        enabledBorder: _b(colors.inputBorder),
        focusedBorder: _b(const Color(0xFF3DEBA8)),
      ),
    );
  }

  OutlineInputBorder _b(Color c) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c),
      );
}

/// Full-width solid action button.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.color = const Color(0xFF3DEBA8),
    this.gradient,
    this.icon,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color color;
  final Gradient? gradient;
  final IconData? icon;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: busy ? null : onPressed,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          color: gradient == null ? color : null,
          gradient: gradient,
          borderRadius: BorderRadius.circular(14),
        ),
        child: busy
            ? const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.4, color: Color(0xFF0B0D14)),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 19, color: const Color(0xFF0B0D14)),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    label,
                    style: sans(
                      size: 16,
                      weight: FontWeight.w700,
                      color: const Color(0xFF0B0D14),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Number-only text input formatter allowing one decimal point.
final amountFormatter = FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'));
