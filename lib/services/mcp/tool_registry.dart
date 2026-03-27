/// Tool registry — registers all MCP devtools tools with a [FastMCP]
/// server instance.
///
/// Each tool is bound to a live [Terminal] reference provided by a
/// [TerminalProvider] callback. This indirection allows the active
/// terminal to change (e.g., when tabs switch) without re-registering
/// tools.
///
/// Inspection tools are read-only. The only write tool is `write_sequence`,
/// which injects escape sequences for testing purposes.
library;

import 'package:dart_mcp/dart_mcp.dart';
import 'package:dart_xterm/dart_xterm.dart';

import 'buffer_state_tool.dart';
import 'cell_inspection_tool.dart';
import 'escape_logger_tool.dart';
import 'toggle_debug_tool.dart';
import 'write_sequence_tool.dart';

/// Callback that returns the currently active [Terminal].
///
/// If no terminal is available (e.g., app is shutting down), returns
/// `null` and the tool will report an error.
typedef TerminalProvider = Terminal? Function();

/// Callback that writes raw data to the active session's PTY stdin.
///
/// Returns `null` if no session is available (e.g., process exited).
typedef PtyWriterProvider = PtyWriter? Function();

/// Registers all devtools tools on [mcp].
///
/// The [terminalProvider] is called on every tool invocation to get the
/// current terminal. This supports multi-tab scenarios where the active
/// terminal changes.
///
/// The [escapeBuffer] and [debugState] are shared state objects that
/// persist for the lifetime of the devtools server.
///
/// The [ptyWriterProvider] supplies a callback to write to the active
/// session's PTY. It is only needed by the `write_sequence` tool.
void registerDevtools(
  FastMCP mcp,
  TerminalProvider terminalProvider, {
  EscapeLogBuffer? escapeBuffer,
  DebugState? debugState,
  PtyWriterProvider? ptyWriterProvider,
}) {
  final buffer = escapeBuffer ?? EscapeLogBuffer();
  final debug = debugState ?? DebugState();
  // -----------------------------------------------------------------------
  //  cell_inspect — read cell content and attributes
  // -----------------------------------------------------------------------
  mcp.registerTool(
    name: 'cell_inspect',
    description:
        'Inspect terminal cell content, colors, and attributes at a '
        'position or rectangular region. Returns character, foreground/'
        'background color (with type: default/named/palette/rgb), and '
        'text attributes (bold, italic, underline, etc.).',
    inputSchema: cellInspectSchema,
    handler: (args) {
      final terminal = terminalProvider();
      if (terminal == null) return 'Error: no active terminal';
      return handleCellInspect(terminal, args);
    },
  );

  // -----------------------------------------------------------------------
  //  read_screen — read visible screen content as text
  // -----------------------------------------------------------------------
  mcp.registerTool(
    name: 'read_screen',
    description:
        'Read the visible terminal screen content as an array of text '
        'lines. Optionally specify a row range. Useful for getting a '
        'quick snapshot of what the terminal is displaying.',
    inputSchema: readScreenSchema,
    handler: (args) {
      final terminal = terminalProvider();
      if (terminal == null) return 'Error: no active terminal';
      return handleReadScreen(terminal, args);
    },
  );

  // -----------------------------------------------------------------------
  //  cursor_state — cursor position, style, visibility
  // -----------------------------------------------------------------------
  mcp.registerTool(
    name: 'cursor_state',
    description:
        'Report cursor position (x, y, absolute_y), style attributes '
        '(bold, italic, etc.), visibility/blink state, active buffer '
        '(main vs alt), scrollback size, and terminal dimensions.',
    inputSchema: cursorStateSchema,
    handler: (args) {
      final terminal = terminalProvider();
      if (terminal == null) return 'Error: no active terminal';
      return handleCursorState(terminal, args);
    },
  );

  // -----------------------------------------------------------------------
  //  buffer_state — DEC modes, mouse state, terminal config
  // -----------------------------------------------------------------------
  mcp.registerTool(
    name: 'buffer_state',
    description:
        'Report terminal buffer state: dimensions, active buffer, '
        'scrollback size, mouse tracking mode, and all active DEC '
        'private modes (DECAWM, DECOM, DECCKM, bracketed paste, etc.).',
    inputSchema: bufferStateSchema,
    handler: (args) {
      final terminal = terminalProvider();
      if (terminal == null) return 'Error: no active terminal';
      return handleBufferState(terminal, args);
    },
  );

  // -----------------------------------------------------------------------
  //  escape_log — capture and inspect recent escape sequences
  // -----------------------------------------------------------------------
  mcp.registerTool(
    name: 'escape_log',
    description:
        'View recently captured escape sequences with timestamps, decoded '
        'names (CSI, OSC, DCS, SGR, etc.), and raw bytes. Supports '
        'filtering by category and time range. The ring buffer retains '
        'the most recent ${buffer.capacity} entries.',
    inputSchema: escapeLogSchema,
    handler: (args) => handleEscapeLog(buffer, args),
  );

  // -----------------------------------------------------------------------
  //  write_sequence — inject escape sequences into the terminal
  // -----------------------------------------------------------------------
  mcp.registerTool(
    name: 'write_sequence',
    description:
        'Inject a raw escape sequence into the terminal for testing. '
        'Can write to the terminal buffer (as if the PTY sent it) or '
        'to the PTY stdin (as if the user typed it). Supports C-style '
        r'escape notation: \x1b for ESC, \x07 for BEL, \n, \r, \t, etc.',
    inputSchema: writeSequenceSchema,
    handler: (args) {
      final terminal = terminalProvider();
      if (terminal == null) return 'Error: no active terminal';
      final ptyWriter = ptyWriterProvider?.call();
      return handleWriteSequence(terminal, ptyWriter, args);
    },
  );

  // -----------------------------------------------------------------------
  //  toggle_debug — enable/disable debug features at runtime
  // -----------------------------------------------------------------------
  mcp.registerTool(
    name: 'toggle_debug',
    description:
        'Toggle debug features at runtime: enable/disable escape sequence '
        'capture, verbose logging, inspect terminal environment variables, '
        'or reset debug state. Use "env" action to see TERM, COLORTERM, '
        'TERM_PROGRAM, and other variables that affect CLI app behavior.',
    inputSchema: toggleDebugSchema,
    handler: (args) => handleToggleDebug(debug, buffer, args),
  );
}
