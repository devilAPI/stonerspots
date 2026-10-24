import 'package:flutter/material.dart';

const Color kAccent = Color(0xFF4CAF50);

ThemeData _build(Brightness b) {
  final scheme = ColorScheme.fromSeed(seedColor: kAccent, brightness: b);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: b == Brightness.dark ? const Color(0xFF101410) : null,
    inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
  );
}

final ThemeData darkTheme = _build(Brightness.dark);
final ThemeData lightTheme = _build(Brightness.light);
