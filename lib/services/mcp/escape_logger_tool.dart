/// MCP tool for capturing and inspecting escape sequences.
///
/// Provides `escape_log` — returns recent escape sequences that have been
/// processed by the terminal, with timestamps, decoded names (CSI, OSC, DCS),
/// and raw byte representations.
///
/// Escape sequences are captured by hooking into the [Terminal]'s
/// [TerminalDebugConfig] callbacks. A ring buffer of configurable size
/// retains the most recent entries. This is a read-only inspection tool.
library;

import 'dart:convert';

/// A single captured escape sequence entry.
class EscapeLogEntry {
  /// Creates an escape log entry.
  const EscapeLogEntry({
    required this.timestamp,
    required this.raw,
    required this.decoded,
    required this.category,
    required this.explanation,
    this.isError = false,
  });

  /// When the sequence was received.
  final DateTime timestamp;

  /// The raw escape sequence bytes as a human-readable escaped string.
  final String raw;

  /// The decoded/pretty-printed representation (e.g., `ESC[1;2H`).
  final String decoded;

  /// The category: `CSI`, `OSC`, `DCS`, `ESC`, `SBC`, `SGR`, or `unknown`.
  final String category;

  /// Human-readable explanation of what the sequence does.
  final String explanation;

  /// Whether this sequence caused a parse error.
  final bool isError;

  /// Serializes to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'raw': raw,
    'decoded': decoded,
    'category': category,
    'explanation': explanation,
    if (isError) 'error': true,
  };
}

/// Ring buffer that captures escape sequences for MCP inspection.
///
/// Thread-safe for single-isolate usage (Flutter main isolate). The buffer
/// automatically evicts the oldest entries when capacity is exceeded.
class EscapeLogBuffer {
  /// Creates a ring buffer with the given [capacity].
  EscapeLogBuffer({this.capacity = 500});

  /// Maximum number of entries to retain.
  final int capacity;

  final List<EscapeLogEntry> _entries = [];

  /// Whether capture is currently enabled.
  bool isCapturing = true;

  /// All captured entries (oldest first).
  List<EscapeLogEntry> get entries => List.unmodifiable(_entries);

  /// Number of entries currently in the buffer.
  int get length => _entries.length;

  /// Add an entry to the ring buffer.
  ///
  /// If the buffer is at capacity, the oldest entry is removed.
  void add(EscapeLogEntry entry) {
    if (!isCapturing) return;

    if (_entries.length >= capacity) {
      _entries.removeAt(0);
    }
    _entries.add(entry);
  }

  /// Clear all captured entries.
  void clear() {
    _entries.clear();
  }

  /// Record a parsed escape sequence.
  ///
  /// [rawChars] is the raw character sequence, [explanation] is the
  /// human-readable description from the escape parser, and [isError]
  /// indicates whether this was a parse error.
  void record(String rawChars, String explanation, {bool isError = false}) {
    final category = _categorize(rawChars);
    final decoded = _decodeSequence(rawChars);

    add(EscapeLogEntry(
      timestamp: DateTime.now(),
      raw: _escapeForDisplay(rawChars),
      decoded: decoded,
      category: category,
      explanation: explanation,
      isError: isError,
    ));
  }

  /// Record a parse error from [TerminalDebugConfig.onParseError].
  void recordParseError(String sequence, String reason) {
    add(EscapeLogEntry(
      timestamp: DateTime.now(),
      raw: _escapeForDisplay(sequence),
      decoded: sequence,
      category: 'error',
      explanation: 'Parse error: $reason',
      isError: true,
    ));
  }

  /// Record an unhandled sequence from
  /// [TerminalDebugConfig.onUnhandledSequence].
  void recordUnhandled(String sequence) {
    add(EscapeLogEntry(
      timestamp: DateTime.now(),
      raw: _escapeForDisplay(sequence),
      decoded: sequence,
      category: _categorize(sequence),
      explanation: 'Unhandled sequence',
      isError: false,
    ));
  }

  /// Categorize a raw escape sequence string.
  static String _categorize(String chars) {
    if (chars.isEmpty) return 'unknown';

    // Check for ESC prefix (0x1B).
    if (chars.codeUnitAt(0) == 0x1B) {
      if (chars.length < 2) return 'ESC';

      return switch (chars.codeUnitAt(1)) {
        0x5B => _isAnySgr(chars) ? 'SGR' : 'CSI', // [
        0x5D => 'OSC', // ]
        0x50 => 'DCS', // P
        _ => 'ESC',
      };
    }

    // Single-byte controls (BEL, BS, HT, LF, CR, etc.).
    if (chars.length == 1 && chars.codeUnitAt(0) < 0x20) {
      return 'SBC';
    }

    return 'unknown';
  }

