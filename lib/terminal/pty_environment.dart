import 'dart:io' show Platform;

import 'package:dart_xterm/dart_xterm.dart';

/// Centralized PTY environment configuration for magnet-terminal.
///
/// Builds the environment variable map passed to [Pty.start] so that
/// child processes (shells and CLI apps) see correct terminal
/// capabilities, locale settings, and program identification.
///
/// ## Environment variables and their effects
///
/// ### Terminal capability advertisement
/// - **TERM** (`xterm-256color`): Tells ncurses/terminfo which capability
///   database entry to load. Most modern CLI apps require at least
///   `xterm-256color` for proper color and cursor support.
/// - **COLORTERM** (`truecolor`): Signals 24-bit RGB color support.
///   Apps like `bat`, `delta`, `lsd`, and rich-prompt shells check this
///   to decide whether to emit `\e[38;2;r;g;b` sequences.
///
/// ### Program identification
/// - **TERM_PROGRAM** (`magnet-terminal`): Identifies this terminal to
///   CLI apps. Claude Code, Codex CLI, and Gemini CLI inspect this to
///   enable terminal-specific features (e.g., inline images, hyperlinks).
/// - **TERM_PROGRAM_VERSION** (`0.1.0`): Companion to TERM_PROGRAM for
///   version-gated feature detection.
///
/// ### Hyperlink and rich-output support
/// - **FORCE_HYPERLINK** (`1`): THE critical env var for hyperlink support.
///   Claude Code (and all Node.js CLI apps using `terminal-link`) delegates
///   hyperlink detection to the `supports-hyperlinks` npm package
///   (https://github.com/chalk/supports-hyperlinks). That package uses a
///   PURELY environment-variable-based detection flow — it does NOT query
///   DA1, DA2, DECRQM, or any other escape sequences. Its decision tree:
///
///   1. `FORCE_HYPERLINK` set and != "0" -> **hyperlinks ON** (our fix)
///   2. `--no-hyperlink` CLI flag -> hyperlinks OFF
///   3. `supports-color` returns false -> hyperlinks OFF
///   4. `stream.isTTY` is false -> hyperlinks OFF
///   5. `WT_SESSION` set (Windows Terminal) -> hyperlinks ON
///   6. win32 platform -> hyperlinks OFF
///   7. `CI` env var set -> hyperlinks OFF
///   8. `TEAMCITY_VERSION` set -> hyperlinks OFF
///   9. `TERM_PROGRAM` switch — ONLY these values are recognized:
///      - `iTerm.app` (>= 3.1)
///      - `WezTerm` (>= 20200620)
///      - `vscode` (>= 1.72)
///      - `ghostty` (any version)
///      - `zed` (any version)
///      - **`magnet-terminal` is NOT in this list**
///   10. `VTE_VERSION` >= 0.50.1 -> hyperlinks ON
///   11. `TERM` switch — ONLY `alacritty` and `xterm-kitty` recognized
///       (`xterm-256color` is NOT recognized here)
///   12. Default -> **hyperlinks OFF**
///
///   Since `TERM_PROGRAM=magnet-terminal` is not in the allowlist (step 9)
///   and `TERM=xterm-256color` is not matched (step 11), without
///   `FORCE_HYPERLINK=1` the package returns false and Claude Code
///   falls back to SGR 4m underlines instead of OSC 8 hyperlinks.
///
///   Long-term fix: submit a PR to chalk/supports-hyperlinks adding
///   `magnet-terminal` to the TERM_PROGRAM switch. Until then,
///   FORCE_HYPERLINK=1 is the correct and stable workaround — it is
///   checked FIRST (step 1) and overrides all other logic.
///
/// - **COLORTERM** also influences hyperlink decisions in some apps.
///
/// ### Theme detection (Codex CLI and Rust CLI tools)
/// - **COLORFGBG** (`15;0`): Foreground/background color hint in the format
///   "fg;bg" where colors are 0-15 (standard terminal palette indices).
///   `15;0` = white-on-black (dark theme). Codex CLI uses the `termbg` Rust
///   crate which checks COLORFGBG first, then falls back to sending OSC 10/11
///   escape sequence queries. Since dart_xterm does not yet respond to
///   OSC 10/11, setting COLORFGBG prevents timeouts and garbled output.
///   Other Rust CLI tools (bat, delta, lsd) also use this for theme detection.
///
/// ### Locale and encoding
/// - **LANG** (`en_US.UTF-8`): Sets the default locale for the child
///   process. Many CLI tools use this to decide output encoding. Without
///   a UTF-8 locale, box-drawing characters, emoji, and non-ASCII text
///   may render as mojibake.
/// - **LC_ALL**: When set, overrides all LC_* category variables. We
///   only set this if it is already present in the parent environment to
///   avoid interfering with the user's locale preferences.
///
/// ### Inherited from the parent process
/// The following are copied from the Dart process environment so the
/// child shell can resolve the user's identity and locate programs:
/// - **HOME**, **USER**, **LOGNAME** — user identity and home directory
/// - **PATH** — executable search path
/// - **SHELL** — the user's preferred login shell (also used by
///   [defaultShell] to decide which shell to spawn)
/// - **TMPDIR** — temporary directory (macOS sets this per-session)
/// - **XPC_FLAGS**, **XPC_SERVICE_NAME** — macOS IPC (some tools need these)
/// - **SSH_AUTH_SOCK** — SSH agent socket for git/ssh passthrough
/// - **Apple_PubSub_Socket_Render** — macOS pasteboard bridge
/// - **DISPLAY** — X11 display (relevant if XQuartz is installed)
/// - **EDITOR**, **VISUAL** — user's preferred editor
/// - **HOMEBREW_PREFIX**, **HOMEBREW_CELLAR**, **HOMEBREW_REPOSITORY** —
///   Homebrew paths (many macOS dev tools depend on these)
class PtyEnvironment {
  PtyEnvironment._();

