library;

import 'dart:convert';

import 'package:magnet_terminal/terminal/terminal_session.dart';

const probeOverrideSchema = <String, dynamic>{
  'type': 'object',
  'properties': {
    'action': {
      'type': 'string',
      'description':
          'What to do: "status" (default), "set", "clear", or "reset".',
      'enum': ['status', 'set', 'clear', 'reset'],
    },
    'probe': {
      'type': 'string',
      'description':
          'Probe response to override: xtversion, da1, da2, da3, xtgettcap.',
      'enum': ['xtversion', 'da1', 'da2', 'da3', 'xtgettcap'],
    },
    'response': {
      'type': 'string',
      'description':
          'Replacement response using C-style escapes such as \\x1b, \\r, \\n.',
    },
  },
};

String handleProbeOverride(TerminalSession session, Map<String, dynamic> args) {
  final action = args['action'] as String? ?? 'status';
  final probe = args['probe'] as String?;

  switch (action) {
    case 'status':
      break;
    case 'set':
      final response = args['response'] as String?;
      if (probe == null || probe.isEmpty) {
        return jsonEncode({'error': 'probe is required for action "set"'});
      }
      if (response == null) {
        return jsonEncode({'error': 'response is required for action "set"'});
      }
      session.probeOverrides.setOverride(probe, _parseEscapeNotation(response));
      break;
    case 'clear':
      if (probe == null || probe.isEmpty) {
        return jsonEncode({'error': 'probe is required for action "clear"'});
      }
      session.probeOverrides.clearOverride(probe);
      break;
    case 'reset':
      session.probeOverrides.reset();
      break;
    default:
      return jsonEncode({'error': 'Unknown action: $action'});
  }

  return jsonEncode({
    if (action == 'set') 'message': 'Probe override updated',
    if (action == 'clear') 'message': 'Probe override cleared',
    if (action == 'reset') 'message': 'All probe overrides cleared',
    'probe_overrides': session.probeOverrides.toJson(),
  });
}

String _parseEscapeNotation(String input) {
  final buf = StringBuffer();
  var i = 0;

  while (i < input.length) {
    if (input[i] == r'\' && i + 1 < input.length) {
      switch (input[i + 1]) {
        case 'x' || 'X':
          if (i + 3 < input.length) {
            final hex = input.substring(i + 2, i + 4);
            final value = int.tryParse(hex, radix: 16);
            if (value != null) {
              buf.writeCharCode(value);
              i += 4;
              continue;
            }
          }
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
