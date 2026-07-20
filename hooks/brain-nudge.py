#!/usr/bin/env python3
"""Stop hook: run the memory pass when a session wrote files but never deposited.

Blocks the stop and feeds instructions back to the model, so the deposit happens
without the user typing /brain. Fires only when BOTH hold:
  - the session edited/wrote at least MIN_WRITES files outside the vault
  - neither the vault nor the snapshot was touched since the session started

Silence on a nothing-happened session is the whole point. A hook that fires every
time is one you train yourself to ignore.

`stop_hook_active` is the loop guard: once we have blocked and the model is doing
the deposit, the next Stop must be allowed through or the turn never ends.
"""
import json
import os
import sys

MIN_WRITES = 3
# MEMORY_BRAIN_CONFIG exists so the test suite can point at a fixture instead of
# the real config. Nothing in normal operation sets it.
CONFIG = os.environ.get("MEMORY_BRAIN_CONFIG") or os.path.expanduser(
    "~/.claude/memory-brain.json"
)

# Windows resolves sys.stdout to cp1252, which mangles any non-ASCII in `reason`
# into "?" on the way back to the model. The payload is JSON, so force UTF-8.
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")


def transcript_events(path):
    """Yield parsed JSONL entries; a corrupt line is skipped, not fatal."""
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    yield json.loads(line)
                except ValueError:
                    continue
    except OSError:
        return


def written_paths(transcript):
    """Every file_path this session passed to Write/Edit/NotebookEdit."""
    seen = []
    for event in transcript_events(transcript):
        message = event.get("message")
        if not isinstance(message, dict):
            continue
        content = message.get("content")
        if not isinstance(content, list):
            continue
        for block in content:
            if not isinstance(block, dict) or block.get("type") != "tool_use":
                continue
            if block.get("name") not in ("Write", "Edit", "NotebookEdit"):
                continue
            target = (block.get("input") or {}).get("file_path")
            if isinstance(target, str) and target:
                seen.append(target)
    return seen


def under(path, root):
    try:
        return os.path.commonpath([os.path.realpath(path), os.path.realpath(root)]) == os.path.realpath(root)
    except (ValueError, OSError):
        return False


def main():
    try:
        event = json.load(sys.stdin)
    except Exception:
        return
    # Already blocked once this turn: let the model finish the deposit and stop.
    if event.get("stop_hook_active"):
        return
    transcript = event.get("transcript_path")
    if not isinstance(transcript, str) or not transcript:
        return

    try:
        with open(CONFIG, "r", encoding="utf-8") as fh:
            config = json.load(fh)
    except Exception:
        return
    vault = config.get("vault_path")
    snapshot = config.get("snapshot_path")
    if not isinstance(vault, str) or not vault or not os.path.isdir(vault):
        return

    deposited = False
    work = 0
    for path in written_paths(transcript):
        if under(path, vault):
            deposited = True
        elif isinstance(snapshot, str) and snapshot and os.path.normcase(
            os.path.realpath(path)
        ) == os.path.normcase(os.path.realpath(snapshot)):
            deposited = True
        else:
            work += 1

    if deposited or work < MIN_WRITES:
        return

    # Paths are resolved from the plugin root rather than hardcoded under
    # ~/.claude, so the instruction stays correct wherever the plugin is installed.
    root = os.environ.get("CLAUDE_PLUGIN_ROOT") or os.path.dirname(
        os.path.dirname(os.path.realpath(__file__))
    )
    procedure = os.path.join(root, "commands", "brain.md")
    linter = os.path.join(root, "hooks", "vault-lintall.py")

    # decision:"block" feeds `reason` back to the model and forces another turn.
    # A hook cannot invoke a slash command, so the instruction has to be the payload.
    print(json.dumps({
        "decision": "block",
        "reason": (
            "memory-brain: this session changed %d files and deposited nothing to the "
            "vault. Before stopping, run the memory pass now by following "
            "%s exactly.\n\n"
            "Short form: measure the snapshot FIRST; decide what this session actually "
            "established (a claim that could be wrong, not narration of what was done); "
            "deposit it to the vault as a vault-node; add its claim to the vault's "
            "_index.md; then update the snapshot to point at it. Verify by running "
            "%s — SKIP means the lint never "
            "checked that file, which is not a pass.\n\n"
            "If nothing this session meets the bar, say so in one line and stop. "
            "An empty pass is a valid outcome; padding the vault with narration is not."
            % (work, procedure, linter)
        ),
    }, ensure_ascii=False))


try:
    main()
except Exception:
    pass
