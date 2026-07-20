"""Sweep the vault through vault-lint.sh and report pass / FAIL / SKIP.

The hook exits 0 both for "valid" and for "not checked", so this replicates its
opt-in gate (vault-lint.sh:52-60) to tell those apart. Reading a `lifecycle:`
anywhere in the file is NOT the gate — it must be inside the frontmatter, or a
fenced code example in a doc reads as a passing node when the hook never looked.
"""
import json, os, re, subprocess

VAULT = r"C:\Users\Administrator\Documents\Obsidian\Claude Vault"
HOOK = r"C:\Users\Administrator\.claude\plugins\cache\claude-memory-brain\memory-brain\0.1.3\hooks\vault-lint.sh"


def opted_in(path):
    """True when the hook would actually lint this file. Mirrors vault-lint.sh:52-60."""
    with open(path, "rb") as fh:
        raw = fh.read(8192)
    if not (raw.startswith(b"---\n") or raw.startswith(b"---\r\n")):
        return False
    body_start = raw.find(b"\n") + 1
    closing = re.search(br"(?m)^---\r?$", raw[body_start:])
    header = raw[body_start:] if closing is None else raw[body_start:body_start + closing.start()]
    return re.search(br"(?m)^lifecycle:", header) is not None


bad = skipped = 0
for root, _, files in os.walk(VAULT):
    if ".obsidian" in root:
        continue
    for name in sorted(files):
        if not name.endswith(".md"):
            continue
        path = os.path.join(root, name)
        rel = os.path.relpath(path, VAULT)
        proc = subprocess.run(
            ["bash", HOOK],
            input=json.dumps({"tool_input": {"file_path": path}}),
            capture_output=True, text=True,
        )
        if proc.returncode == 2:
            bad += 1
            print("FAIL  " + rel)
            for line in proc.stderr.strip().splitlines():
                print("        " + line)
        elif opted_in(path):
            print("pass  " + rel)
        else:
            skipped += 1
            print("SKIP  " + rel + "   (not a node - hook never checked it)")

print("\n%d failing, %d never checked" % (bad, skipped))
