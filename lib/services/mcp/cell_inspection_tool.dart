/// MCP tool for inspecting terminal cell contents and attributes.
///
/// Provides `cell_inspect` — reads cell content, foreground/background
/// colors, and text attributes (bold, italic, underline, etc.) at a
/// single cell or rectangular region of the terminal buffer.
///
/// Also provides `read_screen` — reads the full visible screen content
/// as plain text lines, useful for getting a quick snapshot of what
/// the terminal is displaying.
///
/// All operations are read-only and never mutate terminal state.
library;

import 'dart:convert';

import 'package:dart_xterm/dart_xterm.dart';

/// JSON schema for the `cell_inspect` tool's input parameters.
const cellInspectSchema = <String, dynamic>{
  'type': 'object',
  'properties': {
    'row': {
      'type': 'integer',
      'description': 'Row index (0-based, relative to visible viewport)',
    },
    'col': {
      'type': 'integer',
      'description': 'Column index (0-based)',
    },
    'end_row': {
      'type': 'integer',
      'description':
          'End row for rectangular region (inclusive, omit for single cell)',
    },
    'end_col': {
      'type': 'integer',
      'description':
          'End column for rectangular region (inclusive, omit for single cell)',
    },
  },
  'required': ['row', 'col'],
};

/// JSON schema for the `read_screen` tool's input parameters.
const readScreenSchema = <String, dynamic>{
  'type': 'object',
  'properties': {
    'start_row': {
      'type': 'integer',
      'description':
          'First row to read (0-based, default 0). Negative values index '
              'from scrollback.',
    },
    'end_row': {
      'type': 'integer',
      'description':
          'Last row to read (inclusive, default: last visible row)',
    },
    'trim': {
      'type': 'boolean',
      'description': 'Trim trailing whitespace from each line (default true)',
    },
  },
};

/// Handles the `cell_inspect` tool call.
///
/// Reads one or more cells from the active terminal buffer and returns
/// a JSON object describing each cell's character, colors, and attributes.
String handleCellInspect(Terminal terminal, Map<String, dynamic> args) {
  final row = args['row'] as int;
  final col = args['col'] as int;
  final endRow = args['end_row'] as int? ?? row;
  final endCol = args['end_col'] as int? ?? col;

  final buffer = terminal.buffer;
  final lines = buffer.lines;
  final viewHeight = terminal.viewHeight;

  // Validate bounds.
  if (row < 0 || row >= viewHeight) {
    return jsonEncode({'error': 'row $row out of range [0, $viewHeight)'});
  }
  if (endRow < row || endRow >= viewHeight) {
    return jsonEncode(
      {'error': 'end_row $endRow out of range [$row, $viewHeight)'},
    );
  }

  final cells = <Map<String, dynamic>>[];
  final cellData = CellData.empty();
  final scrollBack = buffer.scrollBack;

  for (var r = row; r <= endRow; r++) {
    final absoluteRow = scrollBack + r;
    if (absoluteRow < 0 || absoluteRow >= lines.length) continue;

    final line = lines[absoluteRow];
    final maxCol =
        endCol < line.length ? endCol : line.length - 1;

    for (var c = col; c <= maxCol; c++) {
      if (c < 0 || c >= line.length) continue;

      line.getCellData(c, cellData);

      cells.add(_describeCellData(r, c, cellData));
    }
  }

  if (cells.length == 1) {
    return jsonEncode(cells.first);
  }
  return jsonEncode({'cells': cells, 'count': cells.length});
}

/// Handles the `read_screen` tool call.
///
/// Returns visible screen content as an array of text lines.
String handleReadScreen(Terminal terminal, Map<String, dynamic> args) {
  final startRow = args['start_row'] as int? ?? 0;
  final trim = args['trim'] as bool? ?? true;
  final viewHeight = terminal.viewHeight;
  final endRow = args['end_row'] as int? ?? (viewHeight - 1);

  final buffer = terminal.buffer;
  final lines = buffer.lines;
  final scrollBack = buffer.scrollBack;
  final result = <String>[];

  for (var r = startRow; r <= endRow; r++) {
    final absoluteRow = scrollBack + r;
    if (absoluteRow < 0 || absoluteRow >= lines.length) {
      result.add('');
      continue;
    }

    final line = lines[absoluteRow];
    var text = line.getText();
    if (trim) text = text.trimRight();
    result.add(text);
  }

  return jsonEncode({
    'lines': result,
    'row_range': [startRow, endRow],
    'dimensions': {
      'columns': terminal.viewWidth,
      'rows': viewHeight,
    },
  });
}

/// Builds a description map for a single cell.
Map<String, dynamic> _describeCellData(int row, int col, CellData data) {
  final codePoint = data.content & CellContent.codepointMask;
  final width = data.content >> CellContent.widthShift;
  final char = codePoint > 0 ? String.fromCharCode(codePoint) : '';

  return {
    'row': row,
    'col': col,
    'char': char,
    'code_point': codePoint,
    'width': width,
    'foreground': _describeColor(data.foreground),
    'background': _describeColor(data.background),
    'attributes': _describeAttributes(data.flags),
  };
}

/// Decodes a packed color integer into a human-readable map.
Map<String, dynamic> _describeColor(int packed) {
  final colorType = packed & CellColor.typeMask;
  final value = packed & CellColor.valueMask;

  return switch (colorType) {
    CellColor.normal => {'type': 'default'},
    CellColor.named => {'type': 'named', 'index': value},
    CellColor.palette => {'type': 'palette', 'index': value},
    CellColor.rgb => {
      'type': 'rgb',
      'r': (value >> 16) & 0xFF,
      'g': (value >> 8) & 0xFF,
      'b': value & 0xFF,
      'hex': '#${value.toRadixString(16).padLeft(6, '0')}',
    },
    _ => {'type': 'unknown', 'raw': packed},
  };
}

/// Decodes packed attribute flags into a list of active attribute names.
Map<String, dynamic> _describeAttributes(int flags) {
  return {
    'bold': (flags & CellAttr.bold) != 0,
    'faint': (flags & CellAttr.faint) != 0,
    'italic': (flags & CellAttr.italic) != 0,
    'underline': (flags & CellAttr.underline) != 0,
    'blink': (flags & CellAttr.blink) != 0,
    'inverse': (flags & CellAttr.inverse) != 0,
    'invisible': (flags & CellAttr.invisible) != 0,
    'strikethrough': (flags & CellAttr.strikethrough) != 0,
    'raw': flags,
  };
}
