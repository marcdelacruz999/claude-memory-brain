---
description: Review and edit the memory-brain session snapshot
disable-model-invocation: true
---

Edit the configured memory-brain snapshot with the user.

1. Read `~/.claude/memory-brain.json`, then read and show the current `snapshot_path` contents. If either cannot be read, explain the problem and stop without writing.
2. Ask what the user wants changed unless their request already says.
3. Apply the requested edit while keeping all four sections: `## Active threads`, `## Standing decisions`, `## Pending questions`, and `## Canon pointers`.
4. Measure the proposed snapshot in UTF-8 bytes. Keep it at or below the 2,500-byte target. If it would exceed the target, consolidate with the user; never silently truncate content.
5. Write the agreed snapshot back and report its UTF-8 byte count.

The plugin never automatically invokes this command; `disable-model-invocation: true` makes that mechanical. It cannot prevent ordinary Claude Write/Edit operations from touching the file when a user asks. The injection hook's 10,000-byte hard cap is the backstop.
