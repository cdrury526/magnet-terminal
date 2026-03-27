library;

import 'dart:convert';
import 'dart:typed_data';

enum HandshakeTraceDirection { ptyOutput, terminalInput }

class HandshakeTraceEntry {
  const HandshakeTraceEntry({
    required this.timestamp,
    required this.direction,
    required this.byteCount,
    required this.hex,
    required this.preview,
    required this.containsProbeTraffic,
    this.responseKind,
    this.overrideApplied = false,
    this.originalHex,
    this.originalPreview,
  });

  final DateTime timestamp;
  final HandshakeTraceDirection direction;
  final int byteCount;
  final String hex;
  final String preview;
  final bool containsProbeTraffic;
  final String? responseKind;
  final bool overrideApplied;
  final String? originalHex;
  final String? originalPreview;

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'direction': switch (direction) {
      HandshakeTraceDirection.ptyOutput => 'pty_output',
      HandshakeTraceDirection.terminalInput => 'terminal_input',
    },
    'byte_count': byteCount,
    'hex': hex,
    'preview': preview,
    'contains_probe_traffic': containsProbeTraffic,
    if (responseKind != null) 'response_kind': responseKind,
    if (overrideApplied) 'override_applied': true,
    if (originalHex != null) 'original_hex': originalHex,
    if (originalPreview != null) 'original_preview': originalPreview,
  };
}

class HandshakeRecorder {
  HandshakeRecorder({this.capacity = 400});

  final int capacity;
  final List<HandshakeTraceEntry> _entries = [];

  bool isRecording = false;
  DateTime? startedAt;
  DateTime? stoppedAt;
  String? label;

  List<HandshakeTraceEntry> get entries => List.unmodifiable(_entries);
  int get length => _entries.length;

  void start({String? label, bool clear = true}) {
    if (clear) {
      _entries.clear();
    }
    isRecording = true;
    startedAt = DateTime.now();
    stoppedAt = null;
    this.label = label;
  }

  void stop() {
    isRecording = false;
    stoppedAt = DateTime.now();
  }

  void clear() {
    _entries.clear();
  }

  void recordPtyOutput(Uint8List bytes) {
    _addEntry(direction: HandshakeTraceDirection.ptyOutput, bytes: bytes);
  }

  void recordTerminalInput(
    Uint8List effectiveBytes, {
    String? responseKind,
    Uint8List? originalBytes,
  }) {
    _addEntry(
      direction: HandshakeTraceDirection.terminalInput,
      bytes: effectiveBytes,
      responseKind: responseKind,
      originalBytes: originalBytes,
    );
  }

  void _addEntry({
    required HandshakeTraceDirection direction,
    required Uint8List bytes,
    String? responseKind,
    Uint8List? originalBytes,
  }) {
    if (!isRecording || bytes.isEmpty) {
      return;
    }

    final preview = formatBytesForDisplay(bytes);
    final originalPreview = originalBytes == null
        ? null
        : formatBytesForDisplay(originalBytes);

    if (_entries.length >= capacity) {
      _entries.removeAt(0);
    }

    _entries.add(
      HandshakeTraceEntry(
        timestamp: DateTime.now(),
        direction: direction,
        byteCount: bytes.length,
        hex: bytesToHex(bytes),
        preview: preview,
        containsProbeTraffic:
            containsProbeTraffic(preview) ||
            (originalPreview != null && containsProbeTraffic(originalPreview)),
        responseKind: responseKind,
        overrideApplied:
            originalBytes != null &&
            !const ListEquality().equals(bytes, originalBytes),
        originalHex: originalBytes == null ? null : bytesToHex(originalBytes),
        originalPreview: originalPreview,
      ),
    );
  }

  Map<String, dynamic> statusJson() => {
    'recording': isRecording,
    'capacity': capacity,
    'entries': _entries.length,
    if (startedAt != null) 'started_at': startedAt!.toIso8601String(),
    if (stoppedAt != null) 'stopped_at': stoppedAt!.toIso8601String(),
    if (label != null) 'label': label,
  };
}

class ProbeOverrideState {
  String? xtVersionResponse;
  String? da1Response;
  String? da2Response;
  String? da3Response;
  String? xtGetTCapResponse;
  DateTime lastChanged = DateTime.now();

  String? apply(String data) {
    if (_isXtVersionResponse(data)) {
      return xtVersionResponse;
    }
    if (_isDa1Response(data)) {
      return da1Response;
    }
    if (_isDa2Response(data)) {
      return da2Response;
    }
    if (_isDa3Response(data)) {
      return da3Response;
    }
    if (_isXtGetTCapResponse(data)) {
      return xtGetTCapResponse;
    }
    return null;
  }

