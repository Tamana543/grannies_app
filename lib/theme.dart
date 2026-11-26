import 'package:flutter/material.dart';

const green = Color(0xFF39785C);
const paleGreen = Color(0xFFEDF5EE);
const red = Color(0xFFD96561);
const paleRed = Color(0xFFFFEFEB);
const ink = Color(0xFF23352D);
const muted = Color(0xFF758279);
ThemeData appTheme() => ThemeData(
  useMaterial3: true,
  scaffoldBackgroundColor: const Color(0xFFFCFDFB),
  colorScheme: ColorScheme.fromSeed(
    seedColor: green,
    brightness: Brightness.light,
    surface: Colors.white,
  ),
  textTheme: const TextTheme(
    headlineLarge: TextStyle(
      fontSize: 34,
      fontWeight: FontWeight.w800,
      color: ink,
      letterSpacing: -1.2,
    ),
    headlineMedium: TextStyle(
      fontSize: 28,
      fontWeight: FontWeight.w800,
      color: ink,
      letterSpacing: -.7,
    ),
    titleLarge: TextStyle(
      fontSize: 21,
      fontWeight: FontWeight.w700,
      color: ink,
    ),
    bodyLarge: TextStyle(fontSize: 16, height: 1.5, color: ink),
    bodyMedium: TextStyle(fontSize: 14, height: 1.5, color: muted),
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: Color(0xFFFCFDFB),
    foregroundColor: ink,
    elevation: 0,
    scrolledUnderElevation: 0,
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.all(18),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(color: Color(0xFFDCE7DE)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(color: Color(0xFFDCE7DE)),
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: green,
      foregroundColor: Colors.white,
      minimumSize: const Size(48, 56),
      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
  ),
);
