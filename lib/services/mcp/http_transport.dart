/// Streamable HTTP transport for the MCP DevTools server.
///
/// Implements the [Transport] interface from dart_mcp, backed by a
/// [dart:io HttpServer]. Handles JSON-RPC messages over HTTP POST
/// requests to `/mcp`, plus a GET health endpoint at `/health`.
///
/// Uses JSON response mode (no SSE) — each POST receives a synchronous
/// JSON-RPC response. This matches the simplified local devtools pattern.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/dart_mcp.dart';

/// MCP protocol version advertised in response headers.
const _kProtocolVersion = '2025-06-18';

/// HTTP transport for the MCP server.
///
/// Listens on a configurable localhost port and translates HTTP POST
/// requests into the [Transport.incoming] stream. Responses from the
/// MCP server are buffered per-request and written back as the HTTP
/// response body.
///
/// The transport manages its own [HttpServer] lifecycle — call [start]
/// to bind the port, and [close] to shut down gracefully.
class HttpTransport implements Transport {
  /// Creates an HTTP transport that will listen on [port].
  ///
  /// The server is not started until [start] is called.
  HttpTransport({this.port = 9710});

  /// The localhost port to listen on.
  final int port;

  HttpServer? _server;
  final _incomingController = StreamController<String>();
  final _sseConnections = <HttpResponse>{};

  /// Completer that pairs each incoming request with its HTTP response.
  ///
  /// The MCP server processes the incoming message and calls [send],
  /// which completes the pending response. This ensures the HTTP
  /// response contains the JSON-RPC reply.
  Completer<String>? _pendingResponse;

  bool _closed = false;

  @override
  Stream<String> get incoming => _incomingController.stream;

  @override
  Future<void> send(String message) async {
    if (_closed) {
      throw TransportException('Transport is closed');
    }

    // Complete the pending HTTP response with this message.
    if (_pendingResponse case final completer? when !completer.isCompleted) {
      completer.complete(message);
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;

    for (final sse in _sseConnections) {
      await sse.close();
    }
    _sseConnections.clear();
    await _server?.close(force: true);
    _server = null;
    await _incomingController.close();
  }

  /// Bind the HTTP server and start accepting requests.
  ///
  /// Returns the bound port (useful if port 0 was used for auto-assign).
  Future<int> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);

    _server!.listen(
      _handleRequest,
      onError: (Object error) {
        _incomingController.addError(
          TransportException('HTTP server error', error),
        );
      },
    );

    return _server!.port;
  }

  /// The actual port the server is listening on.
  ///
  /// Only valid after [start] has completed.
  int get boundPort => _server?.port ?? port;

  /// Whether the HTTP server is currently running.
  bool get isRunning => _server != null && !_closed;

  Future<void> _handleRequest(HttpRequest request) async {
    // Add CORS headers for local development tools.
    request.response.headers
      ..set('Access-Control-Allow-Origin', '*')
      ..set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
      ..set(
        'Access-Control-Allow-Headers',
        'Content-Type, Mcp-Protocol-Version, Mcp-Session-Id',
      );

    // Handle CORS preflight.
    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
      return;
    }

    final path = request.uri.path;

    switch ((request.method, path)) {
      case ('GET', '/health'):
        await _handleHealth(request);
      case ('GET', '/mcp'):
        await _handleMcpSse(request);
      case ('POST', '/mcp'):
        await _handleMcpPost(request);
      default:
        request.response.statusCode = HttpStatus.notFound;
        request.response.write('Not found');
        await request.response.close();
    }
  }

  /// Handle GET /mcp — SSE endpoint for server-to-client messages.
  ///
  /// The MCP streamable HTTP spec requires this endpoint. The client
  /// opens a long-lived SSE connection to receive server-initiated
  /// notifications. We keep the connection open until the client
  /// disconnects or the server shuts down.
  Future<void> _handleMcpSse(HttpRequest request) async {
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.set('Content-Type', 'text/event-stream')
      ..headers.set('Cache-Control', 'no-cache')
      ..headers.set('Connection', 'keep-alive')
      ..headers.set('Mcp-Protocol-Version', _kProtocolVersion);

    // Keep the connection alive. We don't send server-initiated
    // notifications for devtools, so just hold the connection open.
    // The client will close it when done.
    _sseConnections.add(request.response);
    request.response.done.whenComplete(() {
      _sseConnections.remove(request.response);
    });
  }

  Future<void> _handleHealth(HttpRequest request) async {
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({
        'status': 'ok',
        'protocol_version': _kProtocolVersion,
        'port': boundPort,
      }));
    await request.response.close();
  }

  Future<void> _handleMcpPost(HttpRequest request) async {
    if (_closed) {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      request.response.write('Server is shutting down');
      await request.response.close();
      return;
    }

    try {
      final body = await utf8.decoder.bind(request).join();

      // Parse to check if this is a JSON-RPC notification (no "id" field).
      // Notifications don't produce responses, so we must not wait for one.
      final json = jsonDecode(body);
      final isNotification = json is Map<String, dynamic> &&
          json.containsKey('method') &&
          !json.containsKey('id');

      if (isNotification) {
        // Feed to the MCP server but respond immediately with 202 Accepted.
        _incomingController.add(body);
        request.response
          ..statusCode = HttpStatus.accepted
          ..headers.set('Mcp-Protocol-Version', _kProtocolVersion);
        await request.response.close();
        return;
      }

      // Set up the response completer before feeding the message.
      _pendingResponse = Completer<String>();

      // Feed the message to the MCP server via the incoming stream.
      _incomingController.add(body);

      // Wait for the MCP server to produce a response via [send].
      final responseBody = await _pendingResponse!.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () => jsonEncode({
          'jsonrpc': '2.0',
          'id': null,
          'error': {
            'code': -32603,
            'message': 'Request timed out',
          },
        }),
      );

      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..headers.set('Mcp-Protocol-Version', _kProtocolVersion)
        ..write(responseBody);
      await request.response.close();
    } on Exception catch (e) {
      request.response
        ..statusCode = HttpStatus.internalServerError
        ..write('Internal server error: $e');
      await request.response.close();
    } finally {
      _pendingResponse = null;
    }
  }
}
