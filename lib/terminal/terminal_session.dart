/// Terminal session model — wraps a dart_xterm [Terminal] and dart_pty [Pty].
///
/// Each tab in the app owns one [TerminalSession]. The session manages:
/// - PTY process lifecycle (spawn, resize, dispose)
/// - The xterm [Terminal] buffer that the PTY writes into
/// - Bidirectional data piping (PTY output -> Terminal, Terminal input -> PTY)
/// - Title tracking (from OSC escape sequences)
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_pty/dart_pty.dart';
import 'package:dart_xterm/dart_xterm.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'package:magnet_terminal/terminal/pty_environment.dart';

/// Status of a [TerminalSession]'s underlying process.
enum SessionStatus {
  /// The session has been created but the PTY has not been spawned yet.
  idle,

  /// The PTY process is running.
  running,

  /// The PTY process has exited (see [TerminalSession.exitCode]).
  exited,

  /// The session has been disposed and cannot be reused.
  disposed,
}

/// A terminal session that owns both a dart_xterm [Terminal] and a dart_pty
/// [Pty], wired together with bidirectional data pipes.
///
/// Create a session, then call [start] to spawn the shell process. The session
/// pipes PTY output through UTF-8 decoding into the terminal buffer, and
/// forwards terminal user input back to the PTY as UTF-8 bytes.
///
/// Resize events from the terminal are automatically propagated to the PTY so
/// the child process receives SIGWINCH.
///
/// Dispose the session when the tab is closed — this kills the child process
/// and releases all resources.
class TerminalSession with ChangeNotifier {
  /// Creates a new terminal session.
  ///
  /// [maxScrollback] controls how many lines the terminal buffer retains
  /// above the visible viewport. Default is 50,000 lines to support
  /// large output (e.g., `cat` of large files, `find /` output) without
  /// truncating scrollback prematurely. Each line consumes roughly 200-400
  /// bytes of memory depending on content, so 50k lines ≈ 10-20 MB per
  /// session — well within budget for a desktop app.
  TerminalSession({int maxScrollback = 50000})
    : terminal = Terminal(
        maxLines: maxScrollback,
        // Configure DA1/DA2/DA3/XTVERSION/DECRQM responses so CLI apps
        // (Claude Code, Codex CLI, Gemini CLI) detect proper capabilities.
        emitter: PtyEnvironment.buildEmitter(),
      ),
      terminalController = TerminalController();

  // ---------------------------------------------------------------------------
  //  Public state
  // ---------------------------------------------------------------------------

  /// The xterm terminal buffer. Bind this to a [TerminalView] widget.
  final Terminal terminal;

  /// Controller for the terminal view (selection, highlights).
  final TerminalController terminalController;

  /// Current lifecycle status of the session.
  SessionStatus get status => _status;

  /// The title most recently set by the shell via OSC escape sequences.
  /// Falls back to the executable name if no title has been set.
  String get title => _oscTitle ?? _executable ?? 'Terminal';

  /// The exit code of the child process, or `null` if still running.
  int? get exitCode => _exitCode;

  /// The PID of the child process, or `null` if not yet started.
  int? get pid => _pty?.pid;

  // ---------------------------------------------------------------------------
  //  Private state
  // ---------------------------------------------------------------------------

  SessionStatus _status = SessionStatus.idle;
  Pty? _pty;
  StreamSubscription<Uint8List>? _outputSubscription;
  String? _oscTitle;
  String? _executable;
  int? _exitCode;

  // UTF-8 decoder that handles multi-byte sequences split across chunks.
  final Utf8Decoder _utf8Decoder = const Utf8Decoder(allowMalformed: true);

