"""Exercise native Obsidian CLI only against this registered project vault."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import uuid
from pathlib import Path


VAULT = Path(__file__).resolve().parents[2] / "docs" / "obsidian-vault"


def normalized(path: str | Path) -> str:
    return os.path.normcase(os.path.normpath(str(path))).casefold()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--executable", default="D:/obsidian/Obsidian.com")
    args = parser.parse_args()
    exe = Path(args.executable)
    metadata = Path(os.environ["APPDATA"]) / "obsidian" / "obsidian.json"
    if not exe.is_file() or not metadata.is_file():
        print("NOT READY: installed Obsidian.com and registered project vault are required.")
        return 2
    # Only app registration metadata; never read other vault notes.
    entries = json.loads(metadata.read_text(encoding="utf-8")).get("vaults", {})
    ids = [key for key, item in entries.items() if normalized(item.get("path", "")) == normalized(VAULT)]
    if len(ids) != 1:
        print("NOT READY: open this project's docs/obsidian-vault through Obsidian first.")
        return 2
    vault_id = ids[0]

    def run(*arguments: str) -> str:
        result = subprocess.run(
            [str(exe), f"vault={vault_id}", *arguments], cwd=VAULT,
            capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=25,
        )
        if result.returncode:
            raise RuntimeError(f"CLI exited {result.returncode}: {result.stderr.strip()}")
        return result.stdout.strip()

    # Verify the target before asking for any note content or writes.
    path_output = run("vault", "info=path")
    if not any(normalized(line.strip()) == normalized(VAULT) for line in path_output.splitlines()):
        raise RuntimeError("CLI did not confirm the exact project vault. Enable native CLI in Settings > General.")
    dashboard = run("read", "path=00-Dashboard/Dashboard.md")
    if "# Комната, которая меняет правила" not in dashboard:
        raise RuntimeError("Project Dashboard read did not return the expected content")

    marker = "RuleRoom CLI roundtrip " + uuid.uuid4().hex
    # A dot-prefixed probe was not readable in the verified Obsidian 1.12.7 path.
    relative = "00-Dashboard/QA-CLI-" + uuid.uuid4().hex + ".md"
    probe = VAULT / relative
    if probe.exists():
        raise RuntimeError("Refusing to overwrite a pre-existing probe path")
    try:
        run("create", f"path={relative}", f"content={marker}")
        if not probe.is_file() or probe.read_text(encoding="utf-8").strip() != marker:
            raise RuntimeError("Native CLI create did not produce the expected project-only note")
        if marker not in run("read", f"path={relative}"):
            raise RuntimeError("Native CLI read did not return its newly created note")
    finally:
        # Remove only our exact unchanged temporary note, never arbitrary content.
        if probe.is_file() and probe.read_text(encoding="utf-8").strip() == marker:
            probe.unlink()
    print(json.dumps({
        "passed": True, "method": "native CLI", "vault": str(VAULT),
        "dashboardRead": True, "createReadRoundTrip": True,
        "temporaryNoteRemoved": not probe.exists(),
        "scope": "Explicit project vault ID, no personal notes or global settings modified.",
    }, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
