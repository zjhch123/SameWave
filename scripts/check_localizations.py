#!/usr/bin/env python3
"""Validate complete UI/permission translations and interpolation contracts."""
from collections import Counter
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
PLACEHOLDER = re.compile(r"%(?:\d+\$)?(?:lld|llu|ld|lu|d|u|@|f)")


def signature(value):
    return Counter(re.sub(r"^%\d+\$", "%", item) for item in PLACEHOLDER.findall(value))


def units(node):
    if "stringUnit" in node:
        yield node["stringUnit"]
    for variants in node.get("variations", {}).values():
        for variant in variants.values():
            yield from units(variant)


def check():
    errors = []
    total = 0
    for path in sorted((ROOT / "Sources/Resources").glob("*.xcstrings")):
        catalog = json.loads(path.read_text())
        if catalog.get("sourceLanguage") != "en":
            errors.append(f"{path.name}: source language must be English")
        for key, entry in catalog["strings"].items():
            if entry.get("shouldTranslate") is False:
                continue
            total += 1
            label = f"{path.name}: {key!r}"
            if entry.get("extractionState") == "stale":
                errors.append(f"{label}: remove obsolete copy")
            locales = entry.get("localizations", {})
            for language in ("en", "zh-Hans"):
                values = list(units(locales.get(language, {})))
                if not values or any(v.get("state") != "translated" or not v.get("value", "").strip() for v in values):
                    errors.append(f"{label}: incomplete {language} translation")
            english = locales.get("en", {})
            source = english.get("stringUnit", {}).get("value", key)
            # Plural substitutions retain the source key's argument contract.
            if english.get("substitutions"):
                source = key
            for unit in units(locales.get("zh-Hans", {})):
                if signature(unit["value"]) != signature(source):
                    errors.append(f"{label}: Chinese placeholders differ from English")
            plural = english.get("variations", {}).get("plural")
            if plural and not {"one", "other"}.issubset(plural):
                errors.append(f"{label}: English plural requires one and other")
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print(f"Verified {total} English/Simplified Chinese UI and permission translations.")
    return 0


if __name__ == "__main__":
    sys.exit(check())