  // ---------------------------------------------------------------------------
  //  PTY output buffering
  // ---------------------------------------------------------------------------
  //
  // The PTY emits many small output chunks during rapid output (e.g., `cat`
  // of a large file). Writing each chunk individually to the Terminal triggers
  // a separate notifyListeners() + markNeedsLayout() on the RenderTerminal.
  //
  // While Flutter coalesces layout passes within a frame, the repeated
  // parser.write() + notifyListeners() overhead is measurable. We batch
  // all chunks that arrive within a single frame and flush them as one
  // terminal.write() call per frame using a post-frame callback.
  //
  // This reduces the number of terminal.write() calls from potentially
  // hundreds per frame to exactly one, cutting parsing overhead and
  // ChangeNotifier dispatch cost.

  final _outputBuffer = BytesBuilder(copy: false);
  bool _flushScheduled = false;

  // ---------------------------------------------------------------------------
  //  Lifecycle
  // ---------------------------------------------------------------------------

  /// Spawn the shell process and begin piping data.
  ///
  /// Uses the user's default shell from the `SHELL` environment variable.
  /// Sets terminal environment variables required for CLI app compatibility:
  /// - `TERM=xterm-256color`
  /// - `COLORTERM=truecolor`
  /// - `TERM_PROGRAM=magnet-terminal`
  /// - `LANG` (inherited or defaulted to `en_US.UTF-8`)
  void start({
    String? executable,
    List<String>? arguments,
    String? workingDirectory,
    Map<String, String>? extraEnvironment,
    int columns = 80,
    int rows = 24,
  }) {
    if (_status == SessionStatus.disposed) {
      throw StateError('Cannot start a disposed TerminalSession');
    }
    if (_status == SessionStatus.running) {
      throw StateError('TerminalSession is already running');
    }

    // Resolve the shell executable.
    _executable = executable ?? PtyEnvironment.defaultShell;

    // Build the environment map using PtyEnvironment which sets TERM,
    // COLORTERM, TERM_PROGRAM, TERM_PROGRAM_VERSION, FORCE_HYPERLINK,
    // LANG, and inherits essential parent env vars (HOME, PATH, etc.).
    // These env vars work with the EscapeEmitter DA/XTVERSION responses
    // to advertise terminal capabilities to CLI apps.
    final environment = PtyEnvironment.buildEnvironment(
      extraVars: extraEnvironment,
    );

    debugPrint(
      'TerminalSession.start: spawning ${_executable!} '
      'with ${columns}x$rows '
      'cwd=${workingDirectory ?? PtyEnvironment.homeDirectory}',
    );

    // Spawn the PTY process.
    _pty = Pty.start(
      _executable!,
      arguments: arguments,
      environment: environment,
      workingDirectory: workingDirectory ?? PtyEnvironment.homeDirectory,
      columns: columns,
      rows: rows,
    );

    // Wire up bidirectional pipes.
    _wirePtyToTerminal();
    _wireTerminalToPty();
    _wireResize();
    _wireTitleTracking();
    _wireExitHandling();

    _status = SessionStatus.running;
    notifyListeners();
  }

  /// Write raw data to the PTY (as if the user typed it).
  ///
  /// This bypasses the terminal's input handler — use it for programmatic
  /// input injection (e.g., pasting, sending escape sequences).
  void writeToPty(String data) {
    _pty?.write(Uint8List.fromList(utf8.encode(data)));
  }

  /// Resize the terminal and propagate to the PTY.
  ///
  /// Called by the terminal widget wrapper when the view dimensions change.
  void resize(int rows, int columns) {
    terminal.resize(columns, rows, columns * 8, rows * 16);
    if (_status == SessionStatus.running) {
      try {
        _pty?.resize(rows, columns);
      } on PtyException catch (_) {
        // PTY may already be closed during rapid resize + exit race.
      }
    }
  }

  /// Dispose all resources. Safe to call multiple times.
  ///
  /// Cancels the output stream subscription, kills the child process if still
  /// running, disposes the PTY, and cleans up the terminal callbacks.
  @override
  void dispose() {
    if (_status == SessionStatus.disposed) return;

    _status = SessionStatus.disposed;

    // Tear down stream subscription first to avoid processing stale data.
    _outputSubscription?.cancel();
    _outputSubscription = null;

    // Discard any buffered output — no point writing to a disposed terminal.
    _outputBuffer.clear();
    _flushScheduled = false;

    // Disconnect terminal callbacks.
    terminal.onOutput = null;
    terminal.onResize = null;
    terminal.onTitleChange = null;

    // Kill and dispose the PTY.
    if (_pty != null) {
      try {
        _pty!.kill();
      } on PtyException catch (_) {
        // Process may have already exited.
      }
      _pty!.dispose();
      _pty = null;
    }

    // Dispose the terminal controller.
    terminalController.dispose();

    super.dispose();
  }

