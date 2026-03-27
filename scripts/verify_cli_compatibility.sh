#!/usr/bin/env bash
# verify_cli_compatibility.sh — Comprehensive compatibility verification for
# AI CLI tools (Claude Code, Codex CLI, Gemini CLI) running inside magnet-terminal.
#
# This script tests ALL environment variables and terminal capabilities that
# these three CLI tools check when deciding what features to enable. Run it
# inside magnet-terminal to verify the PTY environment is correctly configured.
#
# ## What each CLI tool checks
#
# ### Claude Code (Node.js, uses chalk ecosystem)
#   - supports-hyperlinks: FORCE_HYPERLINK > TERM_PROGRAM > TERM (env vars only)
#   - supports-color: FORCE_COLOR > COLORTERM > TERM (env vars only)
#   - NO escape sequence queries for feature detection
#   - Uses chalk for styling, ink for TUI rendering
#
# ### Codex CLI (Rust, uses termbg + crossterm)
#   - Theme detection: $COLORFGBG > $TERM_PROGRAM_BACKGROUND > OSC 10/11 query
#   - Color support: COLORTERM, TERM, FORCE_COLOR
#   - Keyboard: Kitty keyboard protocol detection (CSI ? u query)
#   - Mouse: SGR mouse mode (1006)
#   - The OSC 10/11 query sends escape sequences and reads the terminal's response
#     to detect foreground/background colors for auto dark/light theme detection
#
# ### Gemini CLI (Node.js, uses chalk ecosystem)
#   - Same as Claude Code for color/hyperlink detection (chalk, supports-hyperlinks)
#   - IDE detection: TERM_PROGRAM (checks for "vscode" and others)
#   - TERMINAL_EMULATOR env var for JetBrains detection
#   - Uses ink for TUI rendering
#
# Usage: Run this script inside a magnet-terminal shell tab.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

pass=0
warn=0
fail=0
info=0

check_pass() {
  echo -e "  ${GREEN}PASS${RESET}  $1"
  ((pass++))
}
check_warn() {
  echo -e "  ${YELLOW}WARN${RESET}  $1"
  ((warn++))
}
check_fail() {
  echo -e "  ${RED}FAIL${RESET}  $1"
  ((fail++))
}
check_info() {
  echo -e "  ${DIM}INFO${RESET}  $1"
  ((info++))
}

echo ""
echo -e "${BOLD}================================================================${RESET}"
echo -e "${BOLD}  Magnet Terminal — AI CLI Compatibility Verification${RESET}"
echo -e "${BOLD}================================================================${RESET}"
echo ""

# ============================================================================
# Section 1: Core Terminal Identity (all three CLIs)
# ============================================================================
echo -e "${CYAN}[1/8] Core Terminal Identity${RESET}"
echo -e "${DIM}     Checked by: Claude Code, Codex CLI, Gemini CLI${RESET}"
echo ""

# TERM
if [[ -n "${TERM:-}" ]]; then
  if [[ "$TERM" == "xterm-256color" ]]; then
    check_pass "TERM=$TERM (standard, broadest compatibility)"
  elif [[ "$TERM" == "xterm-kitty" || "$TERM" == "alacritty" ]]; then
    check_pass "TERM=$TERM (recognized by supports-hyperlinks)"
  else
    check_warn "TERM=$TERM (non-standard, may cause compatibility issues)"
  fi
else
  check_fail "TERM is not set (required for all CLI tools)"
fi

# TERM_PROGRAM
if [[ -n "${TERM_PROGRAM:-}" ]]; then
  check_pass "TERM_PROGRAM=$TERM_PROGRAM"
  if [[ "$TERM_PROGRAM" != "magnet-terminal" ]]; then
    check_warn "  Expected 'magnet-terminal', got '$TERM_PROGRAM'"
  fi
else
  check_fail "TERM_PROGRAM is not set (needed for terminal identification)"
fi

# TERM_PROGRAM_VERSION
if [[ -n "${TERM_PROGRAM_VERSION:-}" ]]; then
  check_pass "TERM_PROGRAM_VERSION=$TERM_PROGRAM_VERSION"
