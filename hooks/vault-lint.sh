#!/usr/bin/env bash

# PostToolUse lint is advisory: only opted-in vault Markdown can produce exit 2.
python3 -c '
import datetime
import json
import os
import re
import sys


def main():
    config_path = os.path.expanduser("~/.claude/memory-brain.json")
    args = sys.argv[1:]
    if args:
        if len(args) != 2 or args[0] != "--config":
            return 0
        config_path = args[1]

    try:
        with open(config_path, "r", encoding="utf-8") as config_file:
            config = json.load(config_file)
    except Exception:
        return 0
    if not isinstance(config, dict) or not isinstance(config.get("vault_path"), str) or not config["vault_path"]:
        return 0

    try:
        event = json.load(sys.stdin)
        file_path = event["tool_input"]["file_path"]
    except Exception:
        return 0
    if not isinstance(file_path, str) or not file_path.endswith(".md"):
        return 0

    vault_real = os.path.realpath(config["vault_path"])
    file_real = os.path.realpath(file_path)
    try:
        if os.path.commonpath([vault_real, file_real]) != vault_real:
            return 0
    except (ValueError, OSError):
        return 0

    try:
        with open(file_real, "rb") as node_file:
            raw = node_file.read(8192)
    except Exception:
        return 0
    if not (raw.startswith(b"---\n") or raw.startswith(b"---\r\n")):
        return 0

    first_break = raw.find(b"\n")
    body_start = first_break + 1
    closing = re.search(br"(?m)^---\r?$", raw[body_start:])
    header_probe = raw[body_start:] if closing is None else raw[body_start:body_start + closing.start()]
    if re.search(br"(?m)^lifecycle:", header_probe) is None:
        return 0

    findings = []
    if closing is None:
        if len(raw) == 8192:
            findings.append("frontmatter too large or unclosed")
        else:
            findings.append("missing closing --- delimiter")
    else:
        delimiter_end = body_start + closing.end()
        header_slice = raw[:delimiter_end]
        try:
            header_text = header_slice.decode("utf-8")
        except UnicodeDecodeError:
            findings.append("frontmatter header is not valid UTF-8")
        else:
            lines = header_text.splitlines()[1:-1]
            accepted = re.compile(r"^[a-z][a-z0-9_]*: \S.*$")
            values = {}
            for line_number, line in enumerate(lines, 2):
                if not line:
                    continue
                if not accepted.fullmatch(line):
                    findings.append("invalid frontmatter syntax on line " + str(line_number))
                    continue
                key, value = line.split(": ", 1)
                if key in values:
                    findings.append("duplicate key: " + key)
                else:
                    values[key] = value

            for key in ("id", "type", "summary", "lifecycle", "created"):
                if key not in values:
                    findings.append("missing required key: " + key)
            if "lifecycle" in values and values["lifecycle"] not in {"scratch", "research", "canon"}:
                findings.append("invalid lifecycle: " + values["lifecycle"])
            if "type" in values and values["type"] not in {"lesson", "project", "output", "capture"}:
                findings.append("invalid type: " + values["type"])
            if "summary" in values and (not values["summary"] or "\n" in values["summary"] or "\r" in values["summary"]):
                findings.append("summary must be non-empty and single-line")
            if "id" in values and re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", values["id"]) is None:
                findings.append("id must be kebab-case")
            if "created" in values:
                try:
                    datetime.date.fromisoformat(values["created"])
                except ValueError:
                    findings.append("created must be a real ISO calendar date")

    if findings:
        for finding in findings:
            print("memory-brain: " + finding, file=sys.stderr)
        return 2
    return 0


try:
    raise SystemExit(main())
except SystemExit:
    raise
except Exception:
    raise SystemExit(0)
' "$@"

exit $?