  /// The terminal type reported via the TERM variable.
  ///
  /// `xterm-256color` is the de-facto standard for modern terminal
  /// emulators and has the broadest compatibility with CLI apps.
  static const term = 'xterm-256color';

  /// The color capability level reported via COLORTERM.
  ///
  /// `truecolor` advertises 24-bit RGB support (16 million colors).
  static const colorTerm = 'truecolor';

  /// The terminal program name reported via TERM_PROGRAM.
  static const termProgram = 'magnet-terminal';

  /// The terminal program version reported via TERM_PROGRAM_VERSION.
  static const termProgramVersion = '0.1.0';

  /// Environment variables that are inherited from the parent Dart
  /// process when they exist. These are not overwritten.
  static const _inheritedKeys = <String>[
    'HOME',
    'USER',
    'LOGNAME',
    'PATH',
    'SHELL',
    'TMPDIR',
    'SSH_AUTH_SOCK',
    'XPC_FLAGS',
    'XPC_SERVICE_NAME',
    'Apple_PubSub_Socket_Render',
    'DISPLAY',
    'EDITOR',
    'VISUAL',
    'HOMEBREW_PREFIX',
    'HOMEBREW_CELLAR',
    'HOMEBREW_REPOSITORY',
    'LC_ALL',
  ];

  /// Returns the user's default shell path.
  ///
  /// Reads the `SHELL` environment variable from the parent process.
  /// Falls back to `/bin/zsh` on macOS (the default since Catalina)
  /// if SHELL is not set.
  ///
  /// **Phase rule:** Never hardcode `/bin/bash` or `/bin/zsh` as the
  /// shell to spawn. Always prefer the user's configured shell.
  static String get defaultShell {
    return Platform.environment['SHELL'] ?? '/bin/zsh';
  }

  /// Returns the user's home directory from the environment.
  ///
  /// Falls back to `/tmp` if HOME is not set (should never happen on
  /// a real macOS system, but avoids a null crash in edge cases).
  static String get homeDirectory {
    return Platform.environment['HOME'] ?? '/tmp';
  }

  /// Creates an [EscapeEmitter] configured for magnet-terminal.
  ///
  /// The emitter generates responses to terminal capability queries (DA1,
  /// DA2, DA3, XTVERSION, DECRQM). These responses work in tandem with
  /// the environment variables set by [buildEnvironment].
  ///
  /// **Important:** These escape responses do NOT affect hyperlink detection
  /// in Node.js CLI apps (Claude Code, etc.). The `supports-hyperlinks`
  /// npm package uses only environment variables (FORCE_HYPERLINK,
  /// TERM_PROGRAM, TERM). DA/DA2/DECRQM responses matter for OTHER apps
  /// like vim, htop, less, and tmux that query terminal capabilities via
  /// escape sequences.
  ///
  /// - **DA1** (`CSI c`): Responds `\e[?1;2c` (VT100 + AVO), matching
  ///   xterm.js. This is the safest response for broad CLI compatibility.
  ///
  /// - **DA2** (`CSI > c`): Responds `\e[>0;100;0c` (VT100 type, version
  ///   100). The version 100 avoids xterm version-sniffing while signaling
  ///   modern capabilities.
  ///
  /// - **DA3** (`CSI = c`): Responds with unit ID `4D41474E` ("MAGN").
  ///
  /// - **XTVERSION** (`CSI > 0 q`): Responds with
  ///   `DCS > | magnet-terminal(0.1.0) ST`. CLI apps use this alongside
  ///   TERM_PROGRAM for terminal identification.
  ///
  /// - **DECRQM** (`CSI ? Ps $ p` / `CSI Ps $ p`): Reports the current
  ///   state of terminal modes. This is how apps discover whether features
  ///   like bracketed paste, focus reporting, or mouse modes are active.
  ///
  /// Why these specific values:
  /// - iTerm2 sends `\e[?62;4c` (VT220+Sixel) but we use the xterm.js
  ///   response because TERM=xterm-256color and most apps expect xterm
  ///   behavior from an xterm TERM value.
  /// - The version code 100 was chosen to be lower than xterm's 276 to
  ///   avoid triggering xterm-specific workarounds in apps that version-sniff.
  static EscapeEmitter buildEmitter() {
    return const EscapeEmitter(
      termName: termProgram,
      termVersion: termProgramVersion,
      // DA1: VT100 with Advanced Video Option — same as xterm.js.
      // This is the broadest-compatible response for TERM=xterm-256color.
      da1Response: '\x1b[?1;2c',
      // DA2: VT100 type (0), firmware version 100, ROM cartridge 0.
      da2ModelCode: 0,
      da2VersionCode: 100,
      // DA3: Unit ID "MAGN" in hex (4D 41 47 4E).
      da3UnitId: '4D41474E',
    );
  }