else
  check_warn "TERM_PROGRAM_VERSION is not set"
fi

echo ""

# ============================================================================
# Section 2: Color Support (all three CLIs)
# ============================================================================
echo -e "${CYAN}[2/8] Color Support${RESET}"
echo -e "${DIM}     Checked by: chalk/supports-color (Claude Code, Gemini CLI), crossterm (Codex CLI)${RESET}"
echo ""

# COLORTERM
if [[ -n "${COLORTERM:-}" ]]; then
  if [[ "$COLORTERM" == "truecolor" ]]; then
    check_pass "COLORTERM=truecolor (24-bit / 16M colors advertised)"
  elif [[ "$COLORTERM" == "24bit" ]]; then
    check_pass "COLORTERM=24bit (truecolor alternative notation)"
  else
    check_warn "COLORTERM=$COLORTERM (expected 'truecolor' for full color support)"
  fi
else
  check_fail "COLORTERM is not set (apps will fall back to 256 colors max)"
fi

# FORCE_COLOR — overrides supports-color detection
if [[ -n "${FORCE_COLOR:-}" ]]; then
  case "$FORCE_COLOR" in
    0) check_warn "FORCE_COLOR=0 (color explicitly disabled)" ;;
    1) check_info "FORCE_COLOR=1 (16 colors forced)" ;;
    2) check_info "FORCE_COLOR=2 (256 colors forced)" ;;
    3) check_pass "FORCE_COLOR=3 (truecolor forced)" ;;
    *) check_info "FORCE_COLOR=$FORCE_COLOR (treated as truthy by supports-color)" ;;
  esac
else
  check_info "FORCE_COLOR is not set (detection uses COLORTERM/TERM — this is fine)"
fi

# Color rendering test
echo ""
echo "  Color rendering test:"
echo -e "    16-color:  ${RED}RED${RESET} ${GREEN}GREEN${RESET} \033[0;34mBLUE${RESET} ${YELLOW}YELLOW${RESET} \033[0;35mMAGENTA${RESET} ${CYAN}CYAN${RESET}"
echo -ne "    256-color: "
for i in 196 202 208 214 220 226 190 154 118 82 46 47 48 49 50 51; do
  printf "\033[48;5;%dm  \033[0m" "$i"
done
echo ""
echo -ne "    Truecolor: "
for i in $(seq 0 15 255); do
  printf "\033[48;2;%d;0;%dm  \033[0m" "$i" "$((255 - i))"
done
echo ""

echo ""

# ============================================================================
# Section 3: Hyperlink Support (Claude Code, Gemini CLI)
# ============================================================================
echo -e "${CYAN}[3/8] Hyperlink Support (OSC 8)${RESET}"
echo -e "${DIM}     Checked by: chalk/supports-hyperlinks (Claude Code, Gemini CLI)${RESET}"
echo ""

# FORCE_HYPERLINK — the critical override
if [[ -n "${FORCE_HYPERLINK:-}" ]]; then
  if [[ "$FORCE_HYPERLINK" == "1" ]]; then
    check_pass "FORCE_HYPERLINK=1 (hyperlinks forced ON — primary fix for magnet-terminal)"
  elif [[ "$FORCE_HYPERLINK" == "0" ]]; then
    check_fail "FORCE_HYPERLINK=0 (hyperlinks explicitly disabled!)"
  else
    check_warn "FORCE_HYPERLINK=$FORCE_HYPERLINK (non-standard value)"
  fi
else
  check_fail "FORCE_HYPERLINK not set (magnet-terminal is not in supports-hyperlinks allowlist)"
fi

# Check for blockers
if [[ -n "${CI:-}" ]]; then
  check_fail "CI=$CI (supports-hyperlinks disables hyperlinks when CI is set!)"
else
  check_pass "CI is not set (good — CI env var blocks hyperlink detection)"
fi

if [[ -n "${TEAMCITY_VERSION:-}" ]]; then
  check_warn "TEAMCITY_VERSION set (blocks hyperlink detection)"
