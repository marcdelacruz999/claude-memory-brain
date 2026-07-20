#!/usr/bin/env bash

set -u

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
INJECT="$REPO_ROOT/hooks/inject-snapshot.sh"
LINT="$REPO_ROOT/hooks/vault-lint.sh"
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

passes=0
failures=0
OUT=
ERR=
STATUS=0

pass() {
  printf 'PASS %s\n' "$1"
  passes=$((passes + 1))
}

fail() {
  printf 'FAIL %s\n' "$1"
  failures=$((failures + 1))
}

assert_case() {
  local name=$1
  shift
  if "$@"; then
    pass "$name"
  else
    fail "$name"
  fi
}

make_config() {
  python3 -c 'import json,sys; json.dump({"vault_path":sys.argv[2],"snapshot_path":sys.argv[3]}, open(sys.argv[1], "w"))' "$1" "$2" "$3"
}

make_vault_config() {
  python3 -c 'import json,sys; json.dump({"vault_path":sys.argv[2]}, open(sys.argv[1], "w"))' "$1" "$2"
}

run_lint() {
  local input=$1
  local config=$2
  local err_file="$TEST_ROOT/lint.err"
  OUT=$(printf '%s' "$input" | bash "$LINT" --config "$config" 2>"$err_file")
  STATUS=$?
  ERR=$(<"$err_file")
}

run_inject() {
  local config=$1
  local root=$2
  local err_file="$TEST_ROOT/inject.err"
  OUT=$(bash "$INJECT" --config "$config" --snapshot-root "$root" 2>"$err_file")
  STATUS=$?
  ERR=$(<"$err_file")
}

silent_zero() {
  [[ $STATUS -eq 0 && -z $OUT && -z $ERR ]]
}

lint_finding() {
  local text=$1
  [[ $STATUS -eq 2 && -z $OUT && $ERR == *"$text"* && $ERR != *Traceback* ]]
}

json_context_equals() {
  local expected=$1
  python3 -c 'import json,sys; o=json.loads(sys.argv[1]); h=o["hookSpecificOutput"]; assert h["hookEventName"] == "SessionStart"; assert h["additionalContext"] == sys.argv[2]' "$OUT" "$expected" >/dev/null 2>&1
}

json_message_only() {
  local text=$1
  python3 -c 'import json,sys; o=json.loads(sys.argv[1]); assert sys.argv[2] in o["systemMessage"]; assert "hookSpecificOutput" not in o' "$OUT" "$text" >/dev/null 2>&1
}

json_context_and_message() {
  local expected=$1
  local text=$2
  python3 -c 'import json,sys; o=json.loads(sys.argv[1]); h=o["hookSpecificOutput"]; assert h["hookEventName"] == "SessionStart"; assert h["additionalContext"] == sys.argv[2]; assert sys.argv[3] in o["systemMessage"]' "$OUT" "$expected" "$text" >/dev/null 2>&1
}

VAULT="$TEST_ROOT/vault"
OUTSIDE="$TEST_ROOT/outside"
MEMORY="$TEST_ROOT/memory"
mkdir -p "$VAULT" "$OUTSIDE" "$MEMORY"
CONFIG="$TEST_ROOT/config.json"
SNAPSHOT="$MEMORY/snapshot.md"
make_config "$CONFIG" "$VAULT" "$SNAPSHOT"

valid_node='---
id: valid-node
type: lesson
summary: A valid summary.
lifecycle: scratch
created: 2026-07-19
---
Body
'

# Step 8.2: no-argument defaults ignore hostile plugin-specific environment variables.
NOARGS_HOME="$TEST_ROOT/noargs-home"
HOSTILE_CONFIG="$TEST_ROOT/hostile.json"
HOSTILE_SNAPSHOT="$MEMORY/hostile.md"
mkdir -p "$NOARGS_HOME"
printf '%s' 'hostile content' >"$HOSTILE_SNAPSHOT"
make_config "$HOSTILE_CONFIG" "$VAULT" "$HOSTILE_SNAPSHOT"
OUT=$(cd "$NOARGS_HOME" && HOME="$NOARGS_HOME" MEMORY_BRAIN_CONFIG="$HOSTILE_CONFIG" MEMORY_BRAIN_SNAPSHOT_ROOT="$MEMORY" bash "$INJECT" 2>"$TEST_ROOT/noargs-inject.err")
STATUS=$?
ERR=$(<"$TEST_ROOT/noargs-inject.err")
assert_case "defaults/inject ignores hostile env overrides" silent_zero