  // ---------------------------------------------------------------------------
  //  Wiring helpers
  // ---------------------------------------------------------------------------

  /// PTY output (bytes) -> buffer -> flush once per frame -> Terminal.write().
  ///
  /// Instead of writing each PTY output chunk directly to the terminal
  /// (which triggers notifyListeners on each call), we accumulate chunks
  /// in a buffer and flush them all at once before the next frame paints.
  /// This batches potentially hundreds of small writes into one, reducing
  /// escape sequence parser invocations and ChangeNotifier overhead.
  void _wirePtyToTerminal() {
    _outputSubscription = _pty!.output.listen(
      (data) {
        _outputBuffer.add(data);
        _scheduleFlush();
      },
      onError: (Object error) {
        debugPrint('TerminalSession: PTY output error: $error');
      },
      onDone: () {
        // Flush any remaining buffered data before the stream closes.
        _flushOutputBuffer();
      },
    );
  }

  /// Schedules a single flush per frame using a post-frame callback.
  ///
  /// Multiple PTY output events within the same frame are coalesced into
  /// one terminal.write() call. We use addPostFrameCallback so the flush
  /// happens at a predictable point in the frame lifecycle, after build
  /// but before paint — ensuring the terminal buffer is updated for the
  /// current frame's paint pass.
  void _scheduleFlush() {
    if (_flushScheduled) return;
    _flushScheduled = true;

    // Use a post-frame callback to flush before the next paint.
    // If the scheduler is not active (e.g., app is starting up or
    // in a test), fall back to a microtask for immediate flush.
    try {
      SchedulerBinding.instance.scheduleFrameCallback((_) {
        _flushOutputBuffer();
      });
    } catch (_) {
      // Scheduler not initialized yet — flush immediately.
      scheduleMicrotask(_flushOutputBuffer);
    }
  }

  /// Writes all buffered PTY output to the terminal in one batch.
  void _flushOutputBuffer() {
    _flushScheduled = false;
    if (_outputBuffer.isEmpty) return;
    if (_status == SessionStatus.disposed) return;

    final bytes = _outputBuffer.takeBytes();
    final decoded = _utf8Decoder.convert(bytes);
    terminal.write(decoded);
  }

  /// Terminal user input (String) -> UTF-8 encode -> PTY.write(bytes).
  void _wireTerminalToPty() {
    terminal.onOutput = (String data) {
      if (_status != SessionStatus.running || _pty == null) return;
      try {
        _pty!.write(Uint8List.fromList(utf8.encode(data)));
      } on PtyException catch (_) {
        // PTY may be closed if process exited between check and write.
      }
    };
  }

  /// Terminal resize -> PTY resize (sends SIGWINCH to child).
  void _wireResize() {
    terminal.onResize =
        (int width, int height, int pixelWidth, int pixelHeight) {
          if (_status != SessionStatus.running || _pty == null) return;
          try {
            _pty!.resize(height, width);
          } on PtyException catch (_) {
            // Resize race with process exit.
          }
        };
  }

  /// Track OSC title changes from the shell.
  void _wireTitleTracking() {
    terminal.onTitleChange = (String title) {
      if (_oscTitle != title) {
        _oscTitle = title;
        notifyListeners();
      }
    };
  }

  /// Handle PTY process exit.
  void _wireExitHandling() {
    _pty!.exitCode.then((int code) {
      if (_status == SessionStatus.disposed) return;
      _exitCode = code;
      _status = SessionStatus.exited;
      notifyListeners();
    });
  }
}
