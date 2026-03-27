/// Tab bar widget — horizontal tab strip for the terminal title bar.
///
/// Renders compact tabs styled like iTerm2/VS Code, with:
/// - Session title text (from OSC escape sequences or default shell name)
/// - Close button per tab (or middle-click to close)
/// - Visual indicator for the active tab
/// - "+" button to create a new tab
/// - Drag-to-reorder support via [ReorderableListView]
/// - Animated tab additions and removals
///
/// Designed to sit inside the 38px title bar, alongside macOS traffic
/// light buttons (78px left padding handled by the parent).
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../app/theme.dart';
import 'tab_manager.dart';
import 'terminal_session.dart';

/// A horizontal tab bar driven by a [TabManager].
///
/// Uses [ListenableBuilder] to rebuild when the [TabManager] notifies
/// (tab added, removed, reordered, switched, or title changed).
///
/// The widget expects to be placed in a constrained-height context
/// (typically [AppShell.titleBarHeight] = 38px).
class TerminalTabBar extends StatelessWidget {
  const TerminalTabBar({
    super.key,
    required this.tabManager,
  });

  /// The tab manager that drives this bar's state.
  final TabManager tabManager;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: tabManager,
      builder: (context, _) {
        return _TabBarContent(tabManager: tabManager);
      },
    );
  }
}

/// The actual tab bar content — separated so ListenableBuilder only
/// rebuilds this subtree, not the entire parent.
class _TabBarContent extends StatelessWidget {
  const _TabBarContent({required this.tabManager});

  final TabManager tabManager;

  @override
  Widget build(BuildContext context) {
    final sessions = tabManager.sessions;
    final activeIndex = tabManager.activeTabIndex;

    return Row(
      children: [
        // Scrollable tab area — takes all available space
        Expanded(
          child: _ReorderableTabStrip(
            sessions: sessions,
            activeIndex: activeIndex,
            onSelect: tabManager.selectTab,
            onClose: tabManager.closeTab,
            onReorder: _handleReorder,
          ),
        ),

        // New tab button
        _NewTabButton(onPressed: tabManager.addTab),
      ],
    );
  }

  void _handleReorder(int oldIndex, int newIndex) {
    // ReorderableListView passes newIndex that accounts for the
    // removal of the old item, so adjust for our moveTab API.
    var adjustedNew = newIndex;
    if (newIndex > oldIndex) {
      adjustedNew--;
    }
    tabManager.moveTab(oldIndex, adjustedNew);
  }
}

// ---------------------------------------------------------------------------
//  Reorderable tab strip
// ---------------------------------------------------------------------------

/// A horizontally scrollable, reorderable list of tab items.
class _ReorderableTabStrip extends StatelessWidget {
  const _ReorderableTabStrip({
    required this.sessions,
    required this.activeIndex,
    required this.onSelect,
    required this.onClose,
    required this.onReorder,
  });

  final List<TerminalSession> sessions;
  final int activeIndex;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onClose;
  final void Function(int oldIndex, int newIndex) onReorder;

  @override
  Widget build(BuildContext context) {
    return ReorderableListView.builder(
      scrollDirection: Axis.horizontal,
      buildDefaultDragHandles: false,
      proxyDecorator: _proxyDecorator,
      onReorder: onReorder,
      itemCount: sessions.length,
      itemBuilder: (context, index) {
        final session = sessions[index];
        final isActive = index == activeIndex;

        return ReorderableDragStartListener(
          key: ValueKey(session),
          index: index,
          child: _TabItem(
            session: session,
            isActive: isActive,
            index: index,
            onSelect: () => onSelect(index),
            onClose: () => onClose(index),
          ),
        );
      },
    );
  }

  /// Custom drag proxy — slightly elevated version of the tab.
  Widget _proxyDecorator(Widget child, int index, Animation<double> animation) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final elevation = Tween<double>(begin: 0, end: 4).animate(animation);
        return Material(
          elevation: elevation.value,
          color: Colors.transparent,
          child: child,
        );
      },
      child: child,
    );
  }
}

// ---------------------------------------------------------------------------
//  Individual tab item
// ---------------------------------------------------------------------------

/// A single tab in the tab bar.
///
/// Shows the session title and a close button on hover. Supports:
/// - Click to select
/// - Middle-click to close
/// - Close button (X) on hover or when active
class _TabItem extends StatefulWidget {
  const _TabItem({
    required this.session,
    required this.isActive,
    required this.index,
    required this.onSelect,
    required this.onClose,
  });

  final TerminalSession session;
  final bool isActive;
  final int index;
  final VoidCallback onSelect;
  final VoidCallback onClose;

  @override
  State<_TabItem> createState() => _TabItemState();
}

class _TabItemState extends State<_TabItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final showClose = _hovered || widget.isActive;

    return Listener(
      // Middle-click to close
      onPointerDown: (event) {
        if (event.buttons == kMiddleMouseButton) {
          widget.onClose();
        }
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onSelect,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            constraints: const BoxConstraints(
              minWidth: 80,
              maxWidth: 200,
            ),
            padding: const EdgeInsets.only(left: 12, right: 4),
            decoration: BoxDecoration(
              color: _tabColor(cs),
              border: Border(
                bottom: BorderSide(
                  color: widget.isActive
                      ? cs.primary
                      : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Session status dot for exited processes
                if (widget.session.status == SessionStatus.exited)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: cs.error,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),

                // Tab title
                Expanded(
                  child: Text(
                    widget.session.title,
                    style: textTheme.labelMedium?.copyWith(
                      color: widget.isActive
                          ? cs.onSurface
                          : cs.onSurface.withValues(alpha: 0.55),
                      fontWeight: widget.isActive
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),

                // Close button — visible on hover or when active
                SizedBox(
                  width: 28,
                  height: 28,
                  child: AnimatedOpacity(
                    opacity: showClose ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 100),
                    child: _TabCloseButton(
                      onPressed: showClose ? widget.onClose : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _tabColor(ColorScheme cs) {
    if (widget.isActive) {
      // Active tab is slightly lighter than chrome background
      return AppTheme.chromeBackground.withValues(alpha: 1.0);
    }
    if (_hovered) {
      return cs.onSurface.withValues(alpha: 0.05);
    }
    return Colors.transparent;
  }
}

// ---------------------------------------------------------------------------
//  Close button
// ---------------------------------------------------------------------------

/// Tiny close button for a tab — styled as a subtle icon that brightens
/// on hover.
class _TabCloseButton extends StatefulWidget {
  const _TabCloseButton({this.onPressed});

  final VoidCallback? onPressed;

  @override
  State<_TabCloseButton> createState() => _TabCloseButtonState();
}

class _TabCloseButtonState extends State<_TabCloseButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: _hovered
                  ? cs.onSurface.withValues(alpha: 0.15)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(
              Icons.close,
              size: 14,
              color: _hovered
                  ? cs.onSurface
                  : cs.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
//  New tab button
// ---------------------------------------------------------------------------

/// The "+" button at the end of the tab bar for creating new tabs.
class _NewTabButton extends StatefulWidget {
  const _NewTabButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_NewTabButton> createState() => _NewTabButtonState();
}

class _NewTabButtonState extends State<_NewTabButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Tooltip(
      message: 'New Tab',
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: 36,
            height: 36,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: _hovered
                  ? cs.onSurface.withValues(alpha: 0.1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              Icons.add,
              size: 18,
              color: _hovered
                  ? cs.onSurface
                  : cs.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ),
      ),
    );
  }
}
