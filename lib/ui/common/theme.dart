import 'package:flutter/material.dart';

const navy = Color(0xFF1E3A5F);
const teal = Color(0xFF0F766E);
const okGreen = Color(0xFF16A34A);
const warnAmber = Color(0xFFD97706);
const badRed = Color(0xFFDC2626);

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: teal, primary: teal, secondary: navy);
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: const Color(0xFFF5F7FA),
    appBarTheme: const AppBarTheme(backgroundColor: navy, foregroundColor: Colors.white, elevation: 0),
    cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(14)), side: BorderSide(color: Color(0xFFE2E8F0)))),
    inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder(), isDense: true),
    filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16))),
  );
}