  /// Check if a CSI sequence is an SGR (Select Graphic Rendition) sequence.
  ///
  /// SGR sequences end with 'm': `ESC [ <params> m`
  static bool _isAnySgr(String chars) {
    if (chars.length < 3) return false;
    return chars.endsWith('m') && chars.codeUnitAt(1) == 0x5B;
  }

  /// Decode a raw sequence into a readable representation.
  static String _decodeSequence(String chars) {
    if (chars.isEmpty) return '';

    final buf = StringBuffer();
    for (final codeUnit in chars.runes) {
      if (codeUnit == 0x1B) {
        buf.write('ESC');
      } else if (codeUnit == 0x07) {
        buf.write('<BEL>');
      } else if (codeUnit == 0x08) {
        buf.write('<BS>');
      } else if (codeUnit == 0x09) {
        buf.write('<HT>');
      } else if (codeUnit == 0x0A) {
        buf.write('<LF>');
      } else if (codeUnit == 0x0D) {
        buf.write('<CR>');
      } else if (codeUnit < 0x20) {
        buf.write('<0x${codeUnit.toRadixString(16).padLeft(2, '0')}>');
      } else if (codeUnit == 0x7F) {
        buf.write('<DEL>');
      } else {
        buf.writeCharCode(codeUnit);
      }
    }
    return buf.toString();
  }

  /// Escape raw characters for safe display in JSON output.
  static String _escapeForDisplay(String chars) {
    final buf = StringBuffer();
    for (final codeUnit in chars.runes) {
      if (codeUnit == 0x1B) {
        buf.write(r'\x1b');
      } else if (codeUnit < 0x20) {
        buf.write('\\x${codeUnit.toRadixString(16).padLeft(2, '0')}');
      } else if (codeUnit == 0x7F) {
        buf.write(r'\x7f');
      } else {
        buf.writeCharCode(codeUnit);
      }
    }
    return buf.toString();
  }
}

/// JSON schema for the `escape_log` tool's input parameters.
const escapeLogSchema = <String, dynamic>{
  'type': 'object',
  'properties': {
    'limit': {
      'type': 'integer',
      'description':
          'Maximum number of recent entries to return (default 50, max 500)',
    },
    'category': {
      'type': 'string',
      'description':
          'Filter by category: CSI, OSC, DCS, ESC, SBC, SGR, error, '
              'or "all" (default "all")',
      'enum': ['all', 'CSI', 'OSC', 'DCS', 'ESC', 'SBC', 'SGR', 'error'],
    },
    'errors_only': {
      'type': 'boolean',
      'description': 'Only return entries that were parse errors (default false)',
    },
    'clear': {
      'type': 'boolean',
      'description': 'Clear the log buffer after returning results (default false)',
    },
    'since': {
      'type': 'string',
      'description':
          'Only return entries after this ISO 8601 timestamp '
              '(e.g., "2026-03-27T10:00:00")',
    },
  },
};

/// Handles the `escape_log` tool call.
///
/// Reads from the shared [EscapeLogBuffer] and returns recent escape
/// sequences matching the requested filters.
String handleEscapeLog(EscapeLogBuffer buffer, Map<String, dynamic> args) {
  final limit = (args['limit'] as int?) ?? 50;
  final category = args['category'] as String? ?? 'all';
  final errorsOnly = args['errors_only'] as bool? ?? false;
  final clear = args['clear'] as bool? ?? false;
  final sinceStr = args['since'] as String?;

  DateTime? since;
  if (sinceStr != null) {
    since = DateTime.tryParse(sinceStr);
    if (since == null) {
      return jsonEncode({'error': 'Invalid ISO 8601 timestamp: $sinceStr'});
    }
  }

  // Apply filters.
  var entries = buffer.entries;

  if (since != null) {
    entries = entries.where((e) => e.timestamp.isAfter(since!)).toList();
  }

  if (errorsOnly) {
    entries = entries.where((e) => e.isError).toList();
  }

  if (category != 'all') {
    entries = entries.where((e) => e.category == category).toList();
  }

  // Take the most recent N entries.
  final clampedLimit = limit.clamp(1, 500);
  if (entries.length > clampedLimit) {
    entries = entries.sublist(entries.length - clampedLimit);
  }

  final result = {
    'entries': entries.map((e) => e.toJson()).toList(),
    'count': entries.length,
    'total_in_buffer': buffer.length,
    'capturing': buffer.isCapturing,
  };

  if (clear) {
    buffer.clear();
    result['cleared'] = true;
  }

  return jsonEncode(result);
}