printf '%s' "$valid_node" >"$VAULT/noargs.md"
NOARGS_EVENT=$(python3 -c 'import json,sys; print(json.dumps({"tool_input":{"file_path":sys.argv[1]}}))' "$VAULT/noargs.md")
OUT=$(cd "$NOARGS_HOME" && printf '%s' "$NOARGS_EVENT" | HOME="$NOARGS_HOME" MEMORY_BRAIN_CONFIG="$HOSTILE_CONFIG" bash "$LINT" 2>"$TEST_ROOT/noargs-lint.err")
STATUS=$?
ERR=$(<"$TEST_ROOT/noargs-lint.err")
assert_case "defaults/lint ignores hostile env overrides" silent_zero

# Step 8.3: vault-lint matrix.
EVENT=$(python3 -c 'import json,sys; print(json.dumps({"tool_input":{"file_path":sys.argv[1]}}))' "$VAULT/node.md")
run_lint "$EVENT" "$TEST_ROOT/absent.json"
assert_case "lint/no config" silent_zero

printf '%s' '{broken' >"$TEST_ROOT/invalid-config.json"
run_lint "$EVENT" "$TEST_ROOT/invalid-config.json"
assert_case "lint/invalid JSON config is silent" silent_zero

printf '%s' "$valid_node" >"$VAULT/node.md"
run_lint "$EVENT" "$CONFIG"
assert_case "lint/valid node" silent_zero

printf '%s' '---
id: missing-summary
type: lesson
lifecycle: scratch
created: 2026-07-19
---
' >"$VAULT/node.md"
run_lint "$EVENT" "$CONFIG"
assert_case "lint/missing summary" lint_finding "missing required key: summary"

printf '%s' "${valid_node/lifecycle: scratch/lifecycle: candidate}" >"$VAULT/node.md"
run_lint "$EVENT" "$CONFIG"
assert_case "lint/invalid lifecycle" lint_finding "invalid lifecycle: candidate"

printf '%s' "${valid_node/type: lesson/type: Lesson}" >"$VAULT/node.md"
run_lint "$EVENT" "$CONFIG"
assert_case "lint/invalid type case" lint_finding "invalid type: Lesson"

printf '%s' '---
id: duplicate-summary
type: lesson
summary: A valid summary.
summary: Duplicate.
lifecycle: scratch
created: 2026-07-19
---
' >"$VAULT/node.md"
run_lint "$EVENT" "$CONFIG"
assert_case "lint/duplicate key" lint_finding "duplicate key: summary"

printf '%s' '---
id: no-close
type: lesson
summary: Missing close.
lifecycle: scratch
created: 2026-07-19
' >"$VAULT/node.md"
run_lint "$EVENT" "$CONFIG"
assert_case "lint/missing closing delimiter" lint_finding "missing closing --- delimiter"

printf '%s' '---
title: Legacy frontmatter
---
Body
' >"$VAULT/node.md"
run_lint "$EVENT" "$CONFIG"
assert_case "lint/legacy file without opt-in key" silent_zero

printf '%s' "$valid_node" >"$OUTSIDE/outside.md"
OUTSIDE_EVENT=$(python3 -c 'import json,sys; print(json.dumps({"tool_input":{"file_path":sys.argv[1]}}))' "$OUTSIDE/outside.md")
run_lint "$OUTSIDE_EVENT" "$CONFIG"
assert_case "lint/file outside vault" silent_zero

PREFIX="$TEST_ROOT/vault-evil"
mkdir -p "$PREFIX"
printf '%s' "$valid_node" >"$PREFIX/f.md"
PREFIX_EVENT=$(python3 -c 'import json,sys; print(json.dumps({"tool_input":{"file_path":sys.argv[1]}}))' "$PREFIX/f.md")
run_lint "$PREFIX_EVENT" "$CONFIG"
assert_case "lint/vault prefix collision" silent_zero

