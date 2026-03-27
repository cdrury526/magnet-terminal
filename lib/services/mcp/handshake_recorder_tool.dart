library;

import 'dart:convert';

import 'package:magnet_terminal/terminal/terminal_session.dart';

const handshakeRecorderSchema = <String, dynamic>{
  'type': 'object',
  'properties': {
    'action': {
      'type': 'string',
      'description':
          'What to do: "status" (default), "start", "stop", or "clear".',
      'enum': ['status', 'start', 'stop', 'clear'],
    },
    'label': {
      'type': 'string',
      'description': 'Optional label for this capture session.',
    },
    'clear_on_start': {
      'type': 'boolean',
      'description': 'When starting, clear prior entries first (default true).',
    },
    'limit': {
      'type': 'integer',
      'description':
          'Maximum number of entries to return (default 100, max 400).',
    },
    'direction': {
      'type': 'string',
      'description':
          'Filter results to "all", "pty_output", or "terminal_input".',
      'enum': ['all', 'pty_output', 'terminal_input'],
    },
    'probes_only': {
      'type': 'boolean',
      'description':
          'Only include entries containing capability negotiation traffic.',
    },
  },
};

String handleHandshakeRecorder(
  TerminalSession session,
  Map<String, dynamic> args,
) {
  final action = args['action'] as String? ?? 'status';
  final label = args['label'] as String?;
  final clearOnStart = args['clear_on_start'] as bool? ?? true;
  final direction = args['direction'] as String? ?? 'all';
  final probesOnly = args['probes_only'] as bool? ?? false;
  final limit = ((args['limit'] as int?) ?? 100).clamp(1, 400);

  switch (action) {
    case 'start':
      session.handshakeRecorder.start(label: label, clear: clearOnStart);
      break;
    case 'stop':
      session.handshakeRecorder.stop();
      break;
    case 'clear':
      session.handshakeRecorder.clear();
      break;
    case 'status':
      break;
    default:
      return jsonEncode({'error': 'Unknown action: $action'});
  }

  var entries = session.handshakeRecorder.entries;
  if (direction != 'all') {
    entries = entries.where((entry) {
      return switch (direction) {
        'pty_output' => entry.direction.name == 'ptyOutput',
        'terminal_input' => entry.direction.name == 'terminalInput',
        _ => true,
      };
    }).toList();
  }

  if (probesOnly) {
    entries = entries.where((entry) => entry.containsProbeTraffic).toList();
  }

  if (entries.length > limit) {
    entries = entries.sublist(entries.length - limit);
  }

  return jsonEncode({
    if (action == 'start') 'message': 'Handshake recording started',
    if (action == 'stop') 'message': 'Handshake recording stopped',
    if (action == 'clear') 'message': 'Handshake recording cleared',
    'recorder': session.handshakeRecorder.statusJson(),
    'entries': entries.map((entry) => entry.toJson()).toList(),
    'count': entries.length,
  });
}
