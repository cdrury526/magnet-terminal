/// Tabbed terminal screen — composites tab bar, tab manager, and terminal views.
///
/// This is the main content widget that replaces the single-terminal layout.
/// It combines:
/// - [TerminalTabBar] in the title bar area
/// - [IndexedStack] below for terminal content — preserves widget state across
///   tab switches so background terminals remain alive and continue receiving
///   PTY output
/// - Focus management — the active terminal receives keyboard focus when
///   tabs are switched
///
/// The [TabManager] owns all session lifecycles. This widget simply wires
/// the manager to the visual layer.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/settings.dart';
import '../app/theme.dart';
import 'tab_bar_widget.dart';
import 'tab_manager.dart';
import 'terminal_session.dart';
import 'terminal_widget.dart';

/// A full-screen tabbed terminal layout.
///
/// Expects to fill the entire window. Renders a title bar with the tab strip
/// and an [IndexedStack] of terminal views below.
///
/// The [tabManager] must be provided by the parent (typically [AppShell])
/// so the manager's lifecycle is controlled at the app level and survives
/// widget rebuilds.
class TabbedTerminalScreen extends StatefulWidget {
  const TabbedTerminalScreen({
    super.key,
    required this.tabManager,
    required this.settings,
  });

  /// The tab manager that drives all session and tab state.
  final TabManager tabManager;

  /// Terminal appearance settings (font, theme, etc.).
  final TerminalSettings settings;

  /// Width reserved for macOS traffic light buttons.
  static const trafficLightWidth = 78.0;

  /// Height of the custom title bar area.
  static const titleBarHeight = 38.0;

  @override
  State<TabbedTerminalScreen> createState() => _TabbedTerminalScreenState();
}

class _TabbedTerminalScreenState extends State<TabbedTerminalScreen> {
  /// Focus nodes for each terminal session, keyed by session identity.
  ///
  /// We maintain a map so focus nodes survive tab reordering and are
  /// properly disposed when their session is closed.
  final Map<Object, FocusNode> _focusNodes = {};

  /// Tracks the last active index so we can detect tab switches
  /// and request focus on the newly active terminal.
  int _lastActiveIndex = -1;

  /// Cached shortcut bindings — rebuilt only when the tab count changes,
  /// not on every widget build.
  Map<ShortcutActivator, VoidCallback>? _cachedShortcuts;
  int _cachedTabCount = -1;

  @override
  void initState() {
    super.initState();
    widget.tabManager.addListener(_onTabManagerChanged);
    widget.settings.addListener(_onSettingsChanged);
    // Ensure focus nodes exist for the initial tab(s).
    _syncFocusNodes();
  }

