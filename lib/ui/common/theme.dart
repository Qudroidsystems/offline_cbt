import 'package:flutter/material.dart';

// Apple-style palette — same tokens as the web portal's Apple theme (portal-theme.css).
const appleBlue = Color(0xFF007AFF);
const label = Color(0xFF1D1D1F); // primary text
const label2 = Color(0x9E3C3C43); // secondary text  rgba(60,60,67,.62)
const groupBg = Color(0xFFF2F2F7); // page background
const fill = Color(0x1F787880); // input / control fill rgba(120,120,128,.12)
const separator = Color(0x293C3C43); // hairlines rgba(60,60,67,.16)

// Names used across the app (kept so every screen follows the new palette).
const navy = label;
const teal = appleBlue;
const okGreen = Color(0xFF34C759);
const warnAmber = Color(0xFFFF9500);
const badRed = Color(0xFFFF3B30);

// Brand colours (splash screen, app icon).
const brandNavy = Color(0xFF1E3A5F);
const brandTeal = Color(0xFF0F766E);

const _fonts = ['Segoe UI Variable Text', 'Segoe UI', 'SF Pro Text', 'Helvetica Neue', 'Arial'];

/// Soft Apple-style card shadow.
const appleShadow = [
  BoxShadow(color: Color(0x0A000000), blurRadius: 2, offset: Offset(0, 1)),
  BoxShadow(color: Color(0x0D000000), blurRadius: 16, offset: Offset(0, 4)),
];

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: appleBlue, primary: appleBlue, secondary: label, surface: Colors.white, error: badRed);
  final base = ThemeData(colorScheme: scheme, useMaterial3: true, fontFamily: _fonts.first, fontFamilyFallback: _fonts.skip(1).toList());
  const radius12 = BorderRadius.all(Radius.circular(12));
  return base.copyWith(
    scaffoldBackgroundColor: groupBg,
    textTheme: base.textTheme.apply(bodyColor: label, displayColor: label),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xF7FBFBFD),
      foregroundColor: label,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(color: label, fontSize: 17, fontWeight: FontWeight.w600, fontFamily: 'Segoe UI Variable Text'),
      shape: Border(bottom: BorderSide(color: separator, width: 0.5)),
    ),
    cardTheme: const CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16)), side: BorderSide(color: Color(0x0F000000))),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: Color(0xFFF2F2F5),
      isDense: true,
      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: radius12, borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: radius12, borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: radius12, borderSide: BorderSide(color: appleBlue, width: 1.6)),
      errorBorder: OutlineInputBorder(borderRadius: radius12, borderSide: BorderSide(color: badRed, width: 1.2)),
      labelStyle: TextStyle(color: label2),
      hintStyle: TextStyle(color: label2),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: appleBlue,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: appleBlue,
        shape: const StadiumBorder(),
        side: const BorderSide(color: separator),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: appleBlue, shape: const StadiumBorder())),
    switchTheme: SwitchThemeData(
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? okGreen : const Color(0xFFE9E9EB)),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? appleBlue : Colors.transparent),
    ),
    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: Color(0xFFF7F7FA),
      indicatorColor: Color(0x1F007AFF),
      selectedIconTheme: IconThemeData(color: appleBlue),
      unselectedIconTheme: IconThemeData(color: label2),
      selectedLabelTextStyle: TextStyle(color: appleBlue, fontWeight: FontWeight.w600, fontSize: 12),
      unselectedLabelTextStyle: TextStyle(color: label2, fontSize: 12),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(18))),
      titleTextStyle: TextStyle(color: label, fontSize: 18, fontWeight: FontWeight.w700, fontFamily: 'Segoe UI Variable Text'),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: Color(0xF21D1D1F),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
    ),
    chipTheme: const ChipThemeData(
      backgroundColor: Color(0xFFF2F2F5),
      side: BorderSide.none,
      shape: StadiumBorder(),
      labelStyle: TextStyle(color: label, fontSize: 12, fontWeight: FontWeight.w500),
    ),
    dividerTheme: const DividerThemeData(color: separator, thickness: 0.5, space: 0.5),
    listTileTheme: const ListTileThemeData(iconColor: label2),
    dataTableTheme: const DataTableThemeData(
      headingTextStyle: TextStyle(color: label2, fontSize: 12, fontWeight: FontWeight.w600),
      dividerThickness: 0.5,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: appleBlue, linearTrackColor: Color(0xFFE5E5EA)),
    popupMenuTheme: const PopupMenuThemeData(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
    ),
  );
}
