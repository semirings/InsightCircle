import 'package:flutter/material.dart';

const kPaleYellow = Color(0xFFFFFDE7);
const kRed        = Color(0xFFD32F2F);

ThemeData buildTheme() => ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: kRed,
        brightness: Brightness.light,
      ).copyWith(
        surface: Colors.white,
        primary: kRed,
        onPrimary: Colors.white,
        secondary: kPaleYellow,
        onSecondary: Colors.black,
      ),
      scaffoldBackgroundColor: Colors.white,
      textTheme: const TextTheme(
        headlineLarge: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        bodyMedium: TextStyle(color: Colors.black),
      ),
    );
