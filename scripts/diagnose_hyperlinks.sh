#!/usr/bin/env bash
# diagnose_hyperlinks.sh — Run inside magnet-terminal to verify hyperlink
# capability detection.
#
# This script checks the same environment variables and conditions that the
# npm `supports-hyperlinks` package (v3.x, chalk/supports-hyperlinks) uses
# to decide whether to emit OSC 8 hyperlinks or fall back to plain text.
#
# Claude Code, Codex CLI, and other Node.js CLI tools use `supports-hyperlinks`
# (via `terminal-link`) to make this decision. The detection is PURELY
# environment-variable based — no escape sequence queries (DA1/DA2/DECRQM)
# are involved.
#
# Detection flow in supports-hyperlinks (in priority order):
#   1. FORCE_HYPERLINK set and != 0  -> hyperlinks ON  (our primary fix)
#   2. --no-hyperlink CLI flag       -> hyperlinks OFF
#   3. supports-color returns false  -> hyperlinks OFF
#   4. stream.isTTY is false         -> hyperlinks OFF
#   5. WT_SESSION set (Win Terminal) -> hyperlinks ON
#   6. win32 platform                -> hyperlinks OFF
#   7. CI env var set                -> hyperlinks OFF
#   8. TEAMCITY_VERSION set          -> hyperlinks OFF
#   9. TERM_PROGRAM switch:
#        iTerm.app (>= 3.1)         -> hyperlinks ON
#        WezTerm (>= 20200620)      -> hyperlinks ON
#        vscode (>= 1.72)           -> hyperlinks ON
#        ghostty                     -> hyperlinks ON
#        zed                         -> hyperlinks ON
#        (anything else)             -> fall through
#  10. VTE_VERSION >= 0.50.1         -> hyperlinks ON
#  11. TERM switch:
#        alacritty                   -> hyperlinks ON
#        xterm-kitty                 -> hyperlinks ON
#  12. Default                       -> hyperlinks OFF
#
# Since TERM_PROGRAM=magnet-terminal is NOT in the recognized list (step 9),
# and TERM=xterm-256color is NOT alacritty/xterm-kitty (step 11), the library
# returns false UNLESS FORCE_HYPERLINK=1 is set (step 1).
#
# Usage: Run this script in the magnet-terminal shell to verify env vars.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

pass=0
warn=0
fail=0

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

echo ""
echo -e "${BOLD}=== Magnet Terminal — Hyperlink Capability Diagnostic ===${RESET}"
echo ""

# ---------------------------------------------------------------------------
# Section 1: Environment variables (the ONLY thing supports-hyperlinks checks)
# ---------------------------------------------------------------------------
echo -e "${CYAN}--- Environment Variables (supports-hyperlinks detection) ---${RESET}"

# FORCE_HYPERLINK — the override that makes everything work
if [[ -n "${FORCE_HYPERLINK:-}" ]]; then
  if [[ "$FORCE_HYPERLINK" == "1" ]]; then
    check_pass "FORCE_HYPERLINK=$FORCE_HYPERLINK (hyperlinks forced ON — this is the primary fix)"
  elif [[ "$FORCE_HYPERLINK" == "0" ]]; then
    check_fail "FORCE_HYPERLINK=0 (hyperlinks explicitly disabled!)"
  else
    check_warn "FORCE_HYPERLINK=$FORCE_HYPERLINK (non-standard value, treated as truthy)"
  fi
else
  check_fail "FORCE_HYPERLINK is not set (without this, magnet-terminal is not recognized)"
fi

# TERM_PROGRAM — checked by supports-hyperlinks but magnet-terminal is NOT recognized
if [[ -n "${TERM_PROGRAM:-}" ]]; then
  case "$TERM_PROGRAM" in
    iTerm.app|WezTerm|vscode|ghostty|zed)
      check_pass "TERM_PROGRAM=$TERM_PROGRAM (recognized by supports-hyperlinks)"
      ;;
    magnet-terminal)
      check_warn "TERM_PROGRAM=$TERM_PROGRAM (NOT in supports-hyperlinks allowlist — needs FORCE_HYPERLINK=1)"
      ;;
    *)
      check_warn "TERM_PROGRAM=$TERM_PROGRAM (unknown to supports-hyperlinks)"
      ;;
  esac
else
  check_fail "TERM_PROGRAM is not set"
fi

# TERM_PROGRAM_VERSION
if [[ -n "${TERM_PROGRAM_VERSION:-}" ]]; then
  check_pass "TERM_PROGRAM_VERSION=$TERM_PROGRAM_VERSION"
else
  check_warn "TERM_PROGRAM_VERSION is not set"
fi

# TERM
if [[ -n "${TERM:-}" ]]; then
  case "$TERM" in
    xterm-256color)
      check_pass "TERM=$TERM (standard, good compatibility)"
      ;;
    alacritty|xterm-kitty)
      check_pass "TERM=$TERM (recognized by supports-hyperlinks for hyperlink support)"
      ;;
    *)
      check_warn "TERM=$TERM (non-standard)"
      ;;
  esac
else
  check_fail "TERM is not set"
fi

# COLORTERM
if [[ -n "${COLORTERM:-}" ]]; then
  if [[ "$COLORTERM" == "truecolor" ]]; then
    check_pass "COLORTERM=$COLORTERM (24-bit color advertised)"
  else
    check_warn "COLORTERM=$COLORTERM (expected 'truecolor')"
  fi
