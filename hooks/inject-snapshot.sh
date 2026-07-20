#!/usr/bin/env bash

# SessionStart is advisory: every path, parse, and content failure exits 0.
. "$(dirname "${BASH_SOURCE[0]}")/lib/python.sh"
mb_resolve_python || exit 0

"$MB_PYTHON" -c '
import errno
import json
import os
import stat
import sys


def emit(context=None, message=None):
    output = {}
    if context is not None:
        output["hookSpecificOutput"] = {
            "hookEventName": "SessionStart",
            "additionalContext": context,
        }
    if message is not None:
        output["systemMessage"] = message
    if output:
        print(json.dumps(output, ensure_ascii=False))


def main():
    default_config = os.path.expanduser("~/.claude/memory-brain.json")
    default_root = os.path.expanduser("~/.claude/memory")
    config_path = default_config
    snapshot_root = default_root
    args = sys.argv[1:]
    index = 0
    while index < len(args):
        if args[index] == "--config" and index + 1 < len(args):
            config_path = args[index + 1]
            index += 2
        elif args[index] == "--snapshot-root" and index + 1 < len(args):
            snapshot_root = args[index + 1]
            index += 2
        else:
            return

    try:
        with open(config_path, "r", encoding="utf-8") as config_file:
            config = json.load(config_file)
    except FileNotFoundError:
        return
    except Exception:
        emit(message="memory-brain: config invalid at " + config_path)
        return

    if not isinstance(config, dict) or not isinstance(config.get("vault_path"), str) or not config["vault_path"]:
        emit(message="memory-brain: config invalid at " + config_path)
        return
    snapshot_path = config.get("snapshot_path", os.path.join(snapshot_root, "snapshot.md"))
    if not isinstance(snapshot_path, str) or not snapshot_path:
        emit(message="memory-brain: config invalid at " + config_path)
        return

    root_real = os.path.realpath(snapshot_root)
    path_real = os.path.realpath(snapshot_path)
    try:
        contained = os.path.commonpath([root_real, path_real]) == root_real
    except (ValueError, OSError):
        contained = False
    if not contained:
        emit(message="memory-brain: snapshot path is outside the allowed memory directory, not injected")
        return

    # Windows Python defines neither O_NOFOLLOW nor O_NONBLOCK. Where O_NOFOLLOW
    # exists it refuses a symlink atomically; without it, an lstat check is the
    # available substitute, and the fstat below still rejects non-regular files.
    open_flags = os.O_RDONLY
    for flag_name in ("O_NOFOLLOW", "O_NONBLOCK", "O_BINARY"):
        open_flags |= getattr(os, flag_name, 0)
    if not hasattr(os, "O_NOFOLLOW"):
        try:
            if stat.S_ISLNK(os.lstat(snapshot_path).st_mode):
                emit(message="memory-brain: snapshot is not a regular non-symlink file, not injected")
                return
        except OSError:
            return

    fd = None
    try:
        fd = os.open(snapshot_path, open_flags)
        if not stat.S_ISREG(os.fstat(fd).st_mode):
            emit(message="memory-brain: snapshot is not a regular non-symlink file, not injected")
            return
        data = os.read(fd, 10001)
    except FileNotFoundError:
        return
    except OSError as error:
        if error.errno == errno.ENOENT:
            return
        emit(message="memory-brain: snapshot could not be safely opened, not injected")
        return
    finally:
        if fd is not None:
            try:
                os.close(fd)
            except OSError:
                pass

    byte_count = len(data)
    if byte_count > 10000:
        emit(message="memory-brain: snapshot exceeds 10,000-byte hard cap, not injected")
        return
    try:
        content = data.decode("utf-8")
    except UnicodeDecodeError:
        emit(message="memory-brain: snapshot must be valid UTF-8, not injected")
        return
    if byte_count > 2500:
        emit(
            context=content,
            message="memory-brain: snapshot over 2,500-byte target — consolidate with /memory-brain:snapshot",
        )
    else:
        emit(context=content)


try:
    main()
except Exception:
    emit(message="memory-brain: snapshot could not be processed, not injected")
' "$@" 2>/dev/null || true

exit 0
