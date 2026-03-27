/// Tab manager — orchestrates multiple terminal sessions.
///
/// Maintains a list of [TerminalSession]s and tracks the active tab.
/// Uses [ChangeNotifier] to drive UI rebuilds when tabs are added,
/// closed, reordered, or switched.
///
/// ## Invariants
/// - There is always at least one tab open. Closing the last tab
///   automatically creates a fresh default session.
/// - The [activeTabIndex] is always a valid index into [sessions].
/// - Maximum [maxTabs] tabs can be open simultaneously (default 20).
/// - Disposed sessions are never left in the list.
library;

import 'package:flutter/foundation.dart';

import 'terminal_session.dart';

/// Factory function for creating new [TerminalSession]s.
///
/// Allows injection of custom session creation logic for testing
/// and for future per-tab configuration (e.g., different shells,
/// working directories, SSH connections).
typedef SessionFactory = TerminalSession Function();

/// Manages the lifecycle of multiple terminal tabs.
///
/// Create a [TabManager], then call [addTab] to open terminal sessions.
/// The constructor automatically creates one initial tab so the app
/// never starts in an empty state.
///
/// Listen for changes via [addListener] (inherited from [ChangeNotifier])
/// to rebuild tab bar UI, terminal views, etc.
class TabManager with ChangeNotifier {
  /// Creates a tab manager and opens one initial tab.
  ///
  /// [sessionFactory] controls how new [TerminalSession]s are created.
  /// Defaults to creating a plain session with default settings.
  ///
  /// [maxTabs] sets the upper limit on simultaneously open tabs.
  /// Attempting to exceed this limit will return `false` from [addTab].
  TabManager({
    SessionFactory? sessionFactory,
    this.maxTabs = 20,
  }) : _sessionFactory = sessionFactory ?? TerminalSession.new {
    // Start with one tab so the app is never empty.
    _addSessionInternal();
  }

  /// Maximum number of tabs allowed.
  final int maxTabs;

  /// Factory used to create new terminal sessions.
  final SessionFactory _sessionFactory;

  // ---------------------------------------------------------------------------
  //  Public state
  // ---------------------------------------------------------------------------

  /// The currently open terminal sessions, in tab-bar order.
  ///
  /// Do not modify this list directly — use [addTab], [closeTab],
  /// [moveTab], etc. instead.
  List<TerminalSession> get sessions => List.unmodifiable(_sessions);

  /// The index of the currently active (visible) tab.
  int get activeTabIndex => _activeTabIndex;

  /// The currently active [TerminalSession].
  TerminalSession get activeSession => _sessions[_activeTabIndex];

  /// The number of currently open tabs.
  int get tabCount => _sessions.length;

  // ---------------------------------------------------------------------------
  //  Private state
  // ---------------------------------------------------------------------------

  final List<TerminalSession> _sessions = [];
  int _activeTabIndex = 0;
  bool _isDisposed = false;

  // ---------------------------------------------------------------------------
  //  Tab operations
  // ---------------------------------------------------------------------------

  /// Opens a new tab and makes it active.
  ///
  /// The new tab is inserted immediately after the current active tab.
  /// Returns `true` if the tab was created, `false` if the [maxTabs]
  /// limit has been reached.
  ///
  /// The session is created via the [SessionFactory] but not started —
  /// the caller (typically the terminal widget) is responsible for
  /// calling [TerminalSession.start] after the widget has been laid
  /// out and can provide initial column/row dimensions.
  bool addTab() {
    _assertNotDisposed();

    if (_sessions.length >= maxTabs) {
      debugPrint(
        'TabManager: cannot open new tab — limit of $maxTabs reached.',
      );
      return false;
    }

    final insertIndex = _activeTabIndex + 1;
    _addSessionInternal(insertAt: insertIndex);
    _activeTabIndex = insertIndex;

    // Note: _addSessionInternal already registers a listener for session
    // changes — do not add a second one here.

    notifyListeners();
    return true;
  }

  /// Closes the tab at [index].
  ///
  /// The closed session is [dispose]d, releasing its PTY and terminal
  /// resources. If the closed tab was the last one, a new default tab
  /// is automatically created (the app must never have zero tabs).
  ///
  /// If the active tab is closed, the selection moves to the nearest
  /// neighbor — preferring the tab to the left, or the tab to the
  /// right if the leftmost tab was closed.
  void closeTab(int index) {
    _assertNotDisposed();
    RangeError.checkValidIndex(index, _sessions, 'index');

    final session = _sessions.removeAt(index);
    session.dispose();

    if (_sessions.isEmpty) {
      // Never leave the app with zero tabs.
      _addSessionInternal();
      _activeTabIndex = 0;
    } else {
      // Adjust active index to stay valid.
      if (_activeTabIndex >= _sessions.length) {
        _activeTabIndex = _sessions.length - 1;
      } else if (_activeTabIndex > index) {
        // Active tab was to the right of the closed one — shift left.
        _activeTabIndex--;
      }
      // If activeTabIndex == index, we now point at the tab that slid
      // into the closed tab's position (the right neighbor), which is
      // the desired behavior.
    }

    notifyListeners();
  }

