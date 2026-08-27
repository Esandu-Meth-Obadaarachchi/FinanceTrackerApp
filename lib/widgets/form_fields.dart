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
    this.onChanged,
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
  final ValueChanged<String>? onChanged;

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
          onChanged: onChanged,
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

/// A labelled single-line text field that suggests matching past entries.
///
/// Looks identical to [AppTextField] but shows a dropdown of [options] filtered
/// by what's typed (case-insensitive substring match). Selecting one fills the
/// shared [controller]. Falls back to a plain field when [options] is empty.
class AppAutocompleteField extends StatefulWidget {
  const AppAutocompleteField({
    super.key,
    required this.colors,
    required this.controller,
    required this.options,
    this.label,
    this.hint,
  });

  final Palette colors;
  final TextEditingController controller;
  final List<String> options;
  final String? label;
  final String? hint;

  @override
  State<AppAutocompleteField> createState() => _AppAutocompleteFieldState();
}

class _AppAutocompleteFieldState extends State<AppAutocompleteField> {
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  OutlineInputBorder _border(Color c) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c),
      );

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null) FieldLabel(widget.label!, colors: colors),
        RawAutocomplete<String>(
          textEditingController: widget.controller,
          focusNode: _focus,
          optionsBuilder: (value) {
            final q = value.text.trim().toLowerCase();
            if (q.isEmpty) return const Iterable<String>.empty();
            final matches = widget.options
                .where((o) => o.toLowerCase().contains(q) &&
                    o.toLowerCase() != q)
                .take(6);
            return matches;
          },
          onSelected: (selection) => widget.controller.text = selection,
          fieldViewBuilder:
              (context, textController, focusNode, onFieldSubmitted) {
            return TextField(
              controller: textController,
              focusNode: focusNode,
              onSubmitted: (_) => onFieldSubmitted(),
              style: sans(size: 14).copyWith(color: colors.text),
              cursorColor: const Color(0xFF3DEBA8),
              decoration: InputDecoration(
                isDense: true,
                hintText: widget.hint,
                hintStyle: sans(size: 14, color: colors.muted),
                filled: true,
                fillColor: colors.inputBg,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
                border: _border(colors.inputBorder),
                enabledBorder: _border(colors.inputBorder),
                focusedBorder: _border(const Color(0xFF3DEBA8)),
              ),
            );
          },
          optionsViewBuilder: (context, onSelected, options) {
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  margin: const EdgeInsets.only(top: 4),
                  constraints: const BoxConstraints(maxHeight: 220, maxWidth: 420),
                  decoration: BoxDecoration(
                    color: colors.card,
                    border: Border.all(color: colors.inputBorder),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: options.length,
                    itemBuilder: (context, i) {
                      final opt = options.elementAt(i);
                      return InkWell(
                        onTap: () => onSelected(opt),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 11),
                          child: Row(
                            children: [
                              Icon(Icons.history,
                                  size: 15, color: colors.muted),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Text(
                                  opt,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: sans(size: 14, color: colors.text),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
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

/// A large editable amount backed by a slider and percentage quick picks,
/// capped at [max]. Used wherever part of an outstanding balance is settled —
/// a loan payment, receiving part of a pending income.
///
/// Owns the value so the slider and the text field cannot fight over it, and
/// reports every change through [onChanged].
class AmountSlider extends StatefulWidget {
  const AmountSlider({
    super.key,
    required this.colors,
    required this.tone,
    required this.max,
    required this.onChanged,
    this.label = 'AMOUNT (LKR)',
  });

  final Palette colors;
  final Color tone;

  /// Upper bound — what is still outstanding. The value starts here.
  final double max;
  final ValueChanged<double> onChanged;
  final String label;

  @override
  State<AmountSlider> createState() => _AmountSliderState();
}

class _AmountSliderState extends State<AmountSlider> {
  final _controller = TextEditingController();
  double _value = 0;

  @override
  void initState() {
    super.initState();
    _value = widget.max;
    _controller.text = _plain(_value);
  }

  @override
  void didUpdateWidget(AmountSlider old) {
    super.didUpdateWidget(old);
    // The outstanding figure can move under us (a stream update); keep the
    // value inside the new bound without stomping on what the user typed.
    if (widget.max != old.max && _value > widget.max) {
      _set(widget.max);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Plain digits for the editable field — no grouping, so it re-parses.
  static String _plain(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(2);

  void _set(double v, {bool syncText = true}) {
    final clamped = v.clamp(0, widget.max).toDouble();
    setState(() => _value = clamped);
    if (syncText) _controller.text = _plain(clamped);
    widget.onChanged(clamped);
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final tone = widget.tone;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: colors.inputBg,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Text(widget.label,
                  style: sans(
                      size: 12,
                      weight: FontWeight.w600,
                      color: colors.sub,
                      letterSpacing: 0.6)),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Rs ', style: mono(size: 22, color: colors.sub)),
                  IntrinsicWidth(
                    child: TextField(
                      controller: _controller,
                      textAlign: TextAlign.center,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [amountFormatter],
                      style:
                          mono(size: 36, weight: FontWeight.w700, color: tone),
                      cursorColor: tone,
                      // Typed edits move the slider but leave the field alone,
                      // so the caret stays where the user put it.
                      onChanged: (raw) => _set(
                          double.tryParse(raw.trim()) ?? 0,
                          syncText: false),
                      decoration: InputDecoration(
                        isCollapsed: true,
                        border: InputBorder.none,
                        hintText: '0',
                        hintStyle: mono(
                            size: 36,
                            weight: FontWeight.w700,
                            color: colors.muted),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        if (widget.max > 0)
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: tone,
              inactiveTrackColor: colors.elevated,
              thumbColor: tone,
              overlayColor: tone.withValues(alpha: 0.14),
              trackHeight: 5,
            ),
            child: Slider(
              value: _value.clamp(0, widget.max).toDouble(),
              max: widget.max,
              onChanged: (v) => _set(v.roundToDouble()),
            ),
          ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (final (label, fraction) in const [
              ('25%', 0.25),
              ('50%', 0.5),
              ('75%', 0.75),
              ('All', 1.0),
            ])
              Expanded(
                child: GestureDetector(
                  onTap: () => _set((widget.max * fraction).roundToDouble()),
                  child: Container(
                    margin: EdgeInsets.only(right: fraction == 1.0 ? 0 : 8),
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: tone.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Text(label,
                          style: sans(
                              size: 12.5,
                              weight: FontWeight.w600,
                              color: tone)),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