  /// Builds the complete environment map for a PTY child process.
  ///
  /// The map is built in three layers:
  /// 1. **Inherited vars** — copied from the parent Dart process if present
  /// 2. **Terminal capability vars** — TERM, COLORTERM, TERM_PROGRAM, etc.
  /// 3. **Locale vars** — LANG for UTF-8 encoding
  ///
  /// [extraVars] allows callers to inject additional variables (e.g., for
  /// testing or per-session overrides). These are applied last and can
  /// override any of the above.
  ///
  /// When [environment] on `Pty.start` receives `null`, the child inherits
  /// the **entire** parent environment — but then we lose the ability to
  /// inject TERM_PROGRAM and other terminal-specific vars. So we always
  /// pass an explicit map that starts from the inherited subset and layers
  /// our additions on top.
  static Map<String, String> buildEnvironment({
    Map<String, String>? extraVars,
  }) {
    final env = <String, String>{};

    // Layer 1: Inherit essential vars from the parent process.
    final parentEnv = Platform.environment;
    for (final key in _inheritedKeys) {
      final value = parentEnv[key];
      if (value != null) {
        env[key] = value;
      }
    }

    // Layer 2: Terminal capability and identification.
    env['TERM'] = term;
    env['COLORTERM'] = colorTerm;
    env['TERM_PROGRAM'] = termProgram;
    env['TERM_PROGRAM_VERSION'] = termProgramVersion;

    // FORCE_HYPERLINK=1 is REQUIRED for hyperlink support in Node.js CLI
    // apps (Claude Code, Codex CLI, etc.) because magnet-terminal is not
    // in the supports-hyperlinks package's TERM_PROGRAM allowlist.
    // This env var is checked FIRST in the detection flow and overrides
    // all other checks. See the class doc above for the full decision tree.
    // To verify this is working, run: scripts/diagnose_hyperlinks.sh
    env['FORCE_HYPERLINK'] = '1';

    // COLORFGBG — Foreground/background color hint for theme detection.
    // Codex CLI (Rust, uses termbg) checks this FIRST when auto-detecting
    // dark vs. light theme. Format is "fg;bg" where 0=black, 15=white.
    // "15;0" means light-on-dark (dark theme). Without this, termbg falls
    // back to sending OSC 10/11 escape sequence queries to the terminal.
    // dart_xterm does NOT yet respond to OSC 10/11 queries, so without
    // COLORFGBG set, termbg times out and may produce garbled output.
    // Other Rust CLI tools (bat, delta, lsd) also use this for theme.
    // TODO: Add OSC 10/11 query response support to dart_xterm so termbg
    // can auto-detect colors even without this env var.
    env['COLORFGBG'] = '15;0';

    // TERM_PROGRAM_BACKGROUND — explicit dark/light hint for Codex CLI.
    // Codex CLI's theme auto-detection checks (in order):
    //   1. $COLORFGBG
    //   2. $TERM_PROGRAM_BACKGROUND
    //   3. OSC 10/11 escape sequence query
    //   4. Windows registry (not applicable on macOS)
    // Setting this alongside COLORFGBG provides a belt-and-suspenders
    // approach: if any CLI only checks one of the two, we're covered.
    // Valid values: "dark" or "light".
    // TODO: When magnet-terminal supports user-configurable themes, derive
    // this dynamically from the active TerminalTheme brightness.
    env['TERM_PROGRAM_BACKGROUND'] = 'dark';

    // Layer 3: Locale — ensure UTF-8 encoding for proper glyph rendering.
    // Only set LANG if the user has not already set LC_ALL (which takes
    // precedence over LANG in POSIX).
    if (!env.containsKey('LC_ALL')) {
      env['LANG'] = parentEnv['LANG'] ?? 'en_US.UTF-8';
    }

    // Layer 4: Caller overrides.
    if (extraVars != null) {
      env.addAll(extraVars);
    }

    return env;
  }
}
