# Magnet Terminal

A production-grade terminal emulator for macOS built with Flutter, powered by [dart_xterm](https://github.com/cdrury526/dart_xterm) and [dart_pty](https://github.com/cdrury526/dart_pty).

## Features

- Native PTY with full escape sequence support
- Custom box-drawing and block element rendering
- Tabbed terminal sessions
- Integrated MCP devtools server for runtime introspection

## Architecture

```
magnet-terminal/          # Flutter desktop app
  ├── lib/
  │   ├── main.dart
  │   ├── app/            # App shell, routing, theming
  │   ├── terminal/       # Terminal widget, tab management
  │   └── devtools/       # Embedded MCP server for debugging
  └── dependencies:
      ├── dart_xterm      # Terminal emulator widget (local path)
      └── dart_pty        # Native PTY package (local path)
```

## Dependencies

| Package | Path | Purpose |
|---|---|---|
| dart_xterm | /Users/chrisdrury/projects/dart_xterm | Terminal rendering, escape sequence parsing |
| dart_pty | /Users/chrisdrury/projects/dart_pty | Native FFI PTY (posix_openpt, posix_spawn) |

## Development

```bash
flutter run -d macos
```
