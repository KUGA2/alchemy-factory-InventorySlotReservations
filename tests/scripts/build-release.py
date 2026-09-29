#!/usr/bin/env python3
"""Build a minimal UE4SS mod ZIP from an explicit allowlist of source files."""

import argparse
import json
import re
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo


ROOT = Path(__file__).resolve().parents[2]
MOD_NAME = "InventorySlotReservations"
FILES = (
    "mod.json",
    "LICENSE",
    "Scripts/main.lua",
    "Scripts/config.lua",
    "Scripts/chestpull.lua",
    "Scripts/slot_binding.lua",
    "Scripts/reservation_policy.lua",
)


def build(tag: str | None, output_dir: Path) -> Path:
    version = json.loads((ROOT / "mod.json").read_text(encoding="utf-8"))["version"]
    if not isinstance(version, str) or not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
        raise ValueError("mod.json must contain a numeric MAJOR.MINOR.PATCH version")
    if tag is not None and tag != f"v{version}":
        raise ValueError(f"Release tag {tag!r} does not match mod.json version v{version}")

    output_dir.mkdir(parents=True, exist_ok=True)
    archive = output_dir / f"{MOD_NAME}-{version}.zip"
    with ZipFile(archive, "w", compression=ZIP_DEFLATED, compresslevel=9) as bundle:
        for relative in FILES:
            path = ROOT / relative
            if not path.is_file() or path.is_symlink():
                raise ValueError(f"Missing or symlinked package file: {path}")
            info = ZipInfo(f"{MOD_NAME}/{relative}", date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            bundle.writestr(info, path.read_bytes(), compress_type=ZIP_DEFLATED, compresslevel=9)
    return archive


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tag", help="Require this release tag to match mod.json (e.g. v0.20.0)")
    parser.add_argument("--output-dir", type=Path, default=ROOT / "dist")
    args = parser.parse_args()
    print(build(args.tag, args.output_dir))
