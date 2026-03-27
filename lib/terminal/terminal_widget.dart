/// Terminal widget wrapper — hosts a [TerminalView] bound to a [TerminalSession].
///
/// [MagnetTerminalWidget] wraps dart_xterm's [TerminalView] with:
/// - Focus management (auto-request on mount, expose [FocusNode] for tab switching)
/// - Session event callbacks (title change, bell, process exit)
/// - Proper lifecycle management (disposes the session when the widget is removed)
/// - Copy/paste support (Cmd+C/V via dart_xterm built-in shortcuts, plus
///   right-click context menu and multi-line paste confirmation)
/// - Configurable theme and font
library;

import 'package:dart_xterm/dart_xterm.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'terminal_session.dart';

/// A widget that renders a terminal session using dart_xterm's [TerminalView].
///
/// Accepts a [TerminalSession] and wires it up automatically. The session is
/// started if not already running, and disposed when this widget is removed
/// from the tree (unless [ownsSession] is false).
///
/// Example:
/// ```dart
/// MagnetTerminalWidget(
///   session: mySession,
///   autofocus: true,
///   onTitleChanged: (title) => setState(() => tabTitle = title),
///   onExit: (code) => closeTab(),
/// )
/// ```
class MagnetTerminalWidget extends StatefulWidget {
  const MagnetTerminalWidget({
    super.key,
    required this.session,
    this.theme,
    this.textStyle,
    this.padding,
    this.focusNode,
    this.autofocus = false,
    this.ownsSession = true,
    this.onTitleChanged,
    this.onBell,
    this.onExit,
    this.onSecondaryTap,
    this.multiLinePasteThreshold = 1,
  });

  /// The terminal session to render. Must be started before or after mounting.
  final TerminalSession session;

  /// Terminal color theme. Falls back to a dark VS Code-inspired theme.
  final TerminalTheme? theme;

  /// Terminal font configuration. Falls back to dart_xterm defaults (13px
  /// monospace with Menlo/Monaco/Consolas fallbacks).
  final TerminalStyle? textStyle;

  /// Padding around the terminal content area.
  final EdgeInsets? padding;

  /// Focus node for this terminal. If not provided, an internal one is created.
  /// Pass an external [FocusNode] when you need to control focus from outside
  /// (e.g., tab switching).
  final FocusNode? focusNode;

  /// Whether to request focus automatically when mounted.
  final bool autofocus;

  /// Whether this widget owns the [session] lifecycle. When true (default),
  /// the session is disposed when this widget is removed from the tree.
  /// Set to false when the session lifecycle is managed externally.
  final bool ownsSession;

  /// Called when the shell sets a new title via OSC 0/2 escape sequences.
  final ValueChanged<String>? onTitleChanged;

  /// Called when the shell sends a bell character (BEL, 0x07).
  final VoidCallback? onBell;

  /// Called when the shell process exits. Receives the exit code.
  final ValueChanged<int>? onExit;

  /// Called on secondary tap (right-click / Ctrl+click) after the built-in
  /// context menu is shown. Receives the global tap position.
  final void Function(Offset position)? onSecondaryTap;

  /// Number of newlines in pasted text before triggering a confirmation dialog.
  /// Set to `0` to always confirm multi-line pastes. Set to a very large number
  /// to effectively disable the confirmation. Defaults to 1 (any text with a
  /// newline triggers the dialog).
  final int multiLinePasteThreshold;

  @override
  State<MagnetTerminalWidget> createState() => _MagnetTerminalWidgetState();
}

class _MagnetTerminalWidgetState extends State<MagnetTerminalWidget> {
  late FocusNode _focusNode;
  bool _ownsFocusNode = false;

  /// Tracks the last title we reported via [onTitleChanged] to avoid duplicate
  /// callbacks when the session notifies but the title hasn't actually changed.
  String? _lastReportedTitle;

  @override
  void initState() {
    super.initState();
    _initFocusNode();
    _listenToSession();
  }

  @override
  void didUpdateWidget(covariant MagnetTerminalWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Handle focus node changes.
    if (oldWidget.focusNode != widget.focusNode) {
      if (_ownsFocusNode) {
        _focusNode.dispose();
      }
      _initFocusNode();
    }

    // Handle session changes.
    if (oldWidget.session != widget.session) {
      oldWidget.session.removeListener(_onSessionChanged);
      _lastReportedTitle = null;
      _listenToSession();
    }
  }

  @override
  void dispose() {
    widget.session.removeListener(_onSessionChanged);

    if (widget.ownsSession) {
      widget.session.dispose();
    }

    if (_ownsFocusNode) {
      _focusNode.dispose();
    }

    super.dispose();
  }

  // ---------------------------------------------------------------------------
  //  Focus
  // ---------------------------------------------------------------------------

