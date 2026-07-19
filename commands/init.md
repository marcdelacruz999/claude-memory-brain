---
description: Configure memory-brain on this machine
disable-model-invocation: true
---

Initialize memory-brain for this machine.

1. Preflight `python3`. If it is unavailable, report that memory-brain requires python3 and stop without writing anything.
2. Ask the user for the absolute path to their SecondBrain vault. Offer an existing likely directory as the detected default when one is available. Confirm that the chosen path is an existing directory before continuing.
3. Create `~/.claude/memory/` if needed and write `~/.claude/memory-brain.json` as valid JSON with exactly `vault_path` set to the chosen absolute vault path and `snapshot_path` set to `~/.claude/memory/snapshot.md` expanded to its absolute path.
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
