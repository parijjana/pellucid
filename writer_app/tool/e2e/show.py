#!/usr/bin/env python3
"""Prints every test `print` line (failures, EVID, TIMING) from a machine.jsonl: show.py [path] [maxlen]."""
import json
import sys

path = sys.argv[1] if len(sys.argv) > 1 else "/tmp/e2e-out-claude/machine.jsonl"
maxlen = int(sys.argv[2]) if len(sys.argv) > 2 else 1800
for line in open(path, errors="replace"):
    try:
        e = json.loads(line)
    except Exception:
        continue
    for x in e if isinstance(e, list) else [e]:
        if x.get("type") == "print":
            print(x["message"][:maxlen])