  void _initFocusNode() {
    if (widget.focusNode != null) {
      _focusNode = widget.focusNode!;
      _ownsFocusNode = false;
    } else {
      _focusNode = FocusNode(debugLabel: 'MagnetTerminalWidget');
      _ownsFocusNode = true;
    }
  }

  /// Request keyboard focus on this terminal. Call this when switching tabs.
  void requestFocus() {
    _focusNode.requestFocus();
  }

  // ---------------------------------------------------------------------------
  //  Session event handling
  // ---------------------------------------------------------------------------

  void _listenToSession() {
    widget.session.addListener(_onSessionChanged);
  }

  void _onSessionChanged() {
    if (!mounted) return;

    final session = widget.session;

    // Title change — notify callback but do not trigger a rebuild.
    // The tab bar listens to the TabManager for title updates, not this widget.
    final currentTitle = session.title;
    if (currentTitle != _lastReportedTitle) {
      _lastReportedTitle = currentTitle;
      widget.onTitleChanged?.call(currentTitle);
    }

    // Process exit — notify callback. Only rebuild if the session has exited
    // (to show an exit indicator or trigger tab close), not on every terminal
    // content change. RenderTerminal handles its own repainting via its
    // direct listener on the Terminal object.
    if (session.status == SessionStatus.exited && session.exitCode != null) {
      widget.onExit?.call(session.exitCode!);
      // Only rebuild on status change, not on every output write.
      setState(() {});
    }
  }

  // ---------------------------------------------------------------------------
  //  Copy / paste helpers
  // ---------------------------------------------------------------------------

  /// Whether the terminal currently has selected text.
  bool get _hasSelection =>
      widget.session.terminalController.selection != null;

  /// Copies the current terminal selection to the system clipboard.
  ///
  /// Returns `true` if text was copied, `false` if there was no selection.
  Future<bool> _copySelection() async {
    final controller = widget.session.terminalController;
    final selection = controller.selection;
    if (selection == null) return false;

    final text = widget.session.terminal.buffer.getText(selection);
    if (text.isEmpty) return false;

    await Clipboard.setData(ClipboardData(text: text));
    return true;
  }

  /// Pastes text from the system clipboard into the terminal.
  ///
  /// If the text contains newlines and exceeds [multiLinePasteThreshold],
  /// shows a confirmation dialog before pasting. Uses [Terminal.paste] which
  /// automatically wraps in bracketed paste escape sequences when the running
  /// app has enabled bracketed paste mode (CSI ? 2004 h).
  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;

    final newlineCount = '\n'.allMatches(text).length;
    if (newlineCount > widget.multiLinePasteThreshold) {
      if (!mounted) return;
      final confirmed = await _showMultiLinePasteConfirmation(text);
      if (!confirmed) return;
    }

