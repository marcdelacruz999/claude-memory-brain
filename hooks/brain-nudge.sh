#!/usr/bin/env bash

# Stop hook: runs the memory pass when a session wrote files but never deposited.
# Thin wrapper so the Python lands on a resolved interpreter (`python3` on macOS,
# usually `py` on Windows — see lib/python.sh for why `command -v` is not enough).
. "$(dirname "${BASH_SOURCE[0]}")/lib/python.sh"
mb_resolve_python || exit 0

"$MB_PYTHON" "$(dirname "${BASH_SOURCE[0]}")/brain-nudge.py" "$@" 2>/dev/null || true

exit 0
