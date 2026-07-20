#!/usr/bin/env bash

# Resolves an interpreter into MB_PYTHON. On Windows, `python3` on PATH is
# usually the Microsoft Store stub: it exists, resolves, and errors on use, so
# candidates are probed by execution rather than by `command -v`. `py` precedes
# bare `python` because it targets the system install instead of whatever
# virtualenv happens to lead PATH.
mb_resolve_python() {
    local candidate
    for candidate in python3 py python; do
        if command -v "$candidate" >/dev/null 2>&1 &&
            "$candidate" -c 'import sys' >/dev/null 2>&1; then
            MB_PYTHON="$candidate"
            return 0
        fi
    done
    return 1
}
