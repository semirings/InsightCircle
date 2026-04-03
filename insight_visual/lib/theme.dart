import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ── Academic Brutalism Palette ─────────────────────────────────────────────
// Source: InsightCircle HTML / Tailwind config
const kBlack               = Color(0xFF000000);
const kRed700              = Color(0xFFB91C1C); // Tailwind red-700 / secondary
const kBackground          = Color(0xFFF9F9F9);
const kSidebarBg           = Color(0xFFFFFDE7); // Manila yellow
const kSurface             = Color(0xFFFFFFFF);
const kSurfaceContainerLow = Color(0xFFF3F3F3);
const kOnSurface           = Color(0xFF1B1B1B);
const kGray100             = Color(0xFFF3F4F6);
const kGray200             = Color(0xFFE5E7EB);
const kGray300             = Color(0xFFD1D5DB);
const kGray400             = Color(0xFF9CA3AF);
const kGray500             = Color(0xFF6B7280);
const kGray600             = Color(0xFF4B5563);

ThemeData buildTheme() {
  final base = ThemeData.light(useMaterial3: true);
  return base.copyWith(
    colorScheme: const ColorScheme.light(
      primary: kBlack,
      onPrimary: kSurface,
      secondary: kRed700,
      onSecondary: kSurface,
      surface: kSurface,
      onSurface: kOnSurface,
    ),
    scaffoldBackgroundColor: kBackground,
    textTheme: GoogleFonts.interTextTheme(base.textTheme),
  );
}

// ── Font helpers ───────────────────────────────────────────────────────────

TextStyle spaceGrotesk({
  double fontSize = 14,
  FontWeight fontWeight = FontWeight.w700,
  Color color = kOnSurface,
  double letterSpacing = 0,
}) =>
    GoogleFonts.spaceGrotesk(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
    );

TextStyle inter({
  double fontSize = 14,
  FontWeight fontWeight = FontWeight.w400,
  Color color = kOnSurface,
  double letterSpacing = 0,
  double? height,
}) =>
    GoogleFonts.inter(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );
