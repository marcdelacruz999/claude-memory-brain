---
description: End-of-session memory pass — deposit durable detail to the vault, then update the injected snapshot to point at it.
---

# /brain — one-shot memory pass

Combines the vault deposit and the snapshot edit into a single routing decision, so the
two stay consistent. Run this at the end of any session that shipped something, resolved
a non-obvious failure, or produced a decision worth keeping.

`/memory-brain:snapshot` still exists for a snapshot-only tweak. Use `/brain` when the
session actually produced something.

## The model

Two stores, one rule for choosing between them.

- **Hot cache** — `snapshot_path` from `~/.claude/memory-brain.json`. Injected into every
  session, **target 4,000 bytes**. Zero-sum: every line added evicts another. Holds what a
  session needs *before it knows it needs it*.
- **Cold store** — `vault_path` from the same config. Unbounded, read on demand. Holds the
  detail behind those lines. Its `_index.md` is the router: one claim per note.

**On the 4,000-byte target.** The injection hook's hard cap is 10,000 (`inject-snapshot.sh`);
4,000 is a discipline, not a limit. 4,000 bytes is roughly 1,000 tokens — negligible against
the context window, so the target exists to force the routing decision, not to save tokens.
Shaving words to win 20 bytes is wasted work: if the file is over, something in it belongs in
the vault. Evict by rule, never by rewording. Past 4,000 with nothing evictable, say so and
keep the content — silent truncation is the one forbidden move.

**Routing rule:** if a future session would go wrong *without* knowing it, the trigger goes
in the snapshot. Everything else goes in the vault. The snapshot's job is to make the vault
findable, not to duplicate it.

A good snapshot line is a **trigger plus a pointer**, not a summary:

> `WhisperFlow broken = check dependencies before code. Symptoms, repro and the two Ollama
> login starters live in vault "20 Knowledge/WhisperFlow troubleshooting.md". Read it first.`

The trigger ("broken = check dependencies") fires recognition. The pointer carries the rest.

## Procedure

### 1. Read config and current state

Read `~/.claude/memory-brain.json`. Read the current `snapshot_path` contents and show
them. If either cannot be read, explain and **stop without writing** — never scaffold a
directory to make a config path look valid.

Read the vault's `_index.md`. It lists every content note by claim — a deposit that
duplicates an existing claim should extend that note instead of adding a second one.

**Measure the current snapshot now**, before writing anything, and note the headroom. That
number decides how much can go in the snapshot in step 4; discovering it afterwards is what
turns this into a shave-and-remeasure loop.

### 2. Decide what this session produced

List candidates before writing anything. For each, name the store and why. Only these
qualify:

- A failure whose cause was not where the symptom pointed
- A decision a future session could silently reverse
- A verified fact that cost real work to establish
- A gotcha that will recur

**Not** a candidate: narration of what was done, anything already in the repo's own docs,
or anything still unverified. Say "nothing worth depositing" when that is true — an empty
pass is a valid outcome and better than padding.

### 3. Deposit to the vault first

Vault before snapshot, always: the snapshot line has to point at a note that exists.

Follow the `vault-node` skill's contract for new notes. Required frontmatter, restricted
grammar — one `key: value` per line, no indentation, no multiline values, no YAML comments:

```
---
id: kebab-case-unique-in-vault
type: lesson
summary: One line a router reads instead of the body.
lifecycle: scratch
created: 2026-07-19
---
```

`type` is one of `lesson`, `project`, `output`, `capture`. `lifecycle` is one of `scratch`,
`research`, `canon` — **new notes always start at `scratch`**. Never raise a node's
lifecycle; promotion is human-gated. `summary` is the load-bearing retrieval field: write
the line a router would read *instead of* the body.

The `vault-lint.sh` PostToolUse hook enforces this, but only on files that already carry a
`lifecycle:` key. A note without it is silently unlinted, not valid — do not treat the
absence of an error as a pass.

