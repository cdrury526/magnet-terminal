import 'package:flutter/material.dart';

import '../services/devtools_server.dart';
import '../terminal/tab_manager.dart';
import '../terminal/tabbed_terminal_screen.dart';
import 'settings.dart';
import 'theme.dart';

/// Root widget for Magnet Terminal.
///
/// Sets up [MaterialApp] with the dark terminal theme. The app uses
/// Material 3 with a terminal-optimized dark palette and monospace
/// text defaults. [TerminalSettings] is provided via [ListenableBuilder]
/// so the theme updates reactively when settings change.
class MagnetTerminalApp extends StatefulWidget {
  const MagnetTerminalApp({super.key});

  @override
  State<MagnetTerminalApp> createState() => _MagnetTerminalAppState();
}

class _MagnetTerminalAppState extends State<MagnetTerminalApp> {
  final _settings = TerminalSettings();

  @override
  void initState() {
    super.initState();
    // Load persisted settings. Until complete, defaults are used.
    _settings.load();
  }

  @override
  void dispose() {
    _settings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ListenableBuilder rebuilds the MaterialApp when settings change,
    // which updates the theme (scaffold background matches terminal theme).
    return ListenableBuilder(
      listenable: _settings,
      builder: (context, _) {
        return MaterialApp(
          title: 'Magnet Terminal',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.dark(
            terminalBackground: _settings.terminalBackground,
          ),
          home: AppShell(settings: _settings),
        );
      },
    );
  }
}

/// The main app shell — provides the top-level layout structure.
///
/// Creates and owns a [TabManager] that manages all terminal sessions.
/// The [TabbedTerminalScreen] handles the visual layout (tab bar + terminal
/// content via IndexedStack). The TabManager is created here so its lifecycle
/// is tied to the app window — all sessions are disposed when the window
/// closes, preventing orphaned PTY processes.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.settings});

  /// Terminal settings shared with all terminal widgets.
  final TerminalSettings settings;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late final TabManager _tabManager;
  late final DevtoolsServer _devtoolsServer;

  @override
  void initState() {
    super.initState();
    // TabManager constructor creates one initial tab automatically.
    _tabManager = TabManager();

    // Start the MCP DevTools server for terminal introspection.
    // Tools get the active terminal/PTY on each invocation via callbacks.
    _devtoolsServer = DevtoolsServer(
      terminalProvider: () => _tabManager.activeSession.terminal,
      ptyWriterProvider: () => _tabManager.activeSession.writeToPty,
      sessionProvider: () => _tabManager.activeSession,
    );
    _devtoolsServer.start();
  }

  @override
  void dispose() {
    _devtoolsServer.stop();
    // TabManager.dispose kills all PTY processes and releases all resources.
    _tabManager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TabbedTerminalScreen(
      tabManager: _tabManager,
      settings: widget.settings,
    );
  }
}
