/// MCP tool for toggling runtime debug state.
///
/// Provides `toggle_debug` — enables or disables debug features at runtime
/// without restarting the app. Controls escape sequence capture, verbose
/// logging, and reports current debug state.
///
/// This tool is the runtime counterpart to [TerminalDebugConfig], which
/// is set at Terminal creation time. `toggle_debug` controls the MCP-level
/// debug instrumentation (escape log capture, verbose output).
library;

import 'dart:convert';
import 'dart:io' show Platform;

import 'escape_logger_tool.dart';

/// Runtime debug state that can be toggled via MCP tools.
///
/// This holds mutable state that persists for the lifetime of the
/// devtools server. It is shared across all tool invocations.
class DebugState {
  /// Whether escape sequence capture is active.
  ///
  /// When `true`, the [EscapeLogBuffer] records incoming sequences.
  /// When `false`, sequences pass through without recording.
  bool captureEscapes = true;

  /// Whether verbose logging is enabled.
  ///
  /// When `true`, additional diagnostic information is printed via
  /// `debugPrint` for every escape sequence processed.
  bool verboseLogging = false;

  /// A user-supplied label for the current debug session.
  ///
  /// Useful for marking "before" and "after" states when testing
  /// specific behaviors.
  String? sessionLabel;

  /// Timestamp when the current debug configuration was last changed.
  DateTime lastChanged = DateTime.now();

  /// Serializes the current state to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
    'capture_escapes': captureEscapes,
    'verbose_logging': verboseLogging,
    if (sessionLabel != null) 'session_label': sessionLabel,
    'last_changed': lastChanged.toIso8601String(),
  };
}

/// JSON schema for the `toggle_debug` tool's input parameters.
const toggleDebugSchema = <String, dynamic>{
  'type': 'object',
  'properties': {
    'action': {
      'type': 'string',
      'description':
          'What to do:\n'
              '  - "status" (default) — report current debug state\n'
              '  - "enable_capture" — start capturing escape sequences\n'
              '  - "disable_capture" — stop capturing escape sequences\n'
              '  - "enable_verbose" — enable verbose logging\n'
              '  - "disable_verbose" — disable verbose logging\n'
              '  - "reset" — reset all debug state to defaults\n'
              '  - "env" — report terminal environment variables',
      'enum': [
        'status',
        'enable_capture',
        'disable_capture',
        'enable_verbose',
        'disable_verbose',
        'reset',
        'env',
      ],
    },
    'label': {
      'type': 'string',
      'description':
          'Optional session label to tag the current debug session '
              '(e.g., "before-fix", "testing-DA-response")',
    },
  },
};

/// Handles the `toggle_debug` tool call.
///
/// Modifies the shared [DebugState] and [EscapeLogBuffer] based on the
/// requested action, then returns the current state.
String handleToggleDebug(
  DebugState debugState,
  EscapeLogBuffer escapeBuffer,
  Map<String, dynamic> args,
) {
  final action = args['action'] as String? ?? 'status';
  final label = args['label'] as String?;

  if (label != null) {
    debugState.sessionLabel = label;
  }

  switch (action) {
    case 'status':
      return _statusResponse(debugState, escapeBuffer);

    case 'enable_capture':
      debugState.captureEscapes = true;
      escapeBuffer.isCapturing = true;
      debugState.lastChanged = DateTime.now();
      return _statusResponse(debugState, escapeBuffer, message: 'Escape capture enabled');

    case 'disable_capture':
      debugState.captureEscapes = false;
      escapeBuffer.isCapturing = false;
      debugState.lastChanged = DateTime.now();
      return _statusResponse(
        debugState,
        escapeBuffer,
        message: 'Escape capture disabled',
      );

    case 'enable_verbose':
      debugState.verboseLogging = true;
      debugState.lastChanged = DateTime.now();
      return _statusResponse(debugState, escapeBuffer, message: 'Verbose logging enabled');

    case 'disable_verbose':
      debugState.verboseLogging = false;
      debugState.lastChanged = DateTime.now();
      return _statusResponse(
        debugState,
        escapeBuffer,
        message: 'Verbose logging disabled',
      );

    case 'reset':
      debugState
        ..captureEscapes = true
        ..verboseLogging = false
        ..sessionLabel = null
        ..lastChanged = DateTime.now();
      escapeBuffer
        ..isCapturing = true
        ..clear();
      return _statusResponse(debugState, escapeBuffer, message: 'Debug state reset to defaults');

    case 'env':
      return _envResponse();

    default:
      return jsonEncode({'error': 'Unknown action: $action'});
  }
}

/// Build a status response with the current debug state.
String _statusResponse(
  DebugState debugState,
  EscapeLogBuffer escapeBuffer, {
  String? message,
}) {
  return jsonEncode({
    if (message != null) 'message': message,
    'debug_state': debugState.toJson(),
    'escape_buffer': {
      'entries': escapeBuffer.length,
      'capacity': escapeBuffer.capacity,
      'capturing': escapeBuffer.isCapturing,
    },
  });
}

/// Build a response with relevant terminal environment variables.
///
/// This helps diagnose why CLI apps (e.g., Claude Code) may not detect
/// terminal capabilities correctly.
String _envResponse() {
  final env = Platform.environment;

  // Terminal-relevant environment variables to inspect.
  const termVars = [
    'TERM',
    'COLORTERM',
    'TERM_PROGRAM',
    'TERM_PROGRAM_VERSION',
    'FORCE_HYPERLINK',
    'LANG',
    'LC_ALL',
    'LC_CTYPE',
    'SHELL',
    'HOME',
    'USER',
    'PATH',
    'VTE_VERSION',
    'ITERM_SESSION_ID',
    'ITERM_PROFILE',
    'TERMINAL_EMULATOR',
    'WT_SESSION',
    'WEZTERM_EXECUTABLE',
    'KONSOLE_VERSION',
    'GNOME_TERMINAL_SCREEN',
    'TMUX',
    'STY',
    'SSH_TTY',
    'SSH_CONNECTION',
  ];

  final found = <String, String>{};
  final missing = <String>[];

  for (final key in termVars) {
    final value = env[key];
    if (value != null) {
      found[key] = value;
    } else {
      missing.add(key);
    }
  }

  return jsonEncode({
    'environment': found,
    'missing': missing,
    'note':
        'These environment variables are set at PTY spawn time and '
        'affect how CLI apps detect terminal capabilities. Variables '
        'like TERM, COLORTERM, and TERM_PROGRAM are critical for '
        'feature detection (hyperlinks, true color, etc.).',
  });
}