SPACE_VAULT="$TEST_ROOT/vault with spaces"
mkdir -p "$SPACE_VAULT"
SPACE_CONFIG="$TEST_ROOT/space-config.json"
make_vault_config "$SPACE_CONFIG" "$SPACE_VAULT"
printf '%s' "$valid_node" >"$SPACE_VAULT/node with spaces.md"
SPACE_EVENT=$(python3 -c 'import json,sys; print(json.dumps({"tool_input":{"file_path":sys.argv[1]}}))' "$SPACE_VAULT/node with spaces.md")
run_lint "$SPACE_EVENT" "$SPACE_CONFIG"
assert_case "lint/path with spaces" silent_zero

ln -s "$OUTSIDE/outside.md" "$VAULT/symlink.md"
SYMLINK_EVENT=$(python3 -c 'import json,sys; print(json.dumps({"tool_input":{"file_path":sys.argv[1]}}))' "$VAULT/symlink.md")
run_lint "$SYMLINK_EVENT" "$CONFIG"
assert_case "lint/symlink out of vault" silent_zero

run_lint '{not json' "$CONFIG"
assert_case "lint/malformed stdin JSON" silent_zero

printf '%s' "${valid_node/created: 2026-07-19/created: 2026-99-99}" >"$VAULT/node.md"
run_lint "$EVENT" "$CONFIG"
assert_case "lint/bad calendar date" lint_finding "created must be a real ISO calendar date"

printf '%s' "${valid_node/id: valid-node/id: Bad_ID}" >"$VAULT/node.md"
run_lint "$EVENT" "$CONFIG"
assert_case "lint/bad id" lint_finding "id must be kebab-case"

python3 -c 'import sys; open(sys.argv[1], "wb").write(b"---\nid: huge\ntype: lesson\nsummary: Huge.\nlifecycle: scratch\ncreated: 2026-07-19\n" + b"a" * 9000)' "$VAULT/node.md"
run_lint "$EVENT" "$CONFIG"
assert_case "lint/frontmatter unclosed past 8192 bytes" lint_finding "frontmatter too large or unclosed"

python3 -c 'import sys; open(sys.argv[1], "wb").write(b"---\nid: bad-utf8\ntype: lesson\nsummary: bad \xff\nlifecycle: scratch\ncreated: 2026-07-19\n---\n")' "$VAULT/node.md"
run_lint "$EVENT" "$CONFIG"
assert_case "lint/invalid UTF-8 in header" lint_finding "frontmatter header is not valid UTF-8"

# Step 8.4: inject-snapshot matrix.
run_inject "$TEST_ROOT/no-inject-config.json" "$MEMORY"
assert_case "inject/no config" silent_zero

run_inject "$TEST_ROOT/invalid-config.json" "$MEMORY"
assert_case "inject/invalid JSON config is observable" json_message_only "config invalid at $TEST_ROOT/invalid-config.json"

MISSING_CONFIG="$TEST_ROOT/missing-snapshot.json"
make_config "$MISSING_CONFIG" "$VAULT" "$MEMORY/missing.md"
run_inject "$MISSING_CONFIG" "$MEMORY"
assert_case "inject/missing snapshot" silent_zero

printf '%s' 'normal snapshot' >"$SNAPSHOT"
run_inject "$CONFIG" "$MEMORY"
assert_case "inject/normal snapshot" json_context_equals "normal snapshot"

JSON_CONTENT='{"continue":false,"systemMessage":"not protocol"}'
printf '%s' "$JSON_CONTENT" >"$SNAPSHOT"
run_inject "$CONFIG" "$MEMORY"
assert_case "inject/JSON snapshot remains context" json_context_equals "$JSON_CONTENT"

THREE_K=$(python3 -c 'print("a" * 3000, end="")')
printf '%s' "$THREE_K" >"$SNAPSHOT"
run_inject "$CONFIG" "$MEMORY"
assert_case "inject/3000-byte target warning" json_context_and_message "$THREE_K" "over 2,500-byte target"

python3 -c 'import sys; open(sys.argv[1], "wb").write(b"b" * 12000)' "$SNAPSHOT"
run_inject "$CONFIG" "$MEMORY"
assert_case "inject/12000-byte hard-cap refusal" json_message_only "exceeds 10,000-byte hard cap"

