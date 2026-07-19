---
name: vault-node
description: Apply the memory-brain node contract when writing files into the configured vault.
---

# Vault Node Contract

When writing a new Markdown node inside the vault configured in `~/.claude/memory-brain.json`, begin with this comment-free canonical template:

```yaml
---
id: verify-tool-output
type: lesson
summary: One line a router reads instead of the body.
lifecycle: scratch
created: 2026-07-19
---
```

Frontmatter uses a restricted grammar, not general YAML. Put one `key: value` pair on each nonblank line. Keys must match `[a-z][a-z0-9_]*`; values must be non-empty and single-line. Do not use indentation, multiline or folded scalars, or YAML comments. Everything after `: ` is value text, so inline `#` text is not treated as a comment.

Every node requires `id`, `type`, `summary`, `lifecycle`, and `created`. The `id` is kebab-case and unique within the vault. `type` is one of `lesson`, `project`, `output`, or `capture`. `lifecycle` is one of `scratch`, `research`, or `canon`. `created` is a real ISO calendar date. The author is responsible for cross-file ID uniqueness; per-edit lint does not scan the vault.

Treat `summary` as the load-bearing retrieval field: write one useful line a router can use instead of loading the body. New files always start with `lifecycle: scratch`.

Lifecycle promotion is advisory and human-gated by convention. Never raise a node's `lifecycle` and never write directly to `wiki/`; `/harvest` is the canon gate. This is a behavioral rule, not technical enforcement.

For each `_index.md`, keep these routing sections:

```markdown
## Load first
- [node-id](relative/path.md) — one-line reason to load it

## Query classes
- question or task class → [node-id](relative/path.md)
```

Keep indexes compact and route by summaries rather than copying node bodies. Leave legacy files without frontmatter alone unless the user asks to migrate them.
