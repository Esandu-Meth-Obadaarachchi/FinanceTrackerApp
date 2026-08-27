import 'package:flutter/material.dart';

/// Layout breakpoints. Below [Breakpoints.wide] the app keeps its single-column
/// phone layout with a bottom nav; at or above it the shell switches to a
/// desktop layout with a side rail and multi-column content.
class Breakpoints {
  static const double wide = 900;
  static const double ultraWide = 1280;
}

extension ResponsiveContext on BuildContext {
  double get screenWidth => MediaQuery.sizeOf(this).width;
  bool get isWide => screenWidth >= Breakpoints.wide;
  bool get isUltraWide => screenWidth >= Breakpoints.ultraWide;

  /// Scroll padding for a top-level screen body. Mobile leaves room for the
  /// floating bottom nav; desktop has none to clear.
  EdgeInsets get pagePadding => isWide
      ? const EdgeInsets.fromLTRB(32, 28, 32, 48)
      : const EdgeInsets.fromLTRB(16, 12, 16, 110);
}

/// Scroll padding that centres a width-capped column inside a full-width list.
/// Widening the side padding keeps the list itself unwrapped, so the scrollbar
/// still hugs the window edge the way a web page's does.
EdgeInsets centredInsets(
  BuildContext context, {
  double maxWidth = 720,
  double minHorizontal = 16,
  double top = 14,
  double bottom = 32,
}) {
  final side = ((context.screenWidth - maxWidth) / 2)
      .clamp(minHorizontal, double.infinity)
      .toDouble();
  return EdgeInsets.fromLTRB(side, top, side, bottom);
}

/// Caps content width and centres it so text and cards stay readable on a
/// wide monitor instead of stretching edge to edge.
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child, this.maxWidth = 1120});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