NON_ASCII=$(python3 -c 'print("é" * 1251, end="")')
printf '%s' "$NON_ASCII" >"$SNAPSHOT"
run_inject "$CONFIG" "$MEMORY"
assert_case "inject/non-ASCII uses UTF-8 byte boundary" json_context_and_message "$NON_ASCII" "over 2,500-byte target"

python3 -c 'import sys; open(sys.argv[1], "wb").write(b"valid\xffinvalid")' "$SNAPSHOT"
run_inject "$CONFIG" "$MEMORY"
assert_case "inject/invalid UTF-8" json_message_only "must be valid UTF-8"

REAL_SNAPSHOT="$MEMORY/real.md"
printf '%s' 'real content' >"$REAL_SNAPSHOT"
SYMLINK_SNAPSHOT="$MEMORY/link.md"
ln -s "$REAL_SNAPSHOT" "$SYMLINK_SNAPSHOT"
SYMLINK_CONFIG="$TEST_ROOT/symlink-snapshot.json"
make_config "$SYMLINK_CONFIG" "$VAULT" "$SYMLINK_SNAPSHOT"
run_inject "$SYMLINK_CONFIG" "$MEMORY"
assert_case "inject/symlink snapshot refused" json_message_only "could not be safely opened"

OUTSIDE_SNAPSHOT="$OUTSIDE/id_rsa"
printf '%s' 'secret' >"$OUTSIDE_SNAPSHOT"
OUTSIDE_CONFIG="$TEST_ROOT/outside-snapshot.json"
make_config "$OUTSIDE_CONFIG" "$VAULT" "$OUTSIDE_SNAPSHOT"
run_inject "$OUTSIDE_CONFIG" "$MEMORY"
assert_case "inject/snapshot outside allowed root" json_message_only "outside the allowed memory directory"

SPACE_MEMORY="$TEST_ROOT/memory with spaces"
mkdir -p "$SPACE_MEMORY"
SPACE_SNAPSHOT="$SPACE_MEMORY/snapshot with spaces.md"
printf '%s' 'space path content' >"$SPACE_SNAPSHOT"
SPACE_INJECT_CONFIG="$TEST_ROOT/space-inject-config.json"
make_config "$SPACE_INJECT_CONFIG" "$VAULT" "$SPACE_SNAPSHOT"
run_inject "$SPACE_INJECT_CONFIG" "$SPACE_MEMORY"
assert_case "inject/snapshot path with spaces" json_context_equals "space path content"

NUDGE="$REPO_ROOT/hooks/snapshot-nudge.sh"
NUDGE_MEMORY="$TEST_ROOT/nudge-memory"
mkdir -p "$NUDGE_MEMORY"
NUDGE_SNAPSHOT="$NUDGE_MEMORY/snapshot.md"
printf '%s' 'nudge content' >"$NUDGE_SNAPSHOT"
NUDGE_CONFIG="$TEST_ROOT/nudge-config.json"
make_config "$NUDGE_CONFIG" "$VAULT" "$NUDGE_SNAPSHOT"

run_nudge() {
  local config=$1
  local root=$2
  local now=$3
  local err_file="$TEST_ROOT/nudge.err"
  OUT=$(bash "$NUDGE" --config "$config" --snapshot-root "$root" --now "$now" 2>"$err_file")
  STATUS=$?
  ERR=$(<"$err_file")
}

nudge_silent() {
  [[ $STATUS -eq 0 && -z $OUT && -z $ERR ]]
}

nudge_message() {
  local needle=$1
  [[ $STATUS -eq 0 && -z $ERR ]] || return 1
  python3 -c '
import json, sys
payload = json.loads(sys.stdin.read())
assert set(payload) == {"systemMessage"}, payload
assert sys.argv[1] in payload["systemMessage"], payload
' "$needle" <<<"$OUT"
}

SNAP_MTIME=$(python3 -c 'import os,sys; print(os.stat(sys.argv[1]).st_mtime)' "$NUDGE_SNAPSHOT")

run_nudge "$NUDGE_CONFIG" "$NUDGE_MEMORY" "$SNAP_MTIME"
assert_case "nudge/fresh snapshot is silent" nudge_silent

