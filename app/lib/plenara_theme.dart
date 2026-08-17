import 'package:flutter/material.dart';

abstract final class PlenaraTheme {
  static const ground = Color(0xFF0A0908);
  static const ink = Color(0xFFEAE2D8);
  static const quietInk = Color(0xFFBDB3A7);
  static const amber = Color(0xFFD99A54);
  static const card = Color(0xD9191612);
  static const line = Color(0x337E7164);

  static ThemeData get dark {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: amber,
          brightness: Brightness.dark,
          surface: ground,
        ).copyWith(
          primary: amber,
          surface: ground,
          onSurface: ink,
          outline: quietInk,
        );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: ground,
      textTheme: ThemeData.dark().textTheme.apply(
        bodyColor: ink,
        displayColor: ink,
      ),
      cardTheme: const CardThemeData(
        color: card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
          side: BorderSide(color: line),
        ),
      ),
    );
  }
}
