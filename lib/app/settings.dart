/// Terminal settings — configurable font, font size, and color theme.
///
/// [TerminalSettings] is a [ChangeNotifier] that stores user preferences and
/// persists them to `~/Library/Application Support/magnet-terminal/config.json`.
///
/// Provides:
/// - Font family selection (SF Mono, Menlo, JetBrains Mono, Fira Code, etc.)
/// - Font size with Cmd+/Cmd- zoom support
/// - Terminal color theme selection from built-in presets
/// - Automatic persistence on every change
///
/// The settings are loaded asynchronously at startup via [load()]. Until loaded,
/// defaults are used so the UI is never blocked.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dart_xterm/dart_xterm.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

// ---------------------------------------------------------------------------
//  Font family definitions
// ---------------------------------------------------------------------------

/// A monospace font option available for terminal rendering.
class FontOption {
  const FontOption({
    required this.displayName,
    required this.family,
    this.fallback = const ['Menlo', 'Monaco', 'Consolas', 'monospace'],
  });

  /// Human-readable name shown in the UI.
  final String displayName;

  /// The CSS/Flutter font family string.
  final String family;

  /// Fallback font families if the primary is unavailable.
  final List<String> fallback;
}

/// Built-in font options. These are monospace fonts commonly available on macOS
/// or bundled with developer tools.
const kFontOptions = <FontOption>[
  FontOption(
    displayName: 'SF Mono',
    family: 'SF Mono',
    fallback: ['Menlo', 'Monaco', 'Consolas', 'monospace'],
  ),
  FontOption(
    displayName: 'Menlo',
    family: 'Menlo',
    fallback: ['Monaco', 'Consolas', 'monospace'],
  ),
  FontOption(
    displayName: 'Monaco',
    family: 'Monaco',
    fallback: ['Menlo', 'Consolas', 'monospace'],
  ),
  FontOption(
    displayName: 'JetBrains Mono',
    family: 'JetBrains Mono',
    fallback: ['SF Mono', 'Menlo', 'monospace'],
  ),
  FontOption(
    displayName: 'Fira Code',
    family: 'Fira Code',
    fallback: ['SF Mono', 'Menlo', 'monospace'],
  ),
  FontOption(
    displayName: 'Courier New',
    family: 'Courier New',
    fallback: ['Courier', 'monospace'],
  ),
];

// ---------------------------------------------------------------------------
//  Terminal color theme definitions
// ---------------------------------------------------------------------------

/// A named terminal color theme with all 16 ANSI colors plus UI colors.
class TerminalColorTheme {
  const TerminalColorTheme({
    required this.name,
    required this.theme,
  });

  /// Human-readable name for the UI.
  final String name;

  /// The actual dart_xterm [TerminalTheme] colors.
  final TerminalTheme theme;
}

