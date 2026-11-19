#!/usr/bin/env python3
"""Crew plan checker (the governor runs it; agents cannot).

  python3 -I .claude/scripts/macos/plan-lint.py before <plan.md>   after the plan is written, before any build run
  python3 -I .claude/scripts/macos/plan-lint.py after  <plan.md>   after the docs phase, before the review

Checks the plan's structure, then its "Docs delta" table against the real docs:

  | Doc | Change | Old marker | New marker | Backed by |
  | `docs/x.md` | ADDED / MODIFIED / REMOVED | exact phrase now in the doc, or - | exact phrase that will be in the doc, or - | S-n / D-n |

before: every Old marker is found in the doc today (a quoted sentence that does not exist is a defect),
        every Backed-by id exists in the plan, every scenario row says why it fails without the change.
after:  every New marker is in the doc, every Old marker of a MODIFIED/REMOVED row is gone.
Markers are short phrases that sit on one line of the doc. Exit 0 = clean, 1 = defects, 2 = usage.
"""
import re
import sys
from pathlib import Path

REQUIRED = ["Goal and acceptance", "Decision Ledger", "Scenarios", "Phases", "Progress", "Assumption Log", "Docs delta"]
CHANGES = {"ADDED", "MODIFIED", "REMOVED"}


def cells(line):
    return [c.strip() for c in line.strip().strip("|").split("|")]


def section(text, title):
    m = re.search(r"^##+ +%s\b.*?$(.*?)(?=^## |\Z)" % re.escape(title), text, re.S | re.M)
    return m.group(1) if m else None


def rows(body):
    out = []
    for line in body.splitlines():
        if line.lstrip().startswith("|") and not re.match(r"^\s*\|[\s:|-]+\|\s*$", line):
            out.append(cells(line))
    return out[1:]  # drop the header row


def marker(cell):
    cell = cell.strip()
    if cell in {"-", "—", "–", ""}:
        return None
    return cell.strip("`").strip()


def main():
    if len(sys.argv) != 3 or sys.argv[1] not in {"before", "after"}:
        print(__doc__)
        return 2
    mode, plan = sys.argv[1], Path(sys.argv[2])
    text = plan.read_text(encoding="utf-8")
    bad = []

    for title in REQUIRED:
        if section(text, title) is None and not re.search(r"^##+ .*%s" % re.escape(title), text, re.M):
            bad.append("missing section: %s" % title)

    ledger = section(text, "Decision Ledger") or ""
    scen = section(text, "Scenarios") or ""
    ids = {r[0] for r in rows(ledger) + rows(scen) if r and re.fullmatch(r"[DS]-\d+", r[0])}
    seen = {}
    for r in rows(scen):
        if not r or not re.fullmatch(r"S-\d+", r[0]):
            continue
        if r[0] in seen:
            bad.append("scenario id repeated: %s" % r[0])
        seen[r[0]] = 1
        if len(r) < 4 or (len(r[3]) < 8 and r[3].lower() != "same"):
            bad.append("%s has no 'fails without the change because' reason" % r[0])
    if not seen:
        bad.append("no scenario rows found (| S-n | fixture | expect | fails without |)")

    delta = section(text, "Docs delta") or ""
    drows = [r for r in rows(delta) if len(r) >= 5]
    if not drows:
        if not re.search(r"Docs delta:\s*none", text, re.I):
            bad.append("Docs delta has no rows (write rows, or the line 'Docs delta: none - <why no behaviour changes>')")
    for r in drows:
        doc, change, old, new, by = r[0].strip("`"), r[1].upper(), marker(r[2]), marker(r[3]), r[4]
        where = "%s %s" % (doc, change)
        path = Path(doc)
        if change not in CHANGES:
            bad.append("%s: change must be ADDED, MODIFIED or REMOVED" % where)
            continue
        if not path.is_file():
            bad.append("%s: doc does not exist" % where)
            continue
        doc_text = path.read_text(encoding="utf-8", errors="replace")
        cited = set(re.findall(r"\b[DS]-\d+\b", by))
        if not cited:
            bad.append("%s: 'Backed by' names no S-n or D-n" % where)
        for i in cited - ids:
            bad.append("%s: backed by %s, which the plan does not define" % (where, i))
        if change in {"MODIFIED", "REMOVED"} and not old:
            bad.append("%s: needs an Old marker" % where)
        if change in {"ADDED", "MODIFIED"} and not new:
            bad.append("%s: needs a New marker" % where)
        if mode == "before" and old and old not in doc_text:
            bad.append("%s: Old marker not found in the doc now: %r" % (where, old))
        if mode == "after":
            if new and new not in doc_text:
                bad.append("%s: New marker missing from the doc: %r" % (where, new))
            if old and change in {"MODIFIED", "REMOVED"} and old in doc_text:
                bad.append("%s: Old marker still in the doc: %r" % (where, old))

    if bad:
        print("plan-lint %s: %d defect(s) in %s" % (mode, len(bad), plan))
        for b in bad:
            print("  - " + b)
        return 1
    print("plan-lint %s: clean (%d scenario(s), %d docs-delta row(s)) in %s" % (mode, len(seen), len(drows), plan))
    return 0


if __name__ == "__main__":
    sys.exit(main())
