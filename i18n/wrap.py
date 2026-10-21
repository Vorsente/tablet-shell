#!/usr/bin/env python3
# One-off helper: wraps Russian string literals in QML/JS with Tr.t(...) and adds the import.
# Usage: wrap.py [--apply] files...   (without --apply: report what would change)
import re
import sys

CYR = re.compile(r"[А-Яа-яЁё]")
SKIP = {"йцукенгшщзхъ", "фывапролджэ", "ячсмитьбюё", "РУ", "/Сценарии", "/Экспорт",
        "section:Батарея", "section:Сводка", "П", "В", "С", "Ч", "ч", "мин"}


def scan(line):
    """yield (start, end, quote, text) of string literals before a // comment"""
    i, n = 0, len(line)
    while i < n:
        c = line[i]
        if c == "/" and i + 1 < n and line[i + 1] == "/":
            return
        if c in "\"'`":
            j = i + 1
            while j < n and line[j] != c:
                j += 2 if line[j] == "\\" else 1
            yield i, j + 1, c, line[i + 1:j]
            i = j + 1
            continue
        i += 1


def process(path, apply):
    src = open(path).read().split("\n")
    out, changed, report = [], False, []
    in_block = False
    for no, line in enumerate(src, 1):
        stripped = line.strip()
        if in_block or stripped.startswith("/*") or stripped.startswith("*"):
            in_block = ("*/" not in line) and (in_block or stripped.startswith("/*"))
            out.append(line)
            continue
        pieces, last = [], 0
        for s, e, q, text in scan(line):
            if not CYR.search(text) or text in SKIP or q == "`":
                continue
            before = line[:s].rstrip()
            after = line[e:].lstrip()
            if before.endswith("Tr.t(") or before.endswith("qsTr("):
                continue
            # an object key ({ "ключ": ... }) cannot be a call; comparisons are fine (both sides translate)
            risky = after.startswith(":") and (before == "" or before.endswith(("{", ",")))
            if risky:
                report.append(f"{path}:{no}: RISKY {line.strip()[:150]}")
                continue
            pieces.append(line[last:s] + "Tr.t(" + line[s:e] + ")")
            last = e
        if pieces:
            line = "".join(pieces) + line[last:]
            changed = True
        out.append(line)
    if changed and path.endswith(".qml") and not any(l.startswith('import "Tr.js"') for l in out):
        idx = max(i for i, l in enumerate(out) if l.startswith("import "))
        out.insert(idx + 1, 'import "Tr.js" as Tr')
    for r in report:
        print(r)
    if apply and changed:
        open(path, "w").write("\n".join(out))
    return changed


apply = "--apply" in sys.argv
for p in [a for a in sys.argv[1:] if a != "--apply"]:
    process(p, apply)