/// Built-in terminal color themes.
const kTerminalThemes = <TerminalColorTheme>[
  // Default Dark — VS Code inspired
  TerminalColorTheme(
    name: 'Default Dark',
    theme: TerminalTheme(
      cursor: Color(0xFFAEAFAD),
      selection: Color(0x80AEAFAD),
      foreground: Color(0xFFCCCCCC),
      background: Color(0xFF0D1117),
      black: Color(0xFF000000),
      red: Color(0xFFCD3131),
      green: Color(0xFF0DBC79),
      yellow: Color(0xFFE5E510),
      blue: Color(0xFF2472C8),
      magenta: Color(0xFFBC3FBC),
      cyan: Color(0xFF11A8CD),
      white: Color(0xFFE5E5E5),
      brightBlack: Color(0xFF666666),
      brightRed: Color(0xFFF14C4C),
      brightGreen: Color(0xFF23D18B),
      brightYellow: Color(0xFFF5F543),
      brightBlue: Color(0xFF3B8EEA),
      brightMagenta: Color(0xFFD670D6),
      brightCyan: Color(0xFF29B8DB),
      brightWhite: Color(0xFFFFFFFF),
      searchHitBackground: Color(0xFFFFFF2B),
      searchHitBackgroundCurrent: Color(0xFF31FF26),
      searchHitForeground: Color(0xFF000000),
    ),
  ),

  // Dracula
  TerminalColorTheme(
    name: 'Dracula',
    theme: TerminalTheme(
      cursor: Color(0xFFF8F8F2),
      selection: Color(0x8044475A),
      foreground: Color(0xFFF8F8F2),
      background: Color(0xFF282A36),
      black: Color(0xFF21222C),
      red: Color(0xFFFF5555),
      green: Color(0xFF50FA7B),
      yellow: Color(0xFFF1FA8C),
      blue: Color(0xFFBD93F9),
      magenta: Color(0xFFFF79C6),
      cyan: Color(0xFF8BE9FD),
      white: Color(0xFFF8F8F2),
      brightBlack: Color(0xFF6272A4),
      brightRed: Color(0xFFFF6E6E),
      brightGreen: Color(0xFF69FF94),
      brightYellow: Color(0xFFFFFFA5),
      brightBlue: Color(0xFFD6ACFF),
      brightMagenta: Color(0xFFFF92DF),
      brightCyan: Color(0xFFA4FFFF),
      brightWhite: Color(0xFFFFFFFF),
      searchHitBackground: Color(0xFFFFFF2B),
      searchHitBackgroundCurrent: Color(0xFF31FF26),
      searchHitForeground: Color(0xFF000000),
    ),
  ),

  // One Dark
  TerminalColorTheme(
    name: 'One Dark',
    theme: TerminalTheme(
      cursor: Color(0xFF528BFF),
      selection: Color(0x803E4451),
      foreground: Color(0xFFABB2BF),
      background: Color(0xFF282C34),
      black: Color(0xFF282C34),
      red: Color(0xFFE06C75),
      green: Color(0xFF98C379),
      yellow: Color(0xFFE5C07B),
      blue: Color(0xFF61AFEF),
      magenta: Color(0xFFC678DD),
      cyan: Color(0xFF56B6C2),
      white: Color(0xFFABB2BF),
      brightBlack: Color(0xFF5C6370),
      brightRed: Color(0xFFE06C75),
      brightGreen: Color(0xFF98C379),
      brightYellow: Color(0xFFE5C07B),
      brightBlue: Color(0xFF61AFEF),
      brightMagenta: Color(0xFFC678DD),
      brightCyan: Color(0xFF56B6C2),
      brightWhite: Color(0xFFFFFFFF),
      searchHitBackground: Color(0xFFFFFF2B),
      searchHitBackgroundCurrent: Color(0xFF31FF26),
      searchHitForeground: Color(0xFF000000),
    ),
  ),

  // Solarized Dark
  TerminalColorTheme(
    name: 'Solarized Dark',
    theme: TerminalTheme(
      cursor: Color(0xFF839496),
      selection: Color(0x80073642),
      foreground: Color(0xFF839496),
      background: Color(0xFF002B36),
      black: Color(0xFF073642),
      red: Color(0xFFDC322F),
      green: Color(0xFF859900),
      yellow: Color(0xFFB58900),
      blue: Color(0xFF268BD2),
      magenta: Color(0xFFD33682),
      cyan: Color(0xFF2AA198),
      white: Color(0xFFEEE8D5),
      brightBlack: Color(0xFF586E75),
      brightRed: Color(0xFFCB4B16),
      brightGreen: Color(0xFF586E75),
      brightYellow: Color(0xFF657B83),
      brightBlue: Color(0xFF839496),
      brightMagenta: Color(0xFF6C71C4),
      brightCyan: Color(0xFF93A1A1),
      brightWhite: Color(0xFFFDF6E3),
      searchHitBackground: Color(0xFFFFFF2B),
      searchHitBackgroundCurrent: Color(0xFF31FF26),
      searchHitForeground: Color(0xFF000000),
    ),
  ),
];

// ---------------------------------------------------------------------------
//  Font size constraints
// ---------------------------------------------------------------------------

/// Minimum allowed font size.
const kMinFontSize = 10.0;

/// Maximum allowed font size.
const kMaxFontSize = 28.0;

/// Default font size.
const kDefaultFontSize = 14.0;

/// Font size increment for Cmd+/Cmd- zoom.
const kFontSizeStep = 1.0;

/// Default line height multiplier.
const kDefaultLineHeight = 1.2;

// ---------------------------------------------------------------------------
//  TerminalSettings — ChangeNotifier with persistence
// ---------------------------------------------------------------------------

/// Manages terminal appearance settings with automatic JSON persistence.
///
/// Usage:
/// ```dart
/// final settings = TerminalSettings();
/// await settings.load(); // Load from disk (uses defaults if file missing)
///
/// // Listen for changes
/// settings.addListener(() {
///   // Rebuild terminal with new theme/font
/// });
///
/// // Modify settings (automatically persists)
/// settings.fontFamily = 'JetBrains Mono';
/// settings.fontSize = 16;
/// settings.themeName = 'Dracula';
/// ```
class TerminalSettings extends ChangeNotifier {
  // -- Font settings --
  String _fontFamily = 'SF Mono';
  double _fontSize = kDefaultFontSize;
  double _lineHeight = kDefaultLineHeight;

  // -- Theme settings --
  String _themeName = 'Default Dark';

