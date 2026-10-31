import 'package:flutter/material.dart';

const Color kAccent = Color(0xFF4CAF50);

ThemeData _build(Brightness b) {
  final scheme = ColorScheme.fromSeed(seedColor: kAccent, brightness: b);
  // Apple-style controls: capsules without outlines, on a soft fill, and no
  // Material ripple.
  final softFill = scheme.onSurface.withValues(alpha: 0.1);
  Color onChip(Set<WidgetState> s) =>
      s.contains(WidgetState.selected) ? scheme.onPrimary : scheme.onSurface;
  const buttonSize = Size(64, 44);
  const buttonPadding = EdgeInsets.symmetric(horizontal: 20);
  const buttonText = TextStyle(fontSize: 15, fontWeight: FontWeight.w600);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: b == Brightness.dark
        ? const Color(0xFF101410)
        : null,
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
    ),
    chipTheme: ChipThemeData(
      shape: const StadiumBorder(),
      side: BorderSide.none,
      backgroundColor: softFill,
      selectedColor: scheme.primary,
      showCheckmark: false,
      elevation: 0,
      pressElevation: 0,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      labelPadding: const EdgeInsets.only(left: 2, right: 6),
      labelStyle: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: WidgetStateColor.resolveWith(onChip),
      ),
      iconTheme: IconThemeData(size: 18, color: scheme.onSurface),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: const StadiumBorder(),
        minimumSize: buttonSize,
        padding: buttonPadding,
        textStyle: buttonText,
        splashFactory: NoSplash.splashFactory,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: const StadiumBorder(),
        side: BorderSide.none,
        backgroundColor: softFill,
        minimumSize: buttonSize,
        padding: buttonPadding,
        textStyle: buttonText,
        splashFactory: NoSplash.splashFactory,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: const StadiumBorder(),
        textStyle: buttonText,
        splashFactory: NoSplash.splashFactory,
      ),
    ),
  );
}

final ThemeData darkTheme = _build(Brightness.dark);
final ThemeData lightTheme = _build(Brightness.light);