    widget.session.terminal.paste(text);
    widget.session.terminalController.clearSelection();
  }

  /// Shows a confirmation dialog for multi-line paste operations.
  ///
  /// Returns `true` if the user confirms the paste, `false` otherwise.
  Future<bool> _showMultiLinePasteConfirmation(String text) async {
    final lineCount = '\n'.allMatches(text).length + 1;
    // Show a preview — truncate if very long.
    final preview = text.length > 500 ? '${text.substring(0, 500)}...' : text;

    final result = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final cs = theme.colorScheme;
        return AlertDialog(
          backgroundColor: cs.surfaceContainer,
          title: Text(
            'Paste $lineCount lines?',
            style: theme.textTheme.titleMedium?.copyWith(
              color: cs.onSurface,
            ),
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480, maxHeight: 300),
            child: SingleChildScrollView(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: Text(
                  preview,
                  style: const TextStyle(
                    fontFamily: 'Menlo',
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Paste'),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  // ---------------------------------------------------------------------------
  //  Context menu
  // ---------------------------------------------------------------------------

  /// Shows a context menu at [position] with Copy and Paste options.
  void _showContextMenu(Offset position) {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    final hasSelection = _hasSelection;

    showMenu<_ContextMenuAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        PopupMenuItem<_ContextMenuAction>(
          enabled: hasSelection,
          value: _ContextMenuAction.copy,
          height: 32,
          child: const _ContextMenuItem(
            icon: Icons.copy,
            label: 'Copy',
            shortcut: '\u2318C',
          ),
        ),
        PopupMenuItem<_ContextMenuAction>(
          value: _ContextMenuAction.paste,
          height: 32,
          child: const _ContextMenuItem(
            icon: Icons.paste,
            label: 'Paste',
            shortcut: '\u2318V',
          ),
        ),
        const PopupMenuDivider(height: 8),
        PopupMenuItem<_ContextMenuAction>(
          value: _ContextMenuAction.selectAll,
          height: 32,
          child: const _ContextMenuItem(
            icon: Icons.select_all,
            label: 'Select All',
            shortcut: '\u2318A',
          ),
        ),
      ],
    ).then((action) {
      if (action == null) return;
      switch (action) {
        case _ContextMenuAction.copy:
          _copySelection();
        case _ContextMenuAction.paste:
          _pasteFromClipboard();
        case _ContextMenuAction.selectAll:
          _selectAll();
      }
    });
  }

  /// Selects all text in the terminal buffer.
  void _selectAll() {
    final terminal = widget.session.terminal;
    final controller = widget.session.terminalController;
    controller.setSelection(
      terminal.buffer.createAnchor(
        0,
        terminal.buffer.height - terminal.viewHeight,
      ),
      terminal.buffer.createAnchor(
        terminal.viewWidth,
        terminal.buffer.height - 1,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  //  Key event interception
  // ---------------------------------------------------------------------------

  /// Intercepts Cmd+V to add multi-line paste confirmation before dart_xterm's
  /// built-in paste handling kicks in.
  ///
  /// Returns [KeyEventResult.handled] for Cmd+V to prevent dart_xterm from
  /// pasting immediately, then performs the paste asynchronously with
  /// confirmation if needed.
  ///
  /// All other key events are returned as [KeyEventResult.ignored] so
  /// dart_xterm handles them normally (including Cmd+C for copy).
  KeyEventResult _onKeyEvent(FocusNode focusNode, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    // Intercept Cmd+V for multi-line paste confirmation.
    if (event.logicalKey == LogicalKeyboardKey.keyV &&
        HardwareKeyboard.instance.isMetaPressed &&
        !HardwareKeyboard.instance.isControlPressed &&
        !HardwareKeyboard.instance.isAltPressed) {
      _pasteFromClipboard();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  // ---------------------------------------------------------------------------
  //  Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final session = widget.session;

    // RepaintBoundary isolates the terminal from parent rebuilds (e.g.,
    // settings changes, tab bar updates). The RenderTerminal already sets
    // isRepaintBoundary = true internally, but this outer boundary prevents
    // the widget tree reconstruction from propagating unnecessary paints
    // to sibling widgets.
    return RepaintBoundary(
      child: TerminalView(
        session.terminal,
        controller: session.terminalController,
        theme: widget.theme ?? _kDefaultTheme,
        textStyle: widget.textStyle ?? _kDefaultTextStyle,
        padding: widget.padding ?? EdgeInsets.zero,
        autoResize: true,
        focusNode: _focusNode,
        autofocus: widget.autofocus,
        hardwareKeyboardOnly: true,
        mouseCursor: SystemMouseCursors.text,
        cursorType: TerminalCursorType.block,
        alwaysShowCursor: false,
        onKeyEvent: _onKeyEvent,
        onSecondaryTapUp: (details, _) {
          _showContextMenu(details.globalPosition);
          widget.onSecondaryTap?.call(details.globalPosition);
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
//  Context menu helpers
// ---------------------------------------------------------------------------

/// Actions available in the terminal context menu.
enum _ContextMenuAction { copy, paste, selectAll }

/// A single row in the terminal context menu.
class _ContextMenuItem extends StatelessWidget {
  const _ContextMenuItem({
    required this.icon,
    required this.label,
    required this.shortcut,
  });

  final IconData icon;
  final String label;
  final String shortcut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.onSurface),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
        Text(
          shortcut,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
//  Default theme and font constants
// -----------------------------------------------------------------------------

/// A dark terminal theme inspired by VS Code's default integrated terminal.
const _kDefaultTheme = TerminalTheme(
  cursor: Color(0xFFAEAFAD),
  selection: Color(0x80AEAFAD),
  foreground: Color(0xFFCCCCCC),
  background: Color(0xFF1A1A2E),
  black: Color(0xFF000000),
  red: Color(0xFFCD3131),
  green: Color(0xFF0DBC79),
  yellow: Color(0xFFE5E510),
  blue: Color(0xFF2472C8),
  magenta: Color(0xFFBC3FBC),
  cyan: Color(0xFF11A8CD),
  white: Color(0xFFE5E5E5),
  brightBlack: Color(0xFF666666),
  brightRed: Color(0xFFF14C4C),
  brightGreen: Color(0xFF23D18B),
  brightYellow: Color(0xFFF5F543),
  brightBlue: Color(0xFF3B8EEA),
  brightMagenta: Color(0xFFD670D6),
  brightCyan: Color(0xFF29B8DB),
  brightWhite: Color(0xFFFFFFFF),
  searchHitBackground: Color(0xFFFFFF2B),
  searchHitBackgroundCurrent: Color(0xFF31FF26),
  searchHitForeground: Color(0xFF000000),
);

/// Default terminal font — 14px Menlo with standard monospace fallbacks.
const _kDefaultTextStyle = TerminalStyle(
  fontSize: 14,
  height: 1.2,
  fontFamily: 'Menlo',
  fontFamilyFallback: [
    'Monaco',
    'Consolas',
    'Liberation Mono',
    'Courier New',
    'monospace',
  ],
);
