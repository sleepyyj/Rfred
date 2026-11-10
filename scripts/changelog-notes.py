#!/usr/bin/env python3
"""Print the CHANGELOG.md section for a version. Exit 1 if missing."""
import re
import sys
from pathlib import Path

def section(path: Path, ver: str) -> str | None:
    if not path.is_file():
        return None
    ver = ver[1:] if ver[:1] in "vV" else ver
    text = path.read_text(encoding="utf-8")
    pattern = re.compile(r"^##[ \t]+(?:v)?" + re.escape(ver) + r"(?:\s|$)", re.M)
    match = pattern.search(text)
    if not match:
        return None
    rest = text[match.end():]
    nxt = re.search(r"^##[ \t]+", rest, re.M)
    end = match.end() + (nxt.start() if nxt else len(rest))
    body = text[match.start():end].strip()
    return (body + "\n") if body else None

def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: changelog-notes.py <version>", file=sys.stderr)
        return 2
    root = Path(__file__).resolve().parent.parent
    body = section(root / "CHANGELOG.md", sys.argv[1])
    if body is None:
        return 1
    sys.stdout.write(body)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
