"""Check the release ZIP contains installable mod files, not test or game data."""

import importlib.util
import json
import tempfile
from pathlib import Path
from zipfile import ZipFile


root = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("build_release", root / "tests/scripts/build-release.py")
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)
version = json.loads((root / "mod.json").read_text(encoding="utf-8"))["version"]

with tempfile.TemporaryDirectory() as temp:
    output_dir = Path(temp)
    archive = builder.build(f"v{version}", output_dir)
    first = archive.read_bytes()
    assert builder.build(f"v{version}", output_dir).read_bytes() == first
    with ZipFile(archive) as bundle:
        expected = {f"InventorySlotReservations/{name}" for name in builder.FILES}
        assert set(bundle.namelist()) == expected, bundle.namelist()
        for name in builder.FILES:
            assert bundle.read(f"InventorySlotReservations/{name}") == (root / name).read_bytes()
    try:
        builder.build("v0.0.0", output_dir)
    except ValueError:
        pass
    else:
        raise AssertionError("Mismatched version tag was accepted")
print("Release package checks passed")