  /// The currently selected font family name.
  String get fontFamily => _fontFamily;
  set fontFamily(String value) {
    if (_fontFamily == value) return;
    _fontFamily = value;
    notifyListeners();
    _persist();
  }

  /// The current font size in logical pixels.
  double get fontSize => _fontSize;
  set fontSize(double value) {
    final clamped = value.clamp(kMinFontSize, kMaxFontSize);
    if (_fontSize == clamped) return;
    _fontSize = clamped;
    notifyListeners();
    _persist();
  }

  /// Line height multiplier.
  double get lineHeight => _lineHeight;
  set lineHeight(double value) {
    if (_lineHeight == value) return;
    _lineHeight = value;
    notifyListeners();
    _persist();
  }

  /// The name of the active terminal color theme.
  String get themeName => _themeName;
  set themeName(String value) {
    if (_themeName == value) return;
    // Validate that the theme exists.
    if (kTerminalThemes.any((t) => t.name == value)) {
      _themeName = value;
      notifyListeners();
      _persist();
    }
  }

  // ---------------------------------------------------------------------------
  //  Derived getters — build dart_xterm objects from current settings
  // ---------------------------------------------------------------------------

  /// Returns the [FontOption] matching the current [fontFamily], or the first
  /// option as fallback.
  FontOption get fontOption {
    return kFontOptions.firstWhere(
      (f) => f.family == _fontFamily,
      orElse: () => kFontOptions.first,
    );
  }

  /// Builds a [TerminalStyle] from current font settings.
  TerminalStyle get terminalStyle {
    final font = fontOption;
    return TerminalStyle(
      fontSize: _fontSize,
      height: _lineHeight,
      fontFamily: font.family,
      fontFamilyFallback: font.fallback,
    );
  }

  /// Returns the active [TerminalTheme].
  TerminalTheme get terminalTheme {
    return kTerminalThemes
        .firstWhere(
          (t) => t.name == _themeName,
          orElse: () => kTerminalThemes.first,
        )
        .theme;
  }

  /// The background color of the active terminal theme. Exposed so the
  /// scaffold/chrome can match it.
  Color get terminalBackground => terminalTheme.background;

  // ---------------------------------------------------------------------------
  //  Font size zoom helpers
  // ---------------------------------------------------------------------------

  /// Increase font size by one step (Cmd+).
  void increaseFontSize() {
    fontSize = _fontSize + kFontSizeStep;
  }

  /// Decrease font size by one step (Cmd-).
  void decreaseFontSize() {
    fontSize = _fontSize - kFontSizeStep;
  }

  /// Reset font size to default (Cmd+0).
  void resetFontSize() {
    fontSize = kDefaultFontSize;
  }

  // ---------------------------------------------------------------------------
  //  Persistence — JSON config file
  // ---------------------------------------------------------------------------

  /// Path to the config file:
  /// ~/Library/Application Support/magnet-terminal/config.json
  static String get _configDir {
    final home = Platform.environment['HOME'] ?? '/tmp';
    return p.join(home, 'Library', 'Application Support', 'magnet-terminal');
  }

  static String get _configPath => p.join(_configDir, 'config.json');

  /// Load settings from the config file. Uses defaults if the file is missing
  /// or contains invalid JSON. Safe to call multiple times.
  Future<void> load() async {
    try {
      final file = File(_configPath);
      if (!await file.exists()) return;

      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;

      _fontFamily = json['fontFamily'] as String? ?? _fontFamily;
      _fontSize = (json['fontSize'] as num?)?.toDouble() ?? _fontSize;
      _lineHeight = (json['lineHeight'] as num?)?.toDouble() ?? _lineHeight;
      _themeName = json['themeName'] as String? ?? _themeName;

      // Clamp font size to valid range.
      _fontSize = _fontSize.clamp(kMinFontSize, kMaxFontSize);

      // Validate theme name — fall back to default if unknown.
      if (!kTerminalThemes.any((t) => t.name == _themeName)) {
        _themeName = 'Default Dark';
      }

      notifyListeners();
    } catch (e) {
      // Config file is corrupt or unreadable — use defaults silently.
      debugPrint('TerminalSettings: failed to load config: $e');
    }
  }

  /// Persist current settings to disk. Fire-and-forget — errors are logged
  /// but do not propagate.
  void _persist() {
    _persistAsync();
  }

  Future<void> _persistAsync() async {
    try {
      final dir = Directory(_configDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final json = {
        'fontFamily': _fontFamily,
        'fontSize': _fontSize,
        'lineHeight': _lineHeight,
        'themeName': _themeName,
      };

      final file = File(_configPath);
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(json),
      );
    } catch (e) {
      debugPrint('TerminalSettings: failed to persist config: $e');
    }
  }
}
