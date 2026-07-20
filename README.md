# memory-brain

`memory-brain` is a Claude Code plugin that carries a small, hand-maintained context snapshot across sessions and gives immediate advisory feedback on opted-in SecondBrain vault nodes. It ships tooling only; your vault and snapshot remain outside this repository.

## Install

```text
/plugin marketplace add marcdelacruz999/claude-memory-brain
/plugin install memory-brain@claude-memory-brain
restart Claude Code (or reload plugins)
/memory-brain:init
```

Supported platforms are macOS, Linux, and Windows via Git Bash. Bash and Python 3 are required; the init command preflights the interpreter.

On Windows, run Claude Code so its hooks execute under **Git Bash** (`C:\Program Files\Git\bin\bash.exe`). The `bash.exe` in `System32` is the WSL launcher: it runs, but inside Linux, where `$HOME` is the WSL home rather than `C:\Users\<you>`, so the hooks would read a different `.claude` directory than Claude Code writes. The hooks pick an interpreter by executing `python3`, `py`, then `python` in order and taking the first that runs, which skips the Microsoft Store `python3` stub.

## Laptop 2 quickstart

First clone your private SecondBrain vault separately, then run the same four steps:

```text
/plugin marketplace add marcdelacruz999/claude-memory-brain
/plugin install memory-brain@claude-memory-brain
restart Claude Code (or reload plugins)
/memory-brain:init
```

When init asks, point it at the cloned vault directory. Vault synchronization is deliberately separate from this public tooling repo.

## What it does

The SessionStart hook reads the configured snapshot and injects it as additional Claude context. SessionStart fires on startup, resume, `/clear`, and compaction, so the snapshot is injected at each of those points. Edits made mid-session appear at the next firing; there is no frozen-for-the-session guarantee. A 4,000-byte UTF-8 target keeps it compact, and snapshots over the 10,000-byte hard cap are refused. The target is a discipline rather than a limit: 4,000 bytes is roughly 1,000 tokens, so going over means something in the snapshot belongs in the vault, not that bytes need shaving.

A second `Stop` hook closes the deposit loop. When a session edited at least three files outside the vault and wrote nothing to the vault or snapshot, it blocks the stop once and hands Claude the `/brain` procedure, so the memory pass happens without anyone remembering to ask. Sessions that deposited something, or that changed less than three files, produce silence — a hook that fires every time is one you train yourself to ignore. `stop_hook_active` guards the loop, so it blocks at most once per turn.

The PostToolUse hook runs after Claude's Write or Edit tool touches a Markdown file under the configured vault. Files opt in when their frontmatter contains a `lifecycle:` line. The hook validates the memory-brain restricted frontmatter contract and returns warn-only model feedback; it never undoes or rewrites a change.

Configuration lives at `~/.claude/memory-brain.json`:

```json
{
  "vault_path": "/absolute/path/to/SecondBrain",
  "snapshot_path": "/absolute/path/to/.claude/memory/snapshot.md",
  "stale_days": 7
}
```

`vault_path` is required. `snapshot_path` is optional and defaults to `~/.claude/memory/snapshot.md`; after canonicalization it must remain under `~/.claude/memory/`. `stale_days` is optional and defaults to `7`; set it to `0` to silence the staleness reminder entirely.

## Staleness reminder

The snapshot is never written automatically — that is the point. The cost of a hand-curated file is that it drifts out of date silently. A `Stop` hook covers that gap: when a session ends and the snapshot has not been modified in `stale_days` days, it prints one reminder to refresh it with `/memory-brain:snapshot`.

It only reads `mtime`. It never writes the snapshot, never proposes content, and never blocks the session — it prints to stderr, which surfaces the reminder without forcing a turn. (The deposit hook is the one that blocks, and only under the conditions above.) Fresh snapshot, missing snapshot, missing config, or `stale_days: 0` all produce silence.

## Commands

- `/memory-brain:init` — write `~/.claude/memory-brain.json` and preflight the interpreter.
- `/memory-brain:snapshot` — snapshot-only edit, when nothing needs depositing.
- `/brain` — the full memory pass: deposit durable detail to the vault, index it, then point the snapshot at it. This is what the deposit hook instructs, and what to run by hand at the end of a session that shipped something.

`/brain` reads the vault's own `AGENTS.md` for folder placement rather than assuming a layout, so it works against both the Obsidian-style (`00 Inbox`, `10 Projects`, …) and pipeline-style (`inbox/`, `projects/`, `output/`, `wiki/`) vaults. It never writes to `wiki/` directly.

## Honest scope

Vault lint is best-effort advisory, not governance. PostToolUse catches only Claude's Write and Edit tools. It does not catch Bash redirects, `mv`, external editors, or edits made while Claude is not running. The skill's lifecycle-promotion and `wiki/` rules are behavioral guidance, not technical enforcement.

Opt-in also has deliberate edges: an intended node whose author forgot `lifecycle:` escapes lint entirely. Foreign frontmatter that happens to contain `lifecycle:` triggers lint and may prompt Claude to fix frontmatter that is not memory-brain's. Cross-file `id` uniqueness remains the author's responsibility because per-edit lint does not scan the vault.

## Privacy

The snapshot's whole purpose is injection into Claude's context. Its contents are sent to Anthropic like any other conversation content, across all projects on this machine. Do not put secrets in it. The plugin itself makes no network calls of any kind; everything it runs is local shell and python3.

## Troubleshooting

- Silent hooks usually mean there is no config. Run `/memory-brain:init`.
- `memory-brain: config invalid` means `~/.claude/memory-brain.json` is malformed or missing required data; fix or rerun init.
- A refused snapshot is commonly over the 10,000-byte hard cap or resolves outside `~/.claude/memory/`. It must also be a regular, non-symlink UTF-8 file.
- A vault warning is advisory. Fix the reported restricted-frontmatter issue; the Write/Edit operation has already happened.

## What this plugin deliberately does NOT do

- Automatically write memories or snapshots **itself** — the deposit hook instructs Claude to run the memory pass; every write is Claude's, reviewable in the transcript, and the hook never edits the vault or snapshot directly
- Couple to claude-mem
- Build or maintain a graph (graphify)
- Keep a session ledger
- Enforce or scan the whole vault
- Write anything from its Stop hooks — the staleness reminder reads `mtime` and prints; the deposit hook emits an instruction. Neither edits the snapshot or the vault
- Synchronize the private vault
- Edit `~/.claude/settings.json`
