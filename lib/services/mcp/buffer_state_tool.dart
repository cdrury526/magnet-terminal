/// MCP tools for inspecting terminal cursor and buffer state.
///
/// Provides two read-only inspection tools:
/// - `cursor_state` — cursor position, style, visibility, active buffer
/// - `buffer_state` — DEC mode flags, mouse mode, terminal dimensions,
///   scrollback size, and other terminal configuration state
///
/// These tools access the dart_xterm [Terminal] object directly and
/// never mutate state.
library;

import 'dart:convert';

import 'package:dart_xterm/dart_xterm.dart';

/// JSON schema for the `cursor_state` tool (no parameters needed).
const cursorStateSchema = <String, dynamic>{
  'type': 'object',
  'properties': <String, dynamic>{},
};

/// JSON schema for the `buffer_state` tool (no parameters needed).
const bufferStateSchema = <String, dynamic>{
  'type': 'object',
  'properties': <String, dynamic>{},
};

/// Handles the `cursor_state` tool call.
///
/// Reports cursor position, style attributes, visibility, and which
/// buffer (main vs alt) is currently active.
String handleCursorState(Terminal terminal, Map<String, dynamic> args) {
  final buffer = terminal.buffer;
  final cursor = terminal.cursor;

  return jsonEncode({
    'cursor': {
      'x': buffer.cursorX,
      'y': buffer.cursorY,
      'absolute_y': buffer.absoluteCursorY,
    },
    'style': {
      'bold': cursor.isBold,
      'faint': cursor.isFaint,
      'italic': cursor.isItalis,
      'underline': cursor.isUnderline,
      'blink': cursor.isBlink,
      'inverse': cursor.isInverse,
      'invisible': cursor.isInvisible,
      'foreground_raw': cursor.foreground,
      'background_raw': cursor.background,
    },
    'visibility': {
      'visible': terminal.cursorVisibleMode,
      'blinking': terminal.cursorBlinkMode,
    },
    'buffer': {
      'active': terminal.isUsingAltBuffer ? 'alt' : 'main',
      'scrollback_lines': buffer.lines.length - terminal.viewHeight,
    },
    'dimensions': {
      'columns': terminal.viewWidth,
      'rows': terminal.viewHeight,
    },
  });
}

/// Handles the `buffer_state` tool call.
///
/// Reports active DEC private modes, mouse tracking state, and other
/// terminal configuration flags that affect behavior.
String handleBufferState(Terminal terminal, Map<String, dynamic> args) {
  return jsonEncode({
    'dimensions': {
      'columns': terminal.viewWidth,
      'rows': terminal.viewHeight,
    },
    'active_buffer': terminal.isUsingAltBuffer ? 'alt' : 'main',
    'scrollback': {
      'total_lines': terminal.buffer.lines.length,
      'viewport_lines': terminal.viewHeight,
      'scrollback_lines':
          terminal.buffer.lines.length - terminal.viewHeight,
    },
    'mouse': {
      'mode': terminal.mouseMode.name,
      'report_mode': terminal.mouseReportMode.name,
    },
    'dec_modes': {
      'DECAWM': terminal.autoWrapMode,
      'DECOM': terminal.originMode,
      'DECCKM': terminal.cursorKeysMode,
      'DECTCEM': terminal.cursorVisibleMode,
      'ATT610': terminal.cursorBlinkMode,
      'reverse_display': terminal.reverseDisplayMode,
      'insert_mode': terminal.insertMode,
      'line_feed_mode': terminal.lineFeedMode,
      'bracketed_paste': terminal.bracketedPasteMode,
      'report_focus': terminal.reportFocusMode,
      'app_keypad': terminal.appKeypadMode,
      'alt_buffer_mouse_scroll': terminal.altBufferMouseScrollMode,
    },
    'margins': {
      'top': terminal.buffer.marginTop,
      'bottom': terminal.buffer.marginBottom,
    },
  });
}
