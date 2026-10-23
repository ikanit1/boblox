"""Install pinned Windows CLI binaries from official releases after SHA256 validation.

No Studio install, account changes, PATH mutation, or third-party setup scripts.
"""
from pathlib import Path
import hashlib
import json
import os
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
BASE = Path(os.environ["LOCALAPPDATA"]) / "RobloxDev"
BIN = BASE / "bin"
CACHE = BASE / "downloads"
EXPECTED = {
    "rojo-rbx/rojo": {"rojo.exe"},
    "JohnnyMorganz/StyLua": {"stylua.exe"},
    "Kampfkarren/selene": {"selene.exe"},
    "luau-lang/luau": {"luau.exe", "luau-analyze.exe", "luau-compile.exe"},
    "lune-org/lune": {"lune.exe"},
}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    manifest = json.loads((ROOT / "docs/toolchain.json").read_text(encoding="utf-8-sig"))
    BIN.mkdir(parents=True, exist_ok=True)
    CACHE.mkdir(parents=True, exist_ok=True)
    for asset in manifest["assets"]:
        if not asset["asset_name"].endswith(".zip"):
            continue
        repo = asset["repository"]
        names = EXPECTED[repo]
        url = asset["source_url"]
        assert url.startswith(f"https://github.com/{repo}/releases/download/")
        expected = asset["official_sha256"].lower()
        assert len(expected) == 64
        archive = CACHE / (repo.replace("/", "-") + "-" + asset["asset_name"])
        if not archive.exists() or digest(archive) != expected:
            request = urllib.request.Request(url, headers={"User-Agent": "RuleRoomBuild/0.2"})
            with urllib.request.urlopen(request, timeout=60) as response:
                data = response.read()
            assert hashlib.sha256(data).hexdigest() == expected, f"Checksum failed: {repo}"
            archive.write_bytes(data)
        found = set()
        with zipfile.ZipFile(archive) as bundle:
            for entry in bundle.infolist():
                name = Path(entry.filename).name
                if name in names:
                    assert name not in found, f"Ambiguous binary: {name}"
                    # Write only selected basenames; never extract archive paths.
                    payload = bundle.read(entry)
                    destination = BIN / name
                    if not destination.exists() or destination.read_bytes() != payload:
                        destination.write_bytes(payload)
                    found.add(name)
        assert found == names, f"Missing binaries: {names - found}"
        print(f"Verified {repo} {asset['tag']}: {', '.join(sorted(found))}")


if __name__ == "__main__":
    main()