  /// Closes all tabs and opens a fresh default tab.
  ///
  /// Every existing session is [dispose]d.
  void closeAllTabs() {
    _assertNotDisposed();

    // Dispose all existing sessions.
    for (final session in _sessions) {
      session.dispose();
    }
    _sessions.clear();

    // Open a fresh default tab.
    _addSessionInternal();
    _activeTabIndex = 0;

    notifyListeners();
  }

  /// Switches the active tab to [index].
  ///
  /// Does nothing if [index] is already the active tab.
  void selectTab(int index) {
    _assertNotDisposed();
    RangeError.checkValidIndex(index, _sessions, 'index');

    if (_activeTabIndex == index) return;

    _activeTabIndex = index;
    notifyListeners();
  }

  /// Moves a tab from [fromIndex] to [toIndex].
  ///
  /// The active tab selection follows the moved tab — if the active
  /// tab is the one being moved, [activeTabIndex] is updated to its
  /// new position.
  ///
  /// This supports drag-and-drop reordering in the tab bar.
  void moveTab(int fromIndex, int toIndex) {
    _assertNotDisposed();
    RangeError.checkValidIndex(fromIndex, _sessions, 'fromIndex');

    // Clamp toIndex to valid range (allows inserting at the end).
    final clampedTo = toIndex.clamp(0, _sessions.length - 1);
    if (fromIndex == clampedTo) return;

    final session = _sessions.removeAt(fromIndex);
    _sessions.insert(clampedTo, session);

    // Update the active tab index to follow the move.
    if (_activeTabIndex == fromIndex) {
      // The moved tab was the active one — follow it.
      _activeTabIndex = clampedTo;
    } else if (fromIndex < _activeTabIndex && clampedTo >= _activeTabIndex) {
      // Moved a tab from before the active tab to after it.
      _activeTabIndex--;
    } else if (fromIndex > _activeTabIndex && clampedTo <= _activeTabIndex) {
      // Moved a tab from after the active tab to before it.
      _activeTabIndex++;
    }

    notifyListeners();
  }

  /// Switches to the next tab (wraps around to the first tab).
  void selectNextTab() {
    _assertNotDisposed();
    if (_sessions.length <= 1) return;
    selectTab((_activeTabIndex + 1) % _sessions.length);
  }

  /// Switches to the previous tab (wraps around to the last tab).
  void selectPreviousTab() {
    _assertNotDisposed();
    if (_sessions.length <= 1) return;
    selectTab((_activeTabIndex - 1 + _sessions.length) % _sessions.length);
  }

  // ---------------------------------------------------------------------------
  //  Dispose
  // ---------------------------------------------------------------------------

  /// Disposes all terminal sessions and releases resources.
  ///
  /// After disposal, all operations will throw [StateError].
  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;

    for (final session in _sessions) {
      session.dispose();
    }
    _sessions.clear();

    super.dispose();
  }

  // ---------------------------------------------------------------------------
  //  Internal helpers
  // ---------------------------------------------------------------------------

  /// Creates a session via the factory and inserts it into the list.
  ///
  /// Returns the created session. If [insertAt] is `null`, the session
  /// is appended at the end.
  TerminalSession _addSessionInternal({int? insertAt}) {
    final session = _sessionFactory();

    if (insertAt != null) {
      _sessions.insert(insertAt, session);
    } else {
      _sessions.add(session);
    }

    // Listen for session changes (title updates, exit status) so we
    // can forward them as tab-level change notifications.
    session.addListener(() => _onSessionChanged(session));

    return session;
  }

  /// Called when a child session's state changes (title, status, etc.).
  ///
  /// Forwards the change as a [TabManager] notification so the tab bar
  /// can update titles, show exit indicators, etc.
  void _onSessionChanged(TerminalSession session) {
    if (_isDisposed) return;

    // Only notify if the session is still in our list (it may have
    // been removed and disposed already).
    if (_sessions.contains(session)) {
      notifyListeners();
    }
  }

  void _assertNotDisposed() {
    if (_isDisposed) {
      throw StateError('TabManager has been disposed');
    }
  }
}