**Placement depends on the vault's layout — read its `AGENTS.md` before choosing a folder.**
Vaults differ per machine and that file is authoritative. Two layouts in use:

- Obsidian-style: `00 Inbox` unclassified, `10 Projects` active work (status and pointers
  into the repo, never copies of repo docs), `20 Knowledge` reusable lessons,
  `30 Decisions` durable choices, `90 Archive` retired.
- Pipeline-style: `inbox/` raw captures, `projects/` one status-and-pointers file per
  project, `output/` shipped things, `wiki/` — **never write here directly**; wiki articles
  are created only by `/harvest`, run from a session inside the vault, after work ships.

Guessing a folder that does not exist scatters the vault. If `AGENTS.md` is missing, list
the vault root and match the existing layout rather than inventing one.

Write the reasoning, not just the conclusion — a decision note that omits *what it
reverses* lets a future session reverse it back. Record what was verified and how, and
label anything unverified as unverified.

**Add a line to `_index.md` for every new note, in the same pass.** Claim first, path
second. A claim is a sentence that could be wrong ("check dependencies before code"), not a
topic label ("notes about WhisperFlow") — a label does not route. Also link the note from
its folder index so it is reachable by browsing.

Then verify the deposit actually linted, rather than assuming. The linter ships with this
plugin — run it with whichever interpreter this machine has (`python3` on macOS, often `py`
on Windows):

```
python3 "$CLAUDE_PLUGIN_ROOT/hooks/vault-lintall.py"
```

`pass` means checked and valid. `SKIP` means the hook never looked — if a note you just
wrote shows SKIP, its frontmatter is wrong, not fine.

### 4. Update the snapshot — one write, not a shave loop

Keep all four sections, even if empty: `## Active threads`, `## Standing decisions`,
`## Pending questions`, `## Canon pointers`.

- Add trigger-plus-pointer lines for what was deposited.
- Drop threads this session resolved.
- Where a snapshot block now duplicates a vault note, collapse it to a pointer.

If step 1's measurement showed less headroom than the new lines need, **decide what to evict
before writing.** Evict in this order, and stop as soon as it fits:

1. A resolved thread or answered question — dead weight.
2. A block whose detail now lives in a vault note — collapse to a pointer.
3. A settled machine fact that is reference, not trigger — move it to a `20 Knowledge` note
   and leave one pointer.

Never evict by rewording. If three passes of the list do not fit it, the snapshot is
carrying something that belongs in the vault — name it and say so instead of shaving.

### 5. Measure once, write, report

**Measure the bytes — never estimate.** Estimates have been wrong by 300-500 bytes here.

```bash
wc -c < "$SNAPSHOT"
```

PowerShell equivalent, if that is the shell in hand — note `Get-Content -Raw` drops the
trailing newline, so this reads a few bytes low against `wc -c`:

```powershell
[System.Text.Encoding]::UTF8.GetByteCount((Get-Content $f -Raw))
```

Over 4,000 after the eviction list is exhausted: keep the content, write it, and report the
overage plainly. Never silently truncate; the 10,000-byte hook cap is the real backstop.

Report: byte count, headroom, what was deposited where, and any lint SKIP on a new note.

## Failure modes worth naming

- **Estimating bytes instead of measuring.** Estimates have been wrong by 300-500 bytes
  here. Measure — and measure in step 1, not after writing.
- **Shaving words to hit the target.** Cutting "symptoms," to win 8 bytes is theatre. Over
  budget means something belongs in the vault; evict by rule.
- **Depositing without indexing.** A note missing from `_index.md` is findable only by a
  grep nobody runs.
- **Depositing narration.** "Did X, then Y" is worthless next session. Deposit the claim
  and the evidence.
- **Snapshot lines that summarize a vault note** instead of pointing at it. Costs bytes
  twice and drifts out of sync.
- **Writing the conclusion without what it overrides.** The reversal is the load-bearing
  part.
