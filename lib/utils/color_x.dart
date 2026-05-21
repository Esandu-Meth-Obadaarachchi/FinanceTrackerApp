import 'package:flutter/material.dart';

/// Hex helpers so colours can be stored as readable strings in Firestore.
extension HexColor on Color {
  String toHex() {
    final argb = toARGB32();
    return '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }
}

Color colorFromHex(String? hex, {Color fallback = const Color(0xFF3DEBA8)}) {
  if (hex == null || hex.isEmpty) return fallback;
  var h = hex.replaceAll('#', '').trim();
  if (h.length == 6) h = 'FF$h';
  final value = int.tryParse(h, radix: 16);
  return value == null ? fallback : Color(value);
}
