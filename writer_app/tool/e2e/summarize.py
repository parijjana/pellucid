#!/usr/bin/env python3
"""Turns `flutter test --machine` output into a pass/fail table per check number.

Test names look like "Check 3: undo/redo ...". Tests that carry a known app bug
print an XFAIL| line and count as XFAIL (expected failure, bug documented).
"""
import json
import re
import sys
from collections import OrderedDict

path = sys.argv[1]
names, results, prints, errors = {}, OrderedDict(), [], {}
for raw in open(path, errors="replace"):
    raw = raw.strip()
    if not raw.startswith("{") and not raw.startswith("["):
        continue
    try:
        ev = json.loads(raw)
    except Exception:
        continue
    for e in ev if isinstance(ev, list) else [ev]:
        t = e.get("type")
        if t == "testStart":
            names[e["test"]["id"]] = e["test"]["name"]
        elif t == "print":
            prints.append(e.get("message", ""))
        elif t == "error":
            errors.setdefault(e["testID"], []).append(e.get("error", "").split("\n")[0])
        elif t == "testDone" and not e.get("hidden"):
            results[e["testID"]] = e.get("result"), e.get("skipped")

xfail = {}
for p in prints:
    if p.startswith("XFAIL|"):
        parts = p.split("|")
        xfail[parts[1]] = parts[2]

rows = OrderedDict()
for tid, (res, skipped) in results.items():
    name = names.get(tid, "?")
    m = re.match(r"(?:.*?)Check (\w+)", name)
    if not m:
        continue
    num = m.group(1)
    if skipped:
        status = "SKIP"
    elif name in xfail:
        status = "XFAIL"
    elif res == "success":
        status = "PASS"
    else:
        status = "FAIL"
    rows.setdefault(num, []).append((status, name, errors.get(tid, [""])[0] if status == "FAIL" else xfail.get(name, "")))

print("\n==== RESULTS BY CHECK ====")
bad = 0
for num in sorted(rows, key=lambda k: (0, int(k)) if k.isdigit() else (1, k)):
    sts = [r[0] for r in rows[num]]
    agg = "FAIL" if "FAIL" in sts else ("XFAIL" if "XFAIL" in sts else ("SKIP" if all(s == "SKIP" for s in sts) else "PASS"))
    if agg == "FAIL":
        bad += 1
    print(f"Check {num:>5}  {agg:<6}")
    for st, name, why in rows[num]:
        print(f"           {st:<6} {name}" + (f"\n                  {why}" if why else ""))

print("\n==== EVIDENCE / TIMING ====")
for p in prints:
    if p.startswith(("TIMING|", "EVID|", "E2E|", "XFAIL|")):
        print(p)

total = sum(len(v) for v in rows.values())
print(f"\n{total} tests, {bad} checks failing")
sys.exit(1 if bad else 0)
