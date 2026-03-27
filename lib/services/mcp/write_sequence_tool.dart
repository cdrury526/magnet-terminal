/// MCP tool for injecting raw escape sequences into the terminal.
///
/// Provides `write_sequence` — sends a raw string (which may contain escape
/// sequences) to the PTY, as if the terminal itself generated the output.
/// This is useful for testing how the terminal handles specific sequences,
/// such as sending a Device Attributes (DA) query and observing the response.
///
/// **This is the only tool that writes to the terminal.** All other tools
/// are strictly read-only.
library;

import 'dart:convert';

import 'package:dart_xterm/dart_xterm.dart';

/// Callback that writes a raw string to the PTY stdin.
///
/// This bypasses the terminal input handler and writes directly, which is
/// needed for injecting escape sequences that the application under the
/// PTY should process.
typedef PtyWriter = void Function(String data);

/// JSON schema for the `write_sequence` tool's input parameters.
const writeSequenceSchema = <String, dynamic>{
  'type': 'object',
  'properties': {
    'sequence': {
      'type': 'string',
      'description':
          'The escape sequence to send. Use \\x1b for ESC (0x1B), '
              '\\x07 for BEL, \\x0a for LF, etc. Examples:\n'
              '  - "\\x1b[c"  — Primary Device Attributes (DA1) query\n'
              '  - "\\x1b[>c" — Secondary DA query\n'
              '  - "\\x1b[6n" — Cursor Position Report (CPR)\n'
              '  - "\\x1b[?1h" — Set DECCKM (application cursor keys)\n'
              '  - "\\x1b]0;My Title\\x07" — Set window title via OSC 0',
    },
    'target': {
      'type': 'string',
      'description':
          'Where to inject the sequence:\n'
              '  - "terminal" (default) — write to Terminal.write(), as if '
              'the PTY sent it. The terminal processes the escape sequence.\n'
              '  - "pty" — write to the PTY stdin, as if the user typed it. '
              'The application under the PTY receives the data.',
      'enum': ['terminal', 'pty'],
    },
    'description': {
      'type': 'string',
      'description':
          'Optional human-readable note about what this sequence is for '
              '(logged for debugging, not sent to the terminal)',
    },
  },
  'required': ['sequence'],
};

/// Handles the `write_sequence` tool call.
///
/// Parses escape notation in the input string and writes it to either
/// the terminal buffer or the PTY stdin, depending on [target].
String handleWriteSequence(
  Terminal terminal,
  PtyWriter? ptyWriter,
  Map<String, dynamic> args,
) {
  final rawSequence = args['sequence'] as String?;
  if (rawSequence == null || rawSequence.isEmpty) {
    return jsonEncode({'error': 'sequence parameter is required'});
  }

  final target = args['target'] as String? ?? 'terminal';
  final description = args['description'] as String?;

  // Parse escape notation: \x1b, \x07, \n, \r, \t, etc.
  final parsed = _parseEscapeNotation(rawSequence);

  switch (target) {
    case 'terminal':
      // Write directly to the terminal buffer — it processes the sequence.
      terminal.write(parsed);
      return jsonEncode({
        'status': 'ok',
        'target': 'terminal',
        'bytes_written': parsed.length,
        'parsed_sequence': _displaySequence(parsed),
        if (description != null) 'description': description,
      });

    case 'pty':
      if (ptyWriter == null) {
        return jsonEncode({
          'error': 'No PTY writer available — session may not be running',
        });
      }
      ptyWriter(parsed);
      return jsonEncode({
        'status': 'ok',
        'target': 'pty',
        'bytes_written': parsed.length,
        'parsed_sequence': _displaySequence(parsed),
        if (description != null) 'description': description,
      });

    default:
      return jsonEncode({
        'error': 'Invalid target "$target". Use "terminal" or "pty".',
      });
  }
}

/// Parse C-style escape notation into actual characters.
///
/// Supports:
/// - `\x1b` or `\x1B` — hex byte
/// - `\n`, `\r`, `\t` — common control characters
/// - `\a` — BEL (0x07)
/// - `\e` — ESC (0x1B)
/// - `\\` — literal backslash
String _parseEscapeNotation(String input) {
  final buf = StringBuffer();
  var i = 0;

  while (i < input.length) {
    if (input[i] == r'\' && i + 1 < input.length) {
      switch (input[i + 1]) {
        case 'x' || 'X':
          // Hex byte: \xNN
          if (i + 3 < input.length) {
            final hex = input.substring(i + 2, i + 4);
            final value = int.tryParse(hex, radix: 16);
            if (value != null) {
              buf.writeCharCode(value);
              i += 4;
              continue;
            }
          }
          // Invalid hex — write literal.
          buf.write(input[i]);
          i++;
        case 'n':
          buf.writeCharCode(0x0A);
          i += 2;
        case 'r':
          buf.writeCharCode(0x0D);
          i += 2;
        case 't':
          buf.writeCharCode(0x09);
          i += 2;
        case 'a':
          buf.writeCharCode(0x07);
          i += 2;
        case 'e':
          buf.writeCharCode(0x1B);
          i += 2;
        case r'\':
          buf.write(r'\');
          i += 2;
        default:
          buf.write(input[i]);
          i++;
      }
    } else {
      buf.write(input[i]);
      i++;
    }
  }

  return buf.toString();
}

/// Create a display-safe representation of parsed bytes.
String _displaySequence(String parsed) {
  final buf = StringBuffer();
  for (final code in parsed.runes) {
    if (code == 0x1B) {
      buf.write('ESC');
    } else if (code < 0x20) {
      buf.write('<0x${code.toRadixString(16).padLeft(2, '0')}>');
    } else if (code == 0x7F) {
      buf.write('<DEL>');
    } else {
      buf.writeCharCode(code);
    }
  }
  return buf.toString();
}
