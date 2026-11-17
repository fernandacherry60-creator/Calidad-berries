import 'package:flutter/material.dart';

/// Sistema de diseño de la app.
///
/// Decisiones pensadas para trabajo en campo:
/// - Alto contraste (lectura bajo sol directo).
/// - Objetivos tactiles grandes (>=52dp) para uso con guantes.
/// - Semaforo consistente en toda la app: verde / ambar / rojo.
/// - Tipografia del sistema (sin descargas en runtime: la app es offline).
class AppColors {
  AppColors._();

  // Paleta principal: "huerto al amanecer".
  static const Color primary = Color(0xFF14532D); // verde hoja profundo
  static const Color primaryLight = Color(0xFF2E7D46);
  static const Color blue = Color(0xFF2563EB);
  static const Color orange = Color(0xFFEA580C);
  static const Color purple = Color(0xFF7C3AED);
  static const Color berry = Color(0xFFB4234B); // frambuesa madura (accion / marca)
  static const Color surface = Color(0xFFFAF7F2); // crema calido, descansa la vista
  static const Color card = Color(0xFFFFFFFF);
  static const Color ink = Color(0xFF1C2321); // texto principal
  static const Color inkSoft = Color(0xFF5C6660); // texto secundario
  static const Color line = Color(0xFFE4DFD6); // bordes sutiles

  // Semaforo (unico en toda la app).
  static const Color ok = Color(0xFF2E7D32);
  static const Color warn = Color(0xFFB26A00);
  static const Color danger = Color(0xFFC62828);
  static const Color okBg = Color(0xFFE3F2E5);
  static const Color warnBg = Color(0xFFFFF3DC);
  static const Color dangerBg = Color(0xFFFDE3E3);

  // Identidad por cultivo (chips y encabezados).
  static const Map<String, Color> cultivo = {
    'Frambuesa': Color(0xFFD6336C),
    'Arandano': Color(0xFF2F5D8A),
    // Reservados para cuando se activen:
    'Zarzamora': Color(0xFF4C3A6E),
    'Fresa': Color(0xFFB01E2E),
  };
}

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      secondary: AppColors.berry,
      surface: AppColors.surface,
      error: AppColors.danger,
    ),
    scaffoldBackgroundColor: AppColors.surface,
  );

  return base.copyWith(
    textTheme: base.textTheme.copyWith(
      headlineMedium: const TextStyle(
        fontSize: 26,
        fontWeight: FontWeight.w800,
        color: AppColors.ink,
        letterSpacing: -0.5,
      ),
      titleLarge: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: AppColors.ink,
      ),
      titleMedium: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: AppColors.ink,
      ),
      bodyMedium: const TextStyle(fontSize: 15, color: AppColors.ink, height: 1.4),
      bodySmall: const TextStyle(fontSize: 13, color: AppColors.inkSoft),
      labelLarge: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.ink,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w800,
        color: AppColors.ink,
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.card,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.line),
      ),
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.card,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.danger),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.berry,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(54), // objetivo tactil grande
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        minimumSize: const Size.fromHeight(54),
        side: const BorderSide(color: AppColors.primary, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.berry,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(
          fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.blue,
        minimumSize: const Size(0, 44),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.orange,
      foregroundColor: Colors.white,
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: AppColors.okBg,
      selectedColor: AppColors.primaryLight,
      side: const BorderSide(color: AppColors.line),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12)),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.ink,
    ),
    dividerTheme: const DividerThemeData(color: AppColors.line, thickness: 1),
  );
}
