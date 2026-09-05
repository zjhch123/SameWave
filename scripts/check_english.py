#!/usr/bin/env python3
"""Check app-owned English copy, documentation filenames, and local Markdown links."""
from pathlib import Path
import re
import sys
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[1]
HAN = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff\U00020000-\U000323af]")
# These are recognized transcript labels in a supported input language, never UI copy.
TRANSCRIPT_LABELS = 'let labels = ["Other party", "\u5bf9\u65b9", "Me", "\u6211"]'
paths = sorted({
    *ROOT.glob("*.md"), *ROOT.joinpath("doc").rglob("*.md"),
    *ROOT.joinpath("Sources").rglob("*.swift"),
    ROOT / "project.yml", ROOT / "build.sh", ROOT / "Sources/Resources/Info.plist",
})
errors = []
for path in paths:
    relative = path.relative_to(ROOT)
    if HAN.search(str(relative)):
        errors.append(f"{relative}: filename contains Chinese text")
    text = path.read_text()
    for number, line in enumerate(text.splitlines(), 1):
        if relative.as_posix() == "Sources/Insights/TranscriptRefiner.swift" and line.strip() == TRANSCRIPT_LABELS:
            continue
        if HAN.search(line):
            errors.append(f"{relative}:{number}: Chinese copy remains")
    if path.suffix == ".md":
        for target in re.findall(r"\[[^\]]*\]\(([^\s)]+)\)", text):
            url = urlsplit(target)
            if url.scheme or not url.path:
                continue
            if not (path.parent / unquote(url.path)).exists():
                errors.append(f"{relative}: broken local link: {target}")
if errors:
    print("\n".join(errors), file=sys.stderr)
    sys.exit(1)
print(f"English copy and local Markdown links verified in {len(paths)} files.")
