import 'package:flutter/material.dart';

/// Magnet Terminal theming — Material 3 dark theme optimized for terminal use.
///
/// Uses [ColorScheme.fromSeed] with a deep blue-grey seed for a cohesive
/// terminal-appropriate palette. The terminal area itself uses its own colors
/// (from xterm's color scheme), but chrome elements (tabs, toolbar, dialogs)
/// use this theme.
///
/// Design goals:
/// - Very dark surfaces so the terminal content is the visual focus
/// - Monospace font defaults for terminal rendering
/// - Minimal elevation/shadows — flat, dense chrome
/// - High contrast text on dark backgrounds
class AppTheme {
  AppTheme._();

  /// Seed color: a muted blue-grey that produces a cool, terminal-friendly
  /// palette without the purple tint of the default Material seed.
  static const _seedColor = Color(0xFF3D5A80);

  /// Default terminal background color — used when no settings are provided.
  /// This is separate from the scaffold/surface colors so the chrome can
  /// be visually distinct from the terminal content.
  static const defaultTerminalBackground = Color(0xFF0D1117);

  /// Surface color for tab bars and toolbars — slightly lighter than terminal
  /// background to create a subtle visual hierarchy.
  static const chromeBackground = Color(0xFF161B22);

  /// Dark theme — primary theme for a terminal app.
  ///
  /// [terminalBackground] overrides the scaffold background to match the
  /// active terminal color theme. Falls back to [defaultTerminalBackground].
  static ThemeData dark({Color? terminalBackground}) {
    final bgColor = terminalBackground ?? defaultTerminalBackground;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: Brightness.dark,
      surface: chromeBackground,
      onSurface: const Color(0xFFE6EDF3),
    );

    // Monospace text theme for terminal-appropriate rendering.
    // Using the system monospace font (SF Mono on macOS) which renders
    // crisply at all sizes and has excellent Unicode coverage.
    const monoFamily = 'SF Mono';
    const fallbackFonts = ['Menlo', 'Monaco', 'Courier New'];

    final textTheme = TextTheme(
      // Display styles — used for large headings, not common in terminal chrome
      displayLarge: TextStyle(
        fontFamily: monoFamily,
        fontFamilyFallback: fallbackFonts,
        fontSize: 32,
        fontWeight: FontWeight.w300,
        letterSpacing: -0.5,
      ),
      displayMedium: TextStyle(
        fontFamily: monoFamily,
        fontFamilyFallback: fallbackFonts,
        fontSize: 24,
        fontWeight: FontWeight.w300,
      ),
      displaySmall: TextStyle(
        fontFamily: monoFamily,
        fontFamilyFallback: fallbackFonts,
        fontSize: 20,
        fontWeight: FontWeight.w400,
      ),

      // Title styles — tab titles, dialog titles
      titleLarge: TextStyle(
        fontFamily: monoFamily,
        fontFamilyFallback: fallbackFonts,
        fontSize: 16,
        fontWeight: FontWeight.w500,
      ),
      titleMedium: TextStyle(
        fontFamily: monoFamily,
        fontFamilyFallback: fallbackFonts,
        fontSize: 14,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.15,
      ),
      titleSmall: TextStyle(
        fontFamily: monoFamily,
        fontFamilyFallback: fallbackFonts,
        fontSize: 12,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.1,
      ),

      // Body styles — general text in chrome areas
      bodyLarge: TextStyle(
        fontFamily: monoFamily,
        fontFamilyFallback: fallbackFonts,
        fontSize: 14,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.25,
      ),
      bodyMedium: TextStyle(
        fontFamily: monoFamily,
        fontFamilyFallback: fallbackFonts,
        fontSize: 13,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.25,
      ),
      bodySmall: TextStyle(
        fontFamily: monoFamily,
        fontFamilyFallback: fallbackFonts,
        fontSize: 12,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.4,
      ),

      // Label styles — buttons, chips, badges
      labelLarge: TextStyle(
        fontFamily: monoFamily,
        fontFamilyFallback: fallbackFonts,
        fontSize: 13,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.1,
      ),
      labelMedium: TextStyle(
        fontFamily: monoFamily,
        fontFamilyFallback: fallbackFonts,
        fontSize: 11,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
      ),
      labelSmall: TextStyle(
        fontFamily: monoFamily,
        fontFamilyFallback: fallbackFonts,
        fontSize: 10,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bgColor,
      textTheme: textTheme,

      // AppBar — flat, no elevation, blends with chrome
      appBarTheme: AppBarTheme(
        backgroundColor: chromeBackground,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleMedium?.copyWith(
          color: colorScheme.onSurface,
        ),
      ),

      // Cards — flat with subtle border, no shadow
      cardTheme: CardThemeData(
        elevation: 0,
        color: chromeBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),

      // Dividers — very subtle separators
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        thickness: 1,
        space: 1,
      ),

      // Icon buttons — common in terminal chrome (close tab, settings, etc.)
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: colorScheme.onSurface.withValues(alpha: 0.7),
          minimumSize: const Size(28, 28),
          padding: const EdgeInsets.all(4),
        ),
      ),

      // Tooltips — dark background, monospace text
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: const Color(0xFF2D333B),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        textStyle: textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurface,
        ),
        waitDuration: const Duration(milliseconds: 500),
      ),

      // Popup menus — context menus for tabs, right-click, etc.
      popupMenuTheme: PopupMenuThemeData(
        color: const Color(0xFF1C2128),
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        textStyle: textTheme.bodyMedium,
      ),

      // Dialogs — settings, confirmations
      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xFF1C2128),
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: colorScheme.onSurface,
        ),
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurface.withValues(alpha: 0.8),
        ),
      ),

      // Input decoration — for search, command palette, etc.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: bgColor,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 8,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(
            color: colorScheme.primary,
            width: 1.5,
          ),
        ),
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurface.withValues(alpha: 0.4),
        ),
      ),

      // Scrollbar — thin, subtle
      scrollbarTheme: ScrollbarThemeData(
        thickness: WidgetStateProperty.all(6),
        thumbColor: WidgetStateProperty.all(
          colorScheme.onSurface.withValues(alpha: 0.2),
        ),
        radius: const Radius.circular(3),
      ),
    );
  }
}
