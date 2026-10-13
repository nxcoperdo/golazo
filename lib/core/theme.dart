import 'package:flutter/material.dart';

const golazoGreen = Color(0xFF1B8A3A);

ThemeData buildTheme() => ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: golazoGreen),
      cardTheme: const CardThemeData(clipBehavior: Clip.antiAlias),
    );
