# shellcheck shell=bash
# agentic-python.sh -- sourced by the hooks, install.sh, verify.sh and
# uninstall.sh. After it runs, `python3` starts a working Python 3 on every
# platform.
#
# macOS and Linux: no change and no fork. `python3` is the real interpreter.
#
# Windows (Git Bash, MSYS2, Cygwin): `python3` is often the Microsoft Store
# alias, which prints "Python was not found" and exits 9009, while the real
# interpreter is `python` or the `py` launcher. This file finds a real
# Python 3 one time, keeps its path in ${CLAUDE_CONFIG_DIR:-~/.claude}/.agentic-python,
# and defines a `python3` shell function that calls it. Later hook runs read
# the saved path and start no probe.
#
# Set AGENTIC_PYTHON to an interpreter path to skip the search.

agentic_is_windows() {
  case "${OSTYPE:-}" in
    msys* | cygwin* | win32*) return 0 ;;
  esac
  return 1
}

agentic_find_python() {
  local cache cand found
  cache="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.agentic-python"
  if [ -n "${AGENTIC_PYTHON:-}" ] && [ -f "$AGENTIC_PYTHON" ]; then
    return 0
  fi
  if [ -f "$cache" ]; then
    IFS= read -r found <"$cache" || true
    if [ -n "$found" ] && [ -f "$found" ]; then
      AGENTIC_PYTHON="$found"
      return 0
    fi
  fi
  for cand in python3 python "py -3"; do
    # Word splitting is intended: "py -3" is a command and an option.
    # shellcheck disable=SC2086
    found=$(command $cand -c 'import sys
if sys.version_info < (3, 8): sys.exit(1)
print(sys.executable.replace("\\", "/"))' 2>/dev/null) || continue
    found="${found%$'\r'}"
    [ -n "$found" ] && [ -f "$found" ] || continue
    AGENTIC_PYTHON="$found"
    if [ -d "${cache%/*}" ]; then
      printf '%s\n' "$found" >"$cache.$$" 2>/dev/null && mv -f "$cache.$$" "$cache" 2>/dev/null
      rm -f "$cache.$$" 2>/dev/null
    fi
    return 0
  done
  return 1
}

if agentic_is_windows && agentic_find_python; then
  # PYTHONUTF8=1: on Windows, Python reads and writes files in the ANSI code
  # page (cp1252) by default. The ledgers and transcripts are UTF-8.
  python3() { PYTHONUTF8=1 "$AGENTIC_PYTHON" "$@"; }
fi

# agentic_native_path PATH -- prints PATH in a form that a native Windows
# program (python.exe, git.exe) reads correctly when the path is inside data,
# for example a JSON file. MSYS converts command arguments by itself, but it
# does not convert text. On macOS and Linux, prints PATH unchanged.
agentic_native_path() {
  if agentic_is_windows && command -v cygpath >/dev/null 2>&1; then
    cygpath -m "$1"
  else
    printf '%s\n' "$1"
  fi
}