else
  check_warn "COLORTERM is not set (some apps use this for color detection)"
fi

# CI — if set, supports-hyperlinks returns false (even with TERM_PROGRAM match)
if [[ -n "${CI:-}" ]]; then
  check_warn "CI=$CI (supports-hyperlinks disables hyperlinks when CI is set)"
else
  check_pass "CI is not set (good — CI blocks hyperlink detection)"
fi

# TEAMCITY_VERSION — blocks hyperlinks
if [[ -n "${TEAMCITY_VERSION:-}" ]]; then
  check_warn "TEAMCITY_VERSION=$TEAMCITY_VERSION (blocks hyperlink detection)"
else
  check_pass "TEAMCITY_VERSION is not set"
fi

echo ""

# ---------------------------------------------------------------------------
# Section 2: TTY check
# ---------------------------------------------------------------------------
echo -e "${CYAN}--- TTY Status ---${RESET}"

if [[ -t 1 ]]; then
  check_pass "stdout is a TTY"
else
  check_fail "stdout is NOT a TTY (supports-hyperlinks requires isTTY)"
fi

if [[ -t 0 ]]; then
  check_pass "stdin is a TTY"
else
  check_warn "stdin is NOT a TTY"
fi

echo ""

# ---------------------------------------------------------------------------
# Section 3: Locale / encoding
# ---------------------------------------------------------------------------
echo -e "${CYAN}--- Locale & Encoding ---${RESET}"

if [[ -n "${LANG:-}" ]]; then
  if [[ "$LANG" == *"UTF-8"* ]] || [[ "$LANG" == *"utf-8"* ]]; then
    check_pass "LANG=$LANG (UTF-8)"
  else
    check_warn "LANG=$LANG (not UTF-8 — may cause rendering issues)"
  fi
else
  check_warn "LANG is not set"
fi

echo ""

# ---------------------------------------------------------------------------
# Section 4: OSC 8 hyperlink rendering test
# ---------------------------------------------------------------------------
echo -e "${CYAN}--- OSC 8 Hyperlink Rendering Test ---${RESET}"
echo ""
echo "  The following line should appear as a clickable link (Cmd+click):"
echo ""
printf '  \033]8;;https://example.com\033\\Click here for example.com\033]8;;\033\\\n'
echo ""
echo "  If you see plain text 'Click here for example.com' with no link,"
echo "  then OSC 8 parsing in dart_xterm may not be rendering hyperlinks"
echo "  in the TerminalView widget (separate from CLI app detection)."
echo ""

# ---------------------------------------------------------------------------
# Section 5: Capability query test (DA1/DA2 — informational only)
# ---------------------------------------------------------------------------
echo -e "${CYAN}--- Terminal Capability Responses (informational) ---${RESET}"
echo ""
echo "  NOTE: supports-hyperlinks does NOT use DA1/DA2/DECRQM queries."
echo "  These responses matter for OTHER apps (vim, htop, less, tmux) but"
echo "  do not affect Claude Code's hyperlink decision."
echo ""

# Send DA1 query and capture response
if [[ -t 0 ]] && [[ -t 1 ]]; then
  # Save terminal settings
  old_stty=$(stty -g 2>/dev/null || true)

  if [[ -n "$old_stty" ]]; then
    # DA1 query
    stty raw -echo min 0 time 5 2>/dev/null || true
    printf '\033[c' > /dev/tty
    da1_response=""
    while IFS= read -r -n 1 -t 1 char 2>/dev/null; do
      da1_response+="$char"
      # DA response ends with 'c'
      if [[ "$char" == "c" ]]; then
        break
      fi
    done
    stty "$old_stty" 2>/dev/null || true

    if [[ -n "$da1_response" ]]; then
      # Convert escape chars to visible form
      visible=$(echo -n "$da1_response" | cat -v)
      check_pass "DA1 response received: $visible"
    else
      check_warn "DA1 response: no response (timeout or not supported)"
    fi
  else
    check_warn "Cannot query DA1 (stty not available)"
  fi
else
  check_warn "Cannot query DA1 (not a TTY)"
fi

echo ""

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo -e "${BOLD}=== Summary ===${RESET}"
echo ""
echo -e "  ${GREEN}PASS${RESET}: $pass  ${YELLOW}WARN${RESET}: $warn  ${RED}FAIL${RESET}: $fail"
echo ""

if [[ $fail -eq 0 ]] && [[ "${FORCE_HYPERLINK:-}" == "1" ]]; then
  echo -e "  ${GREEN}${BOLD}VERDICT: Hyperlinks should work.${RESET}"
  echo "  FORCE_HYPERLINK=1 overrides all other checks in supports-hyperlinks."
  echo "  Claude Code and other Node.js CLI apps will emit OSC 8 hyperlinks."
elif [[ $fail -gt 0 ]]; then
  echo -e "  ${RED}${BOLD}VERDICT: Hyperlinks may not work.${RESET}"
  echo "  Check the FAIL items above. The most important fix is:"
  echo "    export FORCE_HYPERLINK=1"
  echo "  This must be set in the PTY environment (PtyEnvironment.buildEnvironment)."
fi

echo ""
echo "  For more details on how CLI apps detect hyperlinks, see:"
echo "    https://github.com/chalk/supports-hyperlinks"
echo "    https://gist.github.com/egmontkob/eb114294efbcd5adb1944c9f3cb5feda"
echo ""