run_nudge "$NUDGE_CONFIG" "$NUDGE_MEMORY" "$(python3 -c 'import sys; print(float(sys.argv[1]) + 6.9 * 86400)' "$SNAP_MTIME")"
assert_case "nudge/just under threshold is silent" nudge_silent

run_nudge "$NUDGE_CONFIG" "$NUDGE_MEMORY" "$(python3 -c 'import sys; print(float(sys.argv[1]) + 9 * 86400)' "$SNAP_MTIME")"
assert_case "nudge/stale snapshot warns" nudge_message "9 days ago"

run_nudge "$TEST_ROOT/nudge-absent.json" "$NUDGE_MEMORY" "$SNAP_MTIME"
assert_case "nudge/no config is silent" nudge_silent

NUDGE_INVALID_CONFIG="$TEST_ROOT/nudge-invalid.json"
printf '%s' 'not json' >"$NUDGE_INVALID_CONFIG"
run_nudge "$NUDGE_INVALID_CONFIG" "$NUDGE_MEMORY" "$SNAP_MTIME"
assert_case "nudge/invalid config is silent" nudge_silent

NUDGE_MISSING_CONFIG="$TEST_ROOT/nudge-missing.json"
make_config "$NUDGE_MISSING_CONFIG" "$VAULT" "$NUDGE_MEMORY/absent.md"
run_nudge "$NUDGE_MISSING_CONFIG" "$NUDGE_MEMORY" "$SNAP_MTIME"
assert_case "nudge/missing snapshot is silent" nudge_silent

run_nudge "$OUTSIDE_CONFIG" "$NUDGE_MEMORY" "$(python3 -c 'import sys; print(float(sys.argv[1]) + 400 * 86400)' "$SNAP_MTIME")"
assert_case "nudge/snapshot outside allowed root is silent" nudge_silent

NUDGE_OFF_CONFIG="$TEST_ROOT/nudge-off.json"
python3 -c 'import json,sys; json.dump({"vault_path":sys.argv[2],"snapshot_path":sys.argv[3],"stale_days":0}, open(sys.argv[1], "w"))' "$NUDGE_OFF_CONFIG" "$VAULT" "$NUDGE_SNAPSHOT"
run_nudge "$NUDGE_OFF_CONFIG" "$NUDGE_MEMORY" "$(python3 -c 'import sys; print(float(sys.argv[1]) + 400 * 86400)' "$SNAP_MTIME")"
assert_case "nudge/stale_days 0 disables nudge" nudge_silent

NUDGE_CUSTOM_CONFIG="$TEST_ROOT/nudge-custom.json"
python3 -c 'import json,sys; json.dump({"vault_path":sys.argv[2],"snapshot_path":sys.argv[3],"stale_days":2}, open(sys.argv[1], "w"))' "$NUDGE_CUSTOM_CONFIG" "$VAULT" "$NUDGE_SNAPSHOT"
run_nudge "$NUDGE_CUSTOM_CONFIG" "$NUDGE_MEMORY" "$(python3 -c 'import sys; print(float(sys.argv[1]) + 3 * 86400)' "$SNAP_MTIME")"
assert_case "nudge/custom stale_days honored" nudge_message "3 days ago"

NUDGE_BAD_STALE_CONFIG="$TEST_ROOT/nudge-bad-stale.json"
python3 -c 'import json,sys; json.dump({"vault_path":sys.argv[2],"snapshot_path":sys.argv[3],"stale_days":"soon"}, open(sys.argv[1], "w"))' "$NUDGE_BAD_STALE_CONFIG" "$VAULT" "$NUDGE_SNAPSHOT"
run_nudge "$NUDGE_BAD_STALE_CONFIG" "$NUDGE_MEMORY" "$(python3 -c 'import sys; print(float(sys.argv[1]) + 400 * 86400)' "$SNAP_MTIME")"
assert_case "nudge/non-numeric stale_days is silent" nudge_silent

OUT=$(bash "$NUDGE" --unknown-flag 2>"$TEST_ROOT/nudge.err"); STATUS=$?; ERR=$(<"$TEST_ROOT/nudge.err")
assert_case "nudge/unknown flag is silent" nudge_silent

printf 'RESULT %d passed, %d failed\n' "$passes" "$failures"
if [[ $failures -ne 0 ]]; then
  exit 1
fi
