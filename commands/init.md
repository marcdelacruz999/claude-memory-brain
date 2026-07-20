---
description: Configure memory-brain on this machine
disable-model-invocation: true
---

Initialize memory-brain for this machine.

1. Preflight the interpreter by running each of `python3`, `py`, then `python` until one *executes* successfully (on Windows `python3` is often a Microsoft Store stub that resolves on PATH but exits non-zero when run, so test by running it, not by checking existence). If none works, report that memory-brain requires Python 3 and stop without writing anything.
2. Ask the user for the absolute path to their SecondBrain vault. Offer an existing likely directory as the detected default when one is available. Confirm that the chosen path is an existing directory before continuing.
3. Create `~/.claude/memory/` if needed and write `~/.claude/memory-brain.json` as valid JSON with exactly `vault_path` set to the chosen absolute vault path, `snapshot_path` set to `~/.claude/memory/snapshot.md` expanded to its absolute path, and `stale_days` set to `7`. Tell the user `stale_days` controls the end-of-session reminder to refresh a drifting snapshot, and that `0` disables it.

   Write both paths in the interpreter's own native form — generate them with `os.path.realpath(os.path.expanduser(...))` in the resolved Python rather than pasting a shell path. This matters on Windows: under Git Bash a path like `/c/Users/you/...` is resolved by Windows Python to the nonexistent `C:\c\Users\you\...`, so the hooks' containment check would reject the snapshot and silently refuse to inject it.
4. Only if `~/.claude/memory/snapshot.md` is absent, create it with this skeleton:

   ```markdown
   ## Active threads

   ## Standing decisions

   ## Pending questions

   ## Canon pointers
   ```

   Never overwrite an existing snapshot.
5. Confirm each path written and whether the snapshot was created or preserved.
6. Tell the user: the snapshot is injected into Claude's context across all projects on this machine, so its contents are sent to Anthropic like other conversation content. Do not put secrets in it. The plugin itself makes no network calls; its shell tooling is local.