else
  check_pass "TEAMCITY_VERSION is not set"
fi

# OSC 8 rendering test
echo ""
echo "  OSC 8 hyperlink rendering test (Cmd+click should open link):"
printf '    \033]8;;https://github.com/cdrury526/dart_xterm\033\\dart_xterm on GitHub\033]8;;\033\\\n'
echo ""

echo ""

# ============================================================================
# Section 4: Theme Detection (Codex CLI)
# ============================================================================
echo -e "${CYAN}[4/8] Theme / Background Detection${RESET}"
echo -e "${DIM}     Checked by: termbg (Codex CLI), bat, delta, and other Rust CLI tools${RESET}"
echo ""

# COLORFGBG — static foreground/background hint
if [[ -n "${COLORFGBG:-}" ]]; then
  check_pass "COLORFGBG=$COLORFGBG (fg;bg color hint for theme detection)"
else
  check_warn "COLORFGBG not set (Codex CLI will fall back to OSC 10/11 queries)"
  check_info "  Set COLORFGBG=15;0 for dark themes or COLORFGBG=0;15 for light themes"
fi

# TERM_PROGRAM_BACKGROUND — direct theme hint
if [[ -n "${TERM_PROGRAM_BACKGROUND:-}" ]]; then
  check_pass "TERM_PROGRAM_BACKGROUND=$TERM_PROGRAM_BACKGROUND"
else
  check_info "TERM_PROGRAM_BACKGROUND not set (optional — used by some Rust CLIs)"
fi

