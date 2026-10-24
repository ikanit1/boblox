"""Validate only the project vault; optionally prove a bounded file read/write round trip."""

from __future__ import annotations

import argparse
import json
import re
import tempfile
from pathlib import Path
from urllib.parse import unquote, urlsplit


REPO = Path(__file__).resolve().parents[2]
VAULT = REPO / "docs" / "obsidian-vault"
REQUIRED = (
    "00-Dashboard", "01-Game-Design", "02-Architecture", "03-Gameplay-Systems",
    "04-Assets", "05-World-Design", "06-Testing", "07-Tasks", "08-Decisions",
    "09-AI-Skills", "10-Releases",
)
WIKI = re.compile(r"!?\[\[([^\]]+)\]\]")
MARKDOWN = re.compile(r"(?<!!)\[[^\]\n]+\]\((<[^>]+>|[^)\n]+)\)")
FENCES = re.compile(r"^\s*(`{3,}|~{3,}).*$")


def prose(text: str) -> str:
    """Ignore fenced examples when checking real navigation links."""
    lines: list[str] = []
    fence = ""
    for line in text.splitlines():
        match = FENCES.match(line)
        if match:
            token = match.group(1)
            if not fence:
                fence = token[0]
            elif token[0] == fence:
                fence = ""
            lines.append("")
        else:
            lines.append("" if fence else line)
    return "\n".join(lines)


def validate() -> dict:
    notes = sorted(VAULT.rglob("*.md"))
    notes = [p for p in notes if ".obsidian" not in p.relative_to(VAULT).parts]
    by_name: dict[str, list[Path]] = {}
    for note in notes:
        by_name.setdefault(note.stem, []).append(note)
    errors: list[str] = []
    wiki_count = 0
    local_count = 0
    inbound = {p: 0 for p in notes}
    for folder in REQUIRED:
        if not (VAULT / folder).is_dir():
            errors.append(f"Missing required folder: {folder}")
    for source in notes:
        body = prose(source.read_text(encoding="utf-8-sig"))
        label = source.relative_to(VAULT).as_posix()
        for match in WIKI.finditer(body):
            wiki_count += 1
            target = match.group(1).split("|", 1)[0].split("#", 1)[0].strip()
            if not target:
                continue
            path = Path(target)
            if path.is_absolute() or ".." in path.parts:
                errors.append(f"{label}: wikilink escapes vault: {target}")
                continue
            if path.suffix.lower() != ".md":
                path = Path(str(path) + ".md")
            candidates = [VAULT / path, source.parent / path]
            resolved = next((p.resolve() for p in candidates if p.is_file()), None)
            if resolved is None and "/" not in target and "\\" not in target:
                matches = by_name.get(path.stem, [])
                if len(matches) == 1:
                    resolved = matches[0]
                elif len(matches) > 1:
                    errors.append(f"{label}: ambiguous wikilink: {target}")
                    continue
            if resolved is None:
                errors.append(f"{label}: unresolved wikilink: {target}")
            elif resolved in inbound:
                inbound[resolved] += 1
        for match in MARKDOWN.finditer(body):
            target = match.group(1).strip().removeprefix("<").removesuffix(">")
            if target.startswith("#") or urlsplit(target).scheme:
                continue
            target = unquote(target.split("#", 1)[0].split("?", 1)[0])
            if not target:
                continue
            local_count += 1
            path = (source.parent / target).resolve()
            if not path.exists():
                errors.append(f"{label}: missing local target: {target}")
    return {
        "vault": str(VAULT),
        "notes": len(notes),
        "requiredFolders": len(REQUIRED),
        "wikilinks": wiki_count,
        "localMarkdownLinks": local_count,
        "orphans": [p.relative_to(VAULT).as_posix() for p, n in inbound.items() if n == 0],
        "errors": errors,
        "passed": not errors,
        "scope": "Local file existence and unambiguous note targets; no web/heading or UI claim.",
    }


def file_smoke() -> dict:
    """Create an exclusive owned note, read UTF-8, then remove only that exact file."""
    folder = VAULT / "00-Dashboard"
    payload = "# QA file round trip\n\nПроверка UTF-8: комната и правила.\n"
    path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", newline="\n", suffix=".md",
            prefix=".qa-file-roundtrip-", dir=folder, delete=False,
        ) as handle:
            path = Path(handle.name).resolve()
            handle.write(payload)
        if path.parent != folder.resolve():
            raise RuntimeError("Smoke path escaped the project dashboard")
        if path.read_text(encoding="utf-8") != payload:
            raise RuntimeError("UTF-8 read/write mismatch")
        return {"method": "filesystem", "passed": True, "temporaryNoteRemoved": True}
    finally:
        if path is not None:
            path.unlink(missing_ok=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write-smoke", action="store_true", help="Scoped temporary note round trip")
    args = parser.parse_args()
    result = validate()
    if args.write_smoke:
        result["readWrite"] = file_smoke()
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