  @override
  void didUpdateWidget(covariant TabbedTerminalScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tabManager != widget.tabManager) {
      oldWidget.tabManager.removeListener(_onTabManagerChanged);
      widget.tabManager.addListener(_onTabManagerChanged);
      _syncFocusNodes();
      _cachedShortcuts = null; // Invalidate — new manager may have different state.
    }
    if (oldWidget.settings != widget.settings) {
      oldWidget.settings.removeListener(_onSettingsChanged);
      widget.settings.addListener(_onSettingsChanged);
    }
  }

  @override
  void dispose() {
    widget.tabManager.removeListener(_onTabManagerChanged);
    widget.settings.removeListener(_onSettingsChanged);
    // Dispose all focus nodes we own.
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    _focusNodes.clear();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  //  Focus management
  // ---------------------------------------------------------------------------

  /// Called when the [TabManager] notifies (tab added, removed, switched, etc.).
  ///
  /// Syncs focus nodes and requests focus on the active terminal if the
  /// active tab changed.
  void _onTabManagerChanged() {
    if (!mounted) return;

    _syncFocusNodes();

    final activeIndex = widget.tabManager.activeTabIndex;
    if (activeIndex != _lastActiveIndex) {
      _lastActiveIndex = activeIndex;
      // Schedule focus request after the frame so the IndexedStack has
      // already switched the visible child.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _focusActiveTerminal();
      });
    }

    // Defer setState if called during build (e.g. TabManager fires
    // notifyListeners from session listener during initial build).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  /// Called when [TerminalSettings] change (font size, theme, etc.).
  /// Triggers rebuild so terminal widgets pick up new style/theme.
  void _onSettingsChanged() {
    if (!mounted) return;
    setState(() {});
  }

  /// Ensures a [FocusNode] exists for every current session and disposes
  /// nodes for sessions that no longer exist.
  void _syncFocusNodes() {
    final sessions = widget.tabManager.sessions;
    final currentKeys = <Object>{};

    for (final session in sessions) {
      final key = session; // identity-based key
      currentKeys.add(key);
      _focusNodes.putIfAbsent(
        key,
        () => FocusNode(debugLabel: 'Terminal-${session.hashCode}'),
      );
    }

    // Remove focus nodes for closed sessions.
    final staleKeys = _focusNodes.keys.toSet().difference(currentKeys);
    for (final key in staleKeys) {
      _focusNodes.remove(key)?.dispose();
    }
  }

  /// Requests keyboard focus on the active terminal.
  void _focusActiveTerminal() {
    final sessions = widget.tabManager.sessions;
    final activeIndex = widget.tabManager.activeTabIndex;
    if (activeIndex < 0 || activeIndex >= sessions.length) return;

    final activeSession = sessions[activeIndex];
    final focusNode = _focusNodes[activeSession];
    focusNode?.requestFocus();
  }

  // ---------------------------------------------------------------------------
  //  Keyboard shortcut bindings
  // ---------------------------------------------------------------------------

  /// Builds the shortcut map for tab management and font zoom.
  ///
  /// All shortcuts use the Meta (Cmd) key only — never Ctrl, which must
  /// pass through to the PTY for terminal apps (Ctrl+C, Ctrl+Z, etc.).
  ///
  /// The map is cached and only rebuilt when the tab count changes, since
  /// the Cmd+9 shortcut behavior depends on the number of open tabs.
  Map<ShortcutActivator, VoidCallback> _buildShortcuts() {
    final tabManager = widget.tabManager;
    final settings = widget.settings;
    final tabCount = tabManager.tabCount;

    if (_cachedShortcuts != null && _cachedTabCount == tabCount) {
      return _cachedShortcuts!;
    }
    _cachedTabCount = tabCount;

    _cachedShortcuts = <ShortcutActivator, VoidCallback>{
      // Cmd+T — new tab
      const SingleActivator(LogicalKeyboardKey.keyT, meta: true): () {
        tabManager.addTab();
      },

      // Cmd+W — close current tab
      const SingleActivator(LogicalKeyboardKey.keyW, meta: true): () {
        tabManager.closeTab(tabManager.activeTabIndex);
      },

      // Cmd+Shift+] — next tab
      const SingleActivator(
        LogicalKeyboardKey.bracketRight,
        meta: true,
        shift: true,
      ): () {
        tabManager.selectNextTab();
      },

      // Cmd+Shift+[ — previous tab
      const SingleActivator(
        LogicalKeyboardKey.bracketLeft,
        meta: true,
        shift: true,
      ): () {
        tabManager.selectPreviousTab();
      },

      // Cmd+= (Cmd+Plus) — increase font size
      const SingleActivator(LogicalKeyboardKey.equal, meta: true): () {
        settings.increaseFontSize();
      },

      // Cmd+- (Cmd+Minus) — decrease font size
      const SingleActivator(LogicalKeyboardKey.minus, meta: true): () {
        settings.decreaseFontSize();
      },

      // Cmd+0 — reset font size to default
      const SingleActivator(LogicalKeyboardKey.digit0, meta: true): () {
        settings.resetFontSize();
      },

      // Cmd+1 through Cmd+9 — select tab by index (Cmd+9 = last tab)
      for (var i = 1; i <= 9; i++)
        SingleActivator(
          _digitKeys[i]!,
          meta: true,
        ): () {
          if (i == 9) {
            // Cmd+9 always jumps to the last tab (macOS convention).
            tabManager.selectTab(tabManager.tabCount - 1);
          } else if (i <= tabManager.tabCount) {
            tabManager.selectTab(i - 1);
          }
        },
    };

    return _cachedShortcuts!;
  }

  /// Maps digit 1-9 to their [LogicalKeyboardKey] constants.
  static const _digitKeys = <int, LogicalKeyboardKey>{
    1: LogicalKeyboardKey.digit1,
    2: LogicalKeyboardKey.digit2,
    3: LogicalKeyboardKey.digit3,
    4: LogicalKeyboardKey.digit4,
    5: LogicalKeyboardKey.digit5,
    6: LogicalKeyboardKey.digit6,
    7: LogicalKeyboardKey.digit7,
    8: LogicalKeyboardKey.digit8,
    9: LogicalKeyboardKey.digit9,
  };

  // ---------------------------------------------------------------------------
  //  Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tabManager = widget.tabManager;
    final settings = widget.settings;
    final sessions = tabManager.sessions;

    return CallbackShortcuts(
      bindings: _buildShortcuts(),
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: settings.terminalBackground,
          body: Column(
            children: [
              // Title bar — macOS traffic light padding + tab bar
              Container(
                height: TabbedTerminalScreen.titleBarHeight,
                color: AppTheme.chromeBackground,
                child: Row(
                  children: [
                    // Space reserved for macOS traffic lights
                    const SizedBox(
                      width: TabbedTerminalScreen.trafficLightWidth,
                    ),

                    // Tab bar fills the remaining title bar space
                    Expanded(
                      child: TerminalTabBar(tabManager: tabManager),
                    ),
                  ],
                ),
              ),

              // Subtle divider between title bar and content
              Divider(
                height: 1,
                thickness: 1,
                color: cs.outlineVariant.withValues(alpha: 0.2),
              ),

              // Terminal content area — IndexedStack preserves all terminal
              // widget state across tab switches. Background terminals keep
              // running and receiving PTY output.
              Expanded(
                child: IndexedStack(
                  index: tabManager.activeTabIndex,
                  children: [
                    for (int i = 0; i < sessions.length; i++)
                      _TerminalTab(
                        key: ValueKey(sessions[i]),
                        session: sessions[i],
                        focusNode: _focusNodes[sessions[i]]!,
                        isActive: i == tabManager.activeTabIndex,
                        settings: settings,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
//  Individual terminal tab content
// ---------------------------------------------------------------------------

/// Wraps a [MagnetTerminalWidget] for use inside the [IndexedStack].
///
/// Starts the session on first build if it's still idle (hasn't been started).
/// The session lifecycle is owned by [TabManager], not this widget —
/// [ownsSession] is set to false.
class _TerminalTab extends StatefulWidget {
  const _TerminalTab({
    super.key,
    required this.session,
    required this.focusNode,
    required this.isActive,
    required this.settings,
  });

  final TerminalSession session;
  final FocusNode focusNode;
  final bool isActive;
  final TerminalSettings settings;

  @override
  State<_TerminalTab> createState() => _TerminalTabState();
}

class _TerminalTabState extends State<_TerminalTab> {
  @override
  void initState() {
    super.initState();
    // Delay starting the session until after the first frame so we can
    // estimate the terminal size from the widget's constraints. This avoids
    // starting the shell with the default 80x24 and then immediately resizing,
    // which causes the prompt to appear in the middle of a larger terminal.
    if (widget.session.status == SessionStatus.idle) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final size = _estimateTerminalSize();
        widget.session.start(columns: size.columns, rows: size.rows);
      });
    }
  }

  /// Estimates the terminal size based on the widget's constraints.
  /// Returns (columns, rows) as a record.
  ({int columns, int rows}) _estimateTerminalSize() {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return (columns: 80, rows: 24);

    final size = renderBox.size;
    final settings = widget.settings;

    // Calculate cell size from the terminal style.
    final fontSize = settings.terminalStyle?.fontSize ?? 14;
    final lineHeight = fontSize * 1.2; // Default line height multiplier
    final charWidth = fontSize * 0.6; // Approximate char width for monospace

    // Estimate columns and rows, leaving some padding.
    final columns = (size.width / charWidth).floor().clamp(20, 512);
    final rows = (size.height / lineHeight).floor().clamp(10, 256);

    return (columns: columns, rows: rows);
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    return MagnetTerminalWidget(
      session: widget.session,
      focusNode: widget.focusNode,
      autofocus: widget.isActive,
      theme: settings.terminalTheme,
      textStyle: settings.terminalStyle,
      // TabManager owns the session lifecycle — don't let the widget
      // dispose it when removed from the tree (e.g., during tab close,
      // the manager disposes the session after removing it).
      ownsSession: false,
    );
  }
}
