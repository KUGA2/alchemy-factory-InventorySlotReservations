"""Validate every gallery image that will be attached to a GitHub release."""

from pathlib import Path
from struct import unpack


root = Path(__file__).resolve().parents[1] / "images"
gallery = sorted(root.iterdir())
assert gallery, "No release images found"
assert (root / "title.png").is_file(), "The title image must be present"
for image in gallery:
    assert image.is_file() and not image.is_symlink(), image
    assert image.suffix.lower() == ".png", f"Nexus requires PNG, not {image}"
    data = image.read_bytes()
    assert len(data) <= 8 * 1024 * 1024, f"Image exceeds Nexus's 8 MiB limit: {image}"
    assert data[:16] == b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR", f"Not a PNG: {image}"
    width, height = unpack(">II", data[16:24])
    assert 0 < width <= 8000 and 0 < height <= 8000, f"Invalid image dimensions: {image}"
    print(f"{image.name}: {width}x{height}, {len(data)} bytes")
