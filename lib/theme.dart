import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import 'package:google_fonts/google_fonts.dart';

/// Clase que centraliza la paleta de colores de FRIFALCA.
/// Basado en el Rebranding: Robustez industrial y tecnología de frío avanzada.
class AppColors {
  // Colores principales
  static const Color primary = Color(0xFF0A2540); // Deep Industrial
  static const Color secondary = Color(0xFF00D4FF); // Glacier Cyan

  // Modo claro
  static const Color lightBackground = Color(0xFFF6F9FC); // Soft Gray
  static const Color lightSurface = Color(0xFFFFFFFF); // Pure White
  static const Color lightInputFill = Color(0xFFF1F5F9);

  // Modo oscuro
  static const Color darkBackground = Color(0xFF121212);
  static const Color darkSurface = Color(0xFF1E1E1E);
  static const Color darkCard = Color(0xFF2C2C2C);
  static const Color darkInputFill = Color(0xFF2A2A2A);

  // Colores de estado y soporte
  static const Color error = Color(0xFFE63946);
  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFFC107);

  // Colores de estado de pedidos
  static const Color pedidoDespachado = Color(0xFF4CAF50); // Verde
  static const Color pedidoEnProceso = Color(0xFFFFC107); // Amarillo
  static const Color pedidoCancelado = Color(0xFFE63946); // Rojo
  static const Color pedidoSinStock = Color(0xFFFF9800); // Naranja

  // Colores de texto - Modo claro
  static const Color textPrimaryLight = Color(0xFF0A2540);
  static const Color textSecondaryLight = Color(0xFF425466);
  static const Color textLabelLight = Color(0xFF94A3B8);

  // Colores de texto - Modo oscuro (blancos para buen contraste)
  static const Color textPrimaryDark = Color(0xFFFFFFFF);
  static const Color textSecondaryDark = Color(0xFFE0E0E0);
  static const Color textLabelDark = Color(0xFFB0BEC5);
}

/// Clase que define el tema global de la aplicación FRIFALCA.
class AppTheme {
  // Tamaños de fuente centralizados para consistencia
  static const double displayLargeSize = 24;
  static const double headlineMediumSize = 20;
  static const double titleMediumSize = 16;
  static const double bodyLargeSize = 14;
  static const double bodyMediumSize = 13;
  static const double labelSmallSize = 11;

  static const double titleLineHeight = 1.2;
  static const double bodyLineHeight = 1.5;