  String? classify(String data) {
    if (_isXtVersionResponse(data)) return 'xtversion';
    if (_isDa1Response(data)) return 'da1';
    if (_isDa2Response(data)) return 'da2';
    if (_isDa3Response(data)) return 'da3';
    if (_isXtGetTCapResponse(data)) return 'xtgettcap';
    return null;
  }

  void setOverride(String probe, String response) {
    switch (probe) {
      case 'xtversion':
        xtVersionResponse = response;
      case 'da1':
        da1Response = response;
      case 'da2':
        da2Response = response;
      case 'da3':
        da3Response = response;
      case 'xtgettcap':
        xtGetTCapResponse = response;
      default:
        throw ArgumentError.value(probe, 'probe', 'Unknown probe');
    }
    lastChanged = DateTime.now();
  }

  void clearOverride(String probe) {
    switch (probe) {
      case 'xtversion':
        xtVersionResponse = null;
      case 'da1':
        da1Response = null;
      case 'da2':
        da2Response = null;
      case 'da3':
        da3Response = null;
      case 'xtgettcap':
        xtGetTCapResponse = null;
      default:
        throw ArgumentError.value(probe, 'probe', 'Unknown probe');
    }
    lastChanged = DateTime.now();
  }

  void reset() {
    xtVersionResponse = null;
    da1Response = null;
    da2Response = null;
    da3Response = null;
    xtGetTCapResponse = null;
    lastChanged = DateTime.now();
  }

  Map<String, dynamic> toJson() => {
    'last_changed': lastChanged.toIso8601String(),
    'overrides': {
      'xtversion': xtVersionResponse == null
          ? null
          : formatBytesForDisplay(
              Uint8List.fromList(latin1.encode(xtVersionResponse!)),
            ),
      'da1': da1Response == null
          ? null
          : formatBytesForDisplay(
              Uint8List.fromList(latin1.encode(da1Response!)),
            ),
      'da2': da2Response == null
          ? null
          : formatBytesForDisplay(
              Uint8List.fromList(latin1.encode(da2Response!)),
            ),
      'da3': da3Response == null
          ? null
          : formatBytesForDisplay(
              Uint8List.fromList(latin1.encode(da3Response!)),
            ),
      'xtgettcap': xtGetTCapResponse == null
          ? null
          : formatBytesForDisplay(
              Uint8List.fromList(latin1.encode(xtGetTCapResponse!)),
            ),
    },
  };

  static bool _isXtVersionResponse(String data) =>
      data.startsWith('\x1bP>|') && data.endsWith('\x1b\\');

  static bool _isDa1Response(String data) =>
      data.startsWith('\x1b[?') && data.endsWith('c');

  static bool _isDa2Response(String data) =>
      data.startsWith('\x1b[>') && data.endsWith('c');

  static bool _isDa3Response(String data) =>
      data.startsWith('\x1bP!|') && data.endsWith('\x1b\\');

  static bool _isXtGetTCapResponse(String data) =>
      data.startsWith('\x1bP1+r') && data.endsWith('\x1b\\');
}

String bytesToHex(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join(' ');

String formatBytesForDisplay(List<int> bytes) {
  final buf = StringBuffer();
  for (final byte in bytes) {
    switch (byte) {
      case 0x1B:
        buf.write(r'\x1b');
      case 0x07:
        buf.write(r'\x07');
      case 0x08:
        buf.write(r'\x08');
      case 0x09:
        buf.write(r'\t');
      case 0x0A:
        buf.write(r'\n');
      case 0x0D:
        buf.write(r'\r');
      default:
        if (byte < 0x20 || byte == 0x7F) {
          buf.write('\\x${byte.toRadixString(16).padLeft(2, '0')}');
        } else {
          buf.writeCharCode(byte);
        }
    }
  }
  return buf.toString();
}

bool containsProbeTraffic(String preview) {
  return preview.contains(r'\x1b[c') ||
      preview.contains(r'\x1b[>0q') ||
      preview.contains(r'\x1b[>c') ||
      preview.contains(r'\x1bP>|') ||
      preview.contains(r'\x1bP!|') ||
      preview.contains(r'\x1bP1+r') ||
      preview.contains(r'\x1bP+q');
}

class ListEquality {
  const ListEquality();

  bool equals(List<int> a, List<int> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