# OSC 10/11 query test — this is what termbg sends to detect bg color
echo ""
echo "  OSC 10/11 color query test:"
echo -e "  ${DIM}(termbg sends OSC 10 ? and OSC 11 ? to query fg/bg colors)${RESET}"
if [[ -t 0 ]] && [[ -t 1 ]]; then
  old_stty=$(stty -g 2>/dev/null || true)
  if [[ -n "$old_stty" ]]; then
    stty raw -echo min 0 time 5 2>/dev/null || true
    # Send OSC 11 query (background color)
    printf '\033]11;?\033\\' > /dev/tty
    osc11_response=""
    while IFS= read -r -n 1 -t 1 char 2>/dev/null; do
      osc11_response+="$char"
      if [[ "$char" == "\\" ]] || [[ "$char" == $'\a' ]]; then
        break
      fi
      # Safety: don't read more than 100 chars
      if [[ ${#osc11_response} -gt 100 ]]; then
        break
      fi
    done
    stty "$old_stty" 2>/dev/null || true

    if [[ -n "$osc11_response" ]]; then
      visible=$(echo -n "$osc11_response" | cat -v)
      check_pass "OSC 11 response received: $visible"
      check_info "  Codex CLI termbg can auto-detect dark/light theme"
    else
      check_warn "OSC 11: no response (timeout)"
      check_info "  Codex CLI will fall back to COLORFGBG or default dark theme"
      check_info "  Consider adding OSC 10/11 query responses to dart_xterm"
    fi
  fi
else
  check_warn "Cannot test OSC 11 (not a TTY)"
fi

echo ""

# ============================================================================
# Section 5: Locale & Encoding (all three CLIs)
# ============================================================================
echo -e "${CYAN}[5/8] Locale & Encoding${RESET}"
echo -e "${DIM}     Checked by: all CLI tools (affects Unicode rendering)${RESET}"
echo ""

if [[ -n "${LANG:-}" ]]; then
  if [[ "$LANG" == *"UTF-8"* ]] || [[ "$LANG" == *"utf-8"* ]] || [[ "$LANG" == *"utf8"* ]]; then
    check_pass "LANG=$LANG (UTF-8 encoding)"
  else
    check_warn "LANG=$LANG (not UTF-8 — Unicode may render incorrectly)"
  fi
else
  check_warn "LANG not set (may cause encoding issues)"
fi

if [[ -n "${LC_ALL:-}" ]]; then
  check_info "LC_ALL=$LC_ALL (overrides LANG)"
fi

# Unicode rendering test
echo ""
echo "  Unicode rendering test:"
echo "    Box drawing: ┌─────────┐"
echo "    Box drawing: │ Hello!  │"
echo "    Box drawing: └─────────┘"
echo "    Arrows:      ← → ↑ ↓"
echo "    Braille:     ⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏ (spinner chars)"
echo "    Emoji:       ✓ ✗ ⚡ 🔍 📦"
echo ""

echo ""

# ============================================================================
# Section 6: TTY & Process Environment
# ============================================================================
echo -e "${CYAN}[6/8] TTY & Process Environment${RESET}"
echo -e "${DIM}     Checked by: Node.js isTTY, Rust is_terminal()${RESET}"
echo ""

if [[ -t 0 ]]; then
  check_pass "stdin is a TTY"
else
  check_fail "stdin is NOT a TTY (interactive input will not work)"
fi

if [[ -t 1 ]]; then
  check_pass "stdout is a TTY"
else
  check_fail "stdout is NOT a TTY (color and hyperlink detection will fail)"
fi

if [[ -t 2 ]]; then
  check_pass "stderr is a TTY"
else
  check_warn "stderr is NOT a TTY"
fi

# Shell environment
if [[ -n "${HOME:-}" ]]; then
  check_pass "HOME=$HOME"
else
  check_fail "HOME not set"
fi

if [[ -n "${PATH:-}" ]]; then
  check_pass "PATH is set (${#PATH} chars)"
else
  check_fail "PATH not set"
fi

if [[ -n "${SHELL:-}" ]]; then
  check_pass "SHELL=$SHELL"
else
  check_warn "SHELL not set"
fi

if [[ -n "${USER:-}" ]]; then
  check_pass "USER=$USER"
else
  check_warn "USER not set"
fi

if [[ -n "${SSH_AUTH_SOCK:-}" ]]; then
  check_pass "SSH_AUTH_SOCK set (git SSH will work)"
else
  check_warn "SSH_AUTH_SOCK not set (git over SSH may not work)"
fi

echo ""

# ============================================================================
# Section 7: Terminal Capability Responses (DA1/DA2/XTVERSION)
# ============================================================================
echo -e "${CYAN}[7/8] Escape Sequence Capabilities${RESET}"
echo -e "${DIM}     Checked by: vim, htop, less, tmux, ncurses apps (NOT Claude Code/Gemini CLI)${RESET}"
echo ""

if [[ -t 0 ]] && [[ -t 1 ]]; then
  old_stty=$(stty -g 2>/dev/null || true)

  if [[ -n "$old_stty" ]]; then
    # DA1 query
    stty raw -echo min 0 time 5 2>/dev/null || true
    printf '\033[c' > /dev/tty
    da1_response=""
    while IFS= read -r -n 1 -t 1 char 2>/dev/null; do
      da1_response+="$char"
      if [[ "$char" == "c" ]]; then break; fi
      if [[ ${#da1_response} -gt 50 ]]; then break; fi
    done
    stty "$old_stty" 2>/dev/null || true

    if [[ -n "$da1_response" ]]; then
      visible=$(echo -n "$da1_response" | cat -v)
      check_pass "DA1 response: $visible"
    else
      check_warn "DA1: no response (timeout)"
    fi

    # DA2 query
    stty raw -echo min 0 time 5 2>/dev/null || true
    printf '\033[>c' > /dev/tty
    da2_response=""
    while IFS= read -r -n 1 -t 1 char 2>/dev/null; do
      da2_response+="$char"
      if [[ "$char" == "c" ]]; then break; fi
      if [[ ${#da2_response} -gt 50 ]]; then break; fi
    done
    stty "$old_stty" 2>/dev/null || true

    if [[ -n "$da2_response" ]]; then
      visible=$(echo -n "$da2_response" | cat -v)
      check_pass "DA2 response: $visible"
    else
      check_warn "DA2: no response (timeout)"
    fi

    # XTVERSION query
    stty raw -echo min 0 time 5 2>/dev/null || true
    printf '\033[>0q' > /dev/tty
    xtver_response=""
    while IFS= read -r -n 1 -t 1 char 2>/dev/null; do
      xtver_response+="$char"
      if [[ "$char" == "\\" ]]; then break; fi
      if [[ "$char" == $'\a' ]]; then break; fi
      if [[ ${#xtver_response} -gt 100 ]]; then break; fi
    done
    stty "$old_stty" 2>/dev/null || true

    if [[ -n "$xtver_response" ]]; then
      visible=$(echo -n "$xtver_response" | cat -v)
      check_pass "XTVERSION response: $visible"
    else
      check_warn "XTVERSION: no response (timeout)"
    fi
  fi
else
  check_warn "Cannot query DA/XTVERSION (not a TTY)"
fi

echo ""

# ============================================================================
# Section 8: Keyboard & Input (all three CLIs)
# ============================================================================
echo -e "${CYAN}[8/8] Keyboard Protocol Notes${RESET}"
echo -e "${DIM}     Relevant for: Codex CLI (crossterm), interactive prompts${RESET}"
echo ""

check_info "Codex CLI uses crossterm which may query Kitty keyboard protocol (CSI ? u)"
check_info "If Kitty protocol is not supported, crossterm falls back to standard xterm input"
check_info "Arrow keys, Backspace, Enter, Ctrl+C must all generate correct escape sequences"
check_info "Bracketed paste mode (DECSET 2004) should be supported for safe paste handling"

echo ""

# ============================================================================
# Summary
# ============================================================================
echo -e "${BOLD}================================================================${RESET}"
echo -e "${BOLD}  Summary${RESET}"
echo -e "${BOLD}================================================================${RESET}"
echo ""
echo -e "  ${GREEN}PASS${RESET}: $pass    ${YELLOW}WARN${RESET}: $warn    ${RED}FAIL${RESET}: $fail    ${DIM}INFO${RESET}: $info"
echo ""

if [[ $fail -eq 0 ]]; then
  echo -e "  ${GREEN}${BOLD}VERDICT: Environment looks good for AI CLI tools.${RESET}"
  echo ""
  if [[ $warn -gt 0 ]]; then
    echo "  There are some warnings to review, but no blockers."
  fi
else
  echo -e "  ${RED}${BOLD}VERDICT: There are $fail failing checks.${RESET}"
  echo "  Review the FAIL items above before running CLI tools."
fi

echo ""
echo -e "${BOLD}  Per-CLI Status:${RESET}"
echo ""

# Claude Code verdict
if [[ "${FORCE_HYPERLINK:-}" == "1" ]] && [[ -n "${COLORTERM:-}" ]] && [[ -z "${CI:-}" ]]; then
  echo -e "  ${GREEN}Claude Code${RESET}:  Hyperlinks ON, truecolor ON, ready to use"
else
  echo -e "  ${YELLOW}Claude Code${RESET}:  Check FORCE_HYPERLINK and COLORTERM settings"
fi

# Codex CLI verdict
if [[ -n "${COLORTERM:-}" ]] && [[ -n "${TERM:-}" ]]; then
  if [[ -n "${COLORFGBG:-}" ]]; then
    echo -e "  ${GREEN}Codex CLI${RESET}:    Colors OK, theme detection via COLORFGBG"
  else
    echo -e "  ${YELLOW}Codex CLI${RESET}:    Colors OK, theme detection may need OSC 10/11 support or COLORFGBG"
  fi
else
  echo -e "  ${RED}Codex CLI${RESET}:    Check TERM and COLORTERM settings"
fi

# Gemini CLI verdict
if [[ "${FORCE_HYPERLINK:-}" == "1" ]] && [[ -n "${COLORTERM:-}" ]]; then
  echo -e "  ${GREEN}Gemini CLI${RESET}:   Hyperlinks ON, truecolor ON, ready to use"
else
  echo -e "  ${YELLOW}Gemini CLI${RESET}:   Check FORCE_HYPERLINK and COLORTERM settings"
fi

echo ""
echo "  For detailed hyperlink diagnostics: scripts/diagnose_hyperlinks.sh"
echo "  For more info: https://github.com/chalk/supports-hyperlinks"
echo ""