  /// Tema claro: texto oscuro sobre fondo claro
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primary,
        secondary: AppColors.secondary,
        surface: AppColors.lightSurface,
        error: AppColors.error,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
      ),
      scaffoldBackgroundColor: AppColors.lightBackground,

      // Configuración de AppBar (Branding: Deep Industrial)
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: Colors.white),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness:
              Brightness.light, // Iconos claros en barra de estado
          statusBarBrightness: Brightness.dark, // Para iOS
        ),
      ),

      // Tipografía completa - Modo claro (texto oscuro)
      textTheme: TextTheme(
        displayLarge: GoogleFonts.montserrat(
          fontSize: displayLargeSize,
          fontWeight: FontWeight.bold,
          color: AppColors.textPrimaryLight,
          height: titleLineHeight,
        ),
        headlineMedium: GoogleFonts.montserrat(
          fontSize: headlineMediumSize,
          fontWeight: FontWeight.bold,
          color: AppColors.textPrimaryLight,
          height: titleLineHeight,
        ),
        titleMedium: GoogleFonts.montserrat(
          fontSize: titleMediumSize,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimaryLight,
          height: titleLineHeight,
        ),
        bodyLarge: GoogleFonts.inter(
          fontSize: bodyLargeSize,
          color: AppColors.textSecondaryLight,
          height: bodyLineHeight,
        ),
        bodyMedium: GoogleFonts.inter(
          fontSize: bodyMediumSize,
          color: AppColors.textSecondaryLight,
          height: bodyLineHeight,
        ),
        labelSmall: GoogleFonts.inter(
          fontSize: labelSmallSize,
          fontWeight: FontWeight.w500,
          color: AppColors.textLabelLight,
          height: bodyLineHeight,
        ),
      ),

      // Estilo de botones elevados (Flat 2.0)
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),

      // Configuración de Cards (Branding: Limpieza y Profesionalismo)
      cardTheme: CardThemeData(
        elevation: 2,
        color: AppColors.lightSurface,
        shadowColor: Colors.black.withValues(alpha: 0.12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),

      // Decoración de campos de texto (TextFields Modernos)
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.lightInputFill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.secondary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error, width: 1),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        labelStyle: GoogleFonts.inter(color: AppColors.textSecondaryLight),
        hintStyle: GoogleFonts.inter(
          color: AppColors.textLabelLight.withValues(alpha: 0.7),
        ),
      ),

      // Botón flotante (Acento: Glacier Cyan)
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.secondary,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: CircleBorder(),
      ),
    );
  }

  /// Tema oscuro: texto blanco sobre fondo oscuro
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        brightness: Brightness.dark,
        seedColor: AppColors.secondary,
        primary: AppColors.secondary,
        secondary: AppColors.primary,
        surface: AppColors.darkSurface,
        error: AppColors.error,
        onPrimary: Colors.white,
        onSecondary: AppColors.primary,
        onSurface: AppColors.textPrimaryDark,
      ),
      scaffoldBackgroundColor: AppColors.darkBackground,

      // Configuración de AppBar (Branding: Deep Industrial)
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: Colors.white),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness:
              Brightness.light, // Iconos claros en barra de estado
          statusBarBrightness: Brightness.dark, // Para iOS
        ),
      ),

      // Tipografía completa - Modo oscuro (texto blanco/claro)
      textTheme: TextTheme(
        displayLarge: GoogleFonts.montserrat(
          fontSize: displayLargeSize,
          fontWeight: FontWeight.bold,
          color: AppColors.textPrimaryDark,
          height: titleLineHeight,
        ),
        headlineMedium: GoogleFonts.montserrat(
          fontSize: headlineMediumSize,
          fontWeight: FontWeight.bold,
          color: AppColors.textPrimaryDark,
          height: titleLineHeight,
        ),
        titleMedium: GoogleFonts.montserrat(
          fontSize: titleMediumSize,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimaryDark,
          height: titleLineHeight,
        ),
        bodyLarge: GoogleFonts.inter(
          fontSize: bodyLargeSize,
          color: AppColors.textSecondaryDark,
          height: bodyLineHeight,
        ),
        bodyMedium: GoogleFonts.inter(
          fontSize: bodyMediumSize,
          color: AppColors.textSecondaryDark,
          height: bodyLineHeight,
        ),
        labelSmall: GoogleFonts.inter(
          fontSize: labelSmallSize,
          fontWeight: FontWeight.w500,
          color: AppColors.textLabelDark,
          height: bodyLineHeight,
        ),
      ),

      // Estilo de botones elevados (Flat 2.0)
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.secondary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),

      // Configuración de Cards (Branding: Limpieza y Profesionalismo)
      cardTheme: CardThemeData(
        elevation: 2,
        color: AppColors.darkCard,
        shadowColor: Colors.black.withValues(alpha: 0.3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),

      // Decoración de campos de texto (TextFields Modernos)
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.darkInputFill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.secondary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error, width: 1),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        labelStyle: GoogleFonts.inter(color: AppColors.textSecondaryDark),
        hintStyle: GoogleFonts.inter(
          color: AppColors.textLabelDark.withValues(alpha: 0.7),
        ),
      ),

      // Botón flotante (Acento: Glacier Cyan)
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.secondary,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: CircleBorder(),
      ),
    );
  }
}

/// Comportamiento de Scroll personalizado para escritorio y móvil.
class AppScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
  };
}
