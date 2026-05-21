import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Typography helpers — DM Sans for text, DM Mono for figures.
TextStyle sans({
  double size = 14,
  FontWeight weight = FontWeight.w500,
  Color? color,
  double? letterSpacing,
  double? height,
}) =>
    GoogleFonts.dmSans(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );

TextStyle mono({
  double size = 14,
  FontWeight weight = FontWeight.w600,
  Color? color,
  double? letterSpacing,
}) =>
    GoogleFonts.dmMono(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing,
    );

/// Uppercase section label style ("ACCOUNTS", "INCOME"…).
TextStyle label(Color color, {double size = 12}) => GoogleFonts.dmSans(
      fontSize: size,
      fontWeight: FontWeight.w600,
      color: color,
      letterSpacing: 0.6,
    );
