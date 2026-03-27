/// Streamable HTTP transport for the MCP DevTools server.
///
/// Implements the [Transport] interface from dart_mcp, backed by a
/// [dart:io HttpServer]. Handles JSON-RPC messages over HTTP POST
/// requests to `/mcp`, plus a GET health endpoint at `/health`.
///
/// This transport keeps request/response correlation by JSON-RPC id and
/// exposes a minimal session model via the `Mcp-Session-Id` header so
/// clients can keep a stable logical connection across multiple HTTP
/// requests and optional SSE listeners.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dart_mcp/dart_mcp.dart';
import 'package:flutter/foundation.dart';

/// MCP protocol version advertised in response headers.
const _kProtocolVersion = '2025-06-18';

/// HTTP transport for the MCP server.
///
/// Listens on a configurable localhost port and translates HTTP POST
/// requests into the [Transport.incoming] stream. Responses from the
/// MCP server are matched back to the originating HTTP request by
/// JSON-RPC request id.
///
/// The transport manages its own [HttpServer] lifecycle. Call [start]
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
  final _pendingResponses = <String, Completer<String>>{};
  final _sseConnections = <_SseConnection>{};

  String? _sessionId;
  bool _closed = false;

  @override
  Stream<String> get incoming => _incomingController.stream;

  @override
  Future<void> send(String message) async {
    if (_closed) {
      throw TransportException('Transport is closed');
    }

    debugPrint('HttpTransport.send: $message');

    final responseId = _extractMessageId(message);
    if (responseId != null) {
      final completer = _pendingResponses.remove(responseId);
      if (completer != null && !completer.isCompleted) {
        completer.complete(message);
      }
      return;
    }

    await _broadcastSseMessage(message);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;

    for (final completer in _pendingResponses.values) {
      if (!completer.isCompleted) {
        completer.completeError(
          const TransportException('Transport closed before response arrived'),
        );
      }
    }
    _pendingResponses.clear();

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
  /// Returns the bound port, useful if port 0 was used for auto-assign.
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
    request.response.headers
      ..set('Access-Control-Allow-Origin', '*')
      ..set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
      ..set(
        'Access-Control-Allow-Headers',
        'Content-Type, Accept, Mcp-Protocol-Version, Mcp-Session-Id',
      );

    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
      return;
    }

    switch ((request.method, request.uri.path)) {
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
  Future<void> _handleMcpSse(HttpRequest request) async {
    final requestSessionId = request.headers.value('Mcp-Session-Id');
    if (_sessionId != null &&
        requestSessionId != null &&
        requestSessionId != _sessionId) {
      request.response.statusCode = HttpStatus.notFound;
      request.response.write('Unknown MCP session');
      await request.response.close();
      return;
    }

    request.response
      ..statusCode = HttpStatus.ok
      ..bufferOutput = false
      ..headers.set('Content-Type', 'text/event-stream')
      ..headers.set('Cache-Control', 'no-cache')
      ..headers.set('Connection', 'keep-alive')
      ..headers.set('Mcp-Protocol-Version', _kProtocolVersion);

    if (_sessionId case final sessionId?) {
      request.response.headers.set('Mcp-Session-Id', sessionId);
    }

    final connection = _SseConnection(request.response);
    _sseConnections.add(connection);
    await connection.open();

    request.response.done.whenComplete(() async {
      _sseConnections.remove(connection);
      await connection.close();
    });
  }

  Future<void> _handleHealth(HttpRequest request) async {
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(
        jsonEncode({
          'status': 'ok',
          'protocol_version': _kProtocolVersion,
          'port': boundPort,
          if (_sessionId != null) 'session_id': _sessionId,
        }),
      );
    await request.response.close();
  }

  Future<void> _handleMcpPost(HttpRequest request) async {
    if (_closed) {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      request.response.write('Server is shutting down');
      await request.response.close();
      return;
    }

    String? requestKey;

    try {
      final body = await utf8.decoder.bind(request).join();
      final json = jsonDecode(body);

      if (json is! Map<String, dynamic>) {
        request.response.statusCode = HttpStatus.badRequest;
        request.response.write('Expected a JSON-RPC object');
        await request.response.close();
        return;
      }

      final method = json['method'];
      final requestId = json['id'];
      final requestSessionId = request.headers.value('Mcp-Session-Id');
      final isNotification =
          json.containsKey('method') && !json.containsKey('id');

      debugPrint(
        'HttpTransport._handleMcpPost: method=$method id=$requestId '
        'notification=$isNotification session=$requestSessionId',
      );

      if (_sessionId != null &&
          requestSessionId != null &&
          requestSessionId != _sessionId) {
        request.response.statusCode = HttpStatus.notFound;
        request.response.write('Unknown MCP session');
        await request.response.close();
        return;
      }

      if (method == 'initialize' && requestId != null) {
        _sessionId ??= _generateSessionId();
      }

      if (isNotification) {
        _incomingController.add(body);
        request.response
          ..statusCode = HttpStatus.accepted
          ..headers.set('Mcp-Protocol-Version', _kProtocolVersion);
        if (_sessionId case final sessionId?) {
          request.response.headers.set('Mcp-Session-Id', sessionId);
        }
        await request.response.close();
        return;
      }

      requestKey = _requestKey(requestId);
      if (requestKey == null) {
        request.response.statusCode = HttpStatus.badRequest;
        request.response.write('JSON-RPC request is missing a valid id');
        await request.response.close();
        return;
      }

      final responseCompleter = Completer<String>();
      _pendingResponses[requestKey] = responseCompleter;
      _incomingController.add(body);
      debugPrint(
        'HttpTransport._handleMcpPost: queued request key=$requestKey '
        'pending=${_pendingResponses.length}',
      );

      final responseBody = await responseCompleter.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () => jsonEncode({
          'jsonrpc': '2.0',
          'id': requestId,
          'error': {'code': -32603, 'message': 'Request timed out'},
        }),
      );

      debugPrint(
        'HttpTransport._handleMcpPost: response ready key=$requestKey '
        'body=$responseBody',
      );

      if (_sessionId case final sessionId?) {
        request.response.headers.set('Mcp-Session-Id', sessionId);
      }
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..headers.set('Mcp-Protocol-Version', _kProtocolVersion)
        ..write(responseBody);
      await request.response.close();
    } on Exception catch (e) {
      try {
        request.response.statusCode = HttpStatus.internalServerError;
      } on StateError {
        // Headers were already committed. Fall through and append the error.
      }
      request.response.write('Internal server error: $e');
      await request.response.close();
    } finally {
      if (requestKey != null) {
        _pendingResponses.remove(requestKey);
      }
    }
  }

  Future<void> _broadcastSseMessage(String message) async {
    if (_sseConnections.isEmpty) return;

    final staleConnections = <_SseConnection>[];
    for (final connection in _sseConnections) {
      try {
        await connection.sendJsonMessage(message);
      } on Exception {
        staleConnections.add(connection);
      }
    }

    for (final connection in staleConnections) {
      _sseConnections.remove(connection);
      await connection.close();
    }
  }

  String? _extractMessageId(String message) {
    try {
      final json = jsonDecode(message);
      if (json is! Map<String, dynamic>) {
        return null;
      }
      return _requestKey(json['id']);
    } on FormatException {
      return null;
    }
  }

  String? _requestKey(Object? id) {
    if (id == null) return null;
    return jsonEncode(id);
  }

  String _generateSessionId() {
    final now = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final random = Random.secure().nextInt(0x7fffffff).toRadixString(16);
    return '$now-$random';
  }
}

class _SseConnection {
  _SseConnection(this._response);

  final HttpResponse _response;
  bool _closed = false;
  int _eventId = 0;

  Future<void> open() async {
    if (_closed) return;
    _response.write('retry: 15000\n\n');
    await _response.flush();
  }

  Future<void> sendJsonMessage(String message) async {
    if (_closed) return;

    _eventId += 1;
    _response.write('event: message\n');
    _response.write('id: $_eventId\n');

    final normalized = message.replaceAll('\r', '');
    for (final line in const LineSplitter().convert(normalized)) {
      _response.write('data: $line\n');
    }
    _response.write('\n');
    await _response.flush();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _response.close();
    } on Exception {
      // Ignore shutdown errors from already-closed connections.
    }
  }
}
