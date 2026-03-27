/// MCP DevTools server — runs in-process for terminal introspection.
///
/// Built with the dart_mcp SDK's [FastMCP] class. Exposes tools for:
/// - Cell inspection (`cell_inspect`, `read_screen`)
/// - Cursor state queries (`cursor_state`, `buffer_state`)
/// - Escape sequence capture (`escape_log`)
/// - Escape sequence injection (`write_sequence`)
/// - Runtime debug control (`toggle_debug`)
///
/// Served over streamable HTTP on localhost. Claude Code connects to
/// `http://localhost:<port>/mcp` via POST with JSON-RPC 2.0 messages.
///
/// The server starts automatically on app launch and stops on dispose.
/// It is non-blocking — the HTTP server runs on async I/O and never
/// blocks the Flutter UI thread.
library;

import 'package:dart_mcp/dart_mcp.dart';
import 'package:flutter/foundation.dart';

import 'mcp/escape_logger_tool.dart';
import 'mcp/http_transport.dart';
import 'mcp/toggle_debug_tool.dart';
import 'mcp/tool_registry.dart';

/// The in-process MCP DevTools server.
///
/// Manages the lifecycle of the HTTP transport and [FastMCP] server,
/// and provides a [TerminalProvider] callback so tools always operate
/// on the currently active terminal.
///
/// Usage:
/// ```dart
/// final server = DevtoolsServer(
///   terminalProvider: () => tabManager.activeSession.terminal,
///   ptyWriterProvider: () => tabManager.activeSession.writeToPty,
///   sessionProvider: () => tabManager.activeSession,
/// );
/// await server.start();
/// // ... app runs ...
/// await server.stop();
/// ```
class DevtoolsServer {
  /// Creates a devtools server.
  ///
  /// [terminalProvider] is called on every tool invocation to get the
  /// terminal to inspect. It should return `null` if no terminal is
  /// available.
  ///
  /// [ptyWriterProvider] is called by the `write_sequence` tool to get
  /// a function that writes to the active session's PTY stdin. It may
  /// return `null` if no PTY is running.
  ///
  /// [port] is the localhost port to listen on (default 9710).
  DevtoolsServer({
    required TerminalProvider terminalProvider,
    PtyWriterProvider? ptyWriterProvider,
    SessionProvider? sessionProvider,
    this.port = 9730,
  }) : _terminalProvider = terminalProvider,
       _ptyWriterProvider = ptyWriterProvider,
       _sessionProvider = sessionProvider;

  /// The localhost port the server listens on.
  final int port;

  final TerminalProvider _terminalProvider;
  final PtyWriterProvider? _ptyWriterProvider;
  final SessionProvider? _sessionProvider;

  HttpTransport? _transport;
  FastMCP? _mcp;

  /// Shared escape sequence log buffer.
  ///
  /// Exposed so the app can wire [TerminalDebugConfig] callbacks
  /// to feed captured sequences into the buffer.
  final EscapeLogBuffer escapeBuffer = EscapeLogBuffer();

  /// Shared runtime debug state.
  final DebugState debugState = DebugState();

  /// Whether the server is currently running and accepting connections.
  bool get isRunning => _transport?.isRunning ?? false;

  /// The actual port the server is bound to.
  ///
  /// Only valid when [isRunning] is `true`.
  int get boundPort => _transport?.boundPort ?? port;

  /// Start the MCP server.
  ///
  /// Binds the HTTP server to localhost on [port], registers all
  /// tools, and begins accepting MCP requests.
  ///
  /// Safe to call multiple times — subsequent calls are no-ops if
  /// the server is already running.
  Future<void> start() async {
    if (isRunning) return;

    try {
      _transport = HttpTransport(port: port);

      _mcp = FastMCP('magnet-devtools', transport: _transport);

      // Register all tools (inspection + debug).
      registerDevtools(
        _mcp!,
        _terminalProvider,
        escapeBuffer: escapeBuffer,
        debugState: debugState,
        ptyWriterProvider: _ptyWriterProvider,
        sessionProvider: _sessionProvider,
      );

      // Start the HTTP server.
      final boundPort = await _transport!.start();
      debugPrint(
        'DevtoolsServer: MCP server listening on '
        'http://localhost:$boundPort/mcp',
      );
    } on Exception catch (e) {
      debugPrint('DevtoolsServer: failed to start: $e');
      await stop();
      rethrow;
    }
  }

  /// Stop the MCP server and release all resources.
  ///
  /// Safe to call multiple times — subsequent calls are no-ops.
  Future<void> stop() async {
    final mcp = _mcp;
    final transport = _transport;

    _mcp = null;
    _transport = null;

    if (mcp != null) {
      try {
        await mcp.close();
      } on Exception catch (e) {
        debugPrint('DevtoolsServer: error closing MCP server: $e');
      }
    }

    if (transport != null) {
      try {
        await transport.close();
      } on Exception catch (e) {
        debugPrint('DevtoolsServer: error closing transport: $e');
      }
    }

    debugPrint('DevtoolsServer: stopped');
  }
}
