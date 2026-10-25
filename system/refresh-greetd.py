#!/usr/bin/env python3
"""Change only tablet-shell's greetd launch command, preserving other TOML settings.

Used exclusively after the caller confirms that tablet-shell already owns the
existing greeter session. On normal installation greeter.sh writes a fresh file.
"""
import pathlib
import re
import sys

config = pathlib.Path(sys.argv[1])
content = config.read_text(encoding="utf-8")
lines = content.splitlines(keepends=True)
in_session = False
replaced = False
for idx, line in enumerate(lines):
    header = re.match(r"^\s*\[([^\]]+)\]", line)
    if header:
        in_session = header.group(1).strip() == "default_session"
    if in_session and re.match(r"^\s*command\s*=", line):
        lines[idx] = 'command = "/usr/local/libexec/tablet-shell-greeter"\n'
        replaced = True
        break
if not replaced:
    raise SystemExit("No [default_session] command in existing greetd config: refusing overwrite")
new = "".join(lines)
if new != content:
    config.write_text(new, encoding="utf-8")
