#!/usr/bin/env bash

# Stop hook: reminds the user when the snapshot has gone stale. Never writes.
. "$(dirname "${BASH_SOURCE[0]}")/lib/python.sh"
mb_resolve_python || exit 0

"$MB_PYTHON" -c '
import json
import os
import stat
import sys
import time


def main():
    default_config = os.path.expanduser("~/.claude/memory-brain.json")
    default_root = os.path.expanduser("~/.claude/memory")
    config_path = default_config
    snapshot_root = default_root
    now = None
    args = sys.argv[1:]
    index = 0
    while index < len(args):
        if args[index] == "--config" and index + 1 < len(args):
            config_path = args[index + 1]
            index += 2
        elif args[index] == "--snapshot-root" and index + 1 < len(args):
            snapshot_root = args[index + 1]
            index += 2
        elif args[index] == "--now" and index + 1 < len(args):
            now = float(args[index + 1])
            index += 2
        else:
            return
    if now is None:
        now = time.time()

    try:
        with open(config_path, "r", encoding="utf-8") as config_file:
            config = json.load(config_file)
    except Exception:
        return
    if not isinstance(config, dict) or not isinstance(config.get("vault_path"), str) or not config["vault_path"]:
        return

    stale_days = config.get("stale_days", 7)
    if isinstance(stale_days, bool) or not isinstance(stale_days, (int, float)):
        return
    if stale_days <= 0:
        return

    snapshot_path = config.get("snapshot_path", os.path.join(snapshot_root, "snapshot.md"))
    if not isinstance(snapshot_path, str) or not snapshot_path:
        return

    root_real = os.path.realpath(snapshot_root)
    path_real = os.path.realpath(snapshot_path)
    try:
        if os.path.commonpath([root_real, path_real]) != root_real:
            return
    except (ValueError, OSError):
        return

    try:
        info = os.lstat(path_real)
    except OSError:
        return
    if not stat.S_ISREG(info.st_mode):
        return

    age_days = (now - info.st_mtime) / 86400.0
    if age_days < stale_days:
        return

    # `systemMessage` is NOT in the Stop hook output schema — emitting it here was
    # a silent no-op. Stop has no non-blocking message channel, and decision:"block"
    # would force a turn over a cosmetic reminder, so this goes to stderr instead.
    sys.stderr.write(
        "memory-brain: snapshot last updated "
        + str(int(age_days))
        + " days ago - refresh it with /memory-brain:snapshot\n"
    )


try:
    main()
except Exception:
    pass
' "$@" || true

exit 0
