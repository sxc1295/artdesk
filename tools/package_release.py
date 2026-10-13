"""Package only explicitly approved source and artwork files; never local state."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE_FILES = [
    "README.md", "使用说明.txt", "LICENSE", "THIRD_PARTY_NOTICES.md", "requirements-dev.txt",
    "ArtDesk.ps1", "Queue-ArtDesk.ps1", "Install-ArtDesk.ps1", "Uninstall-ArtDesk.ps1",
    "Open-ArtDesk.cmd", "Install-ArtDesk.cmd", "Uninstall-ArtDesk.cmd",
    "app-template.html", "data/artworks.json", "tests/Test-ArtDesk.ps1",
    "tools/build_gallery.py", "tools/package_release.py",
]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "dist")
    parser.add_argument("--version", default="1.0.0")
    args = parser.parse_args()
    if not all(c.isalnum() or c in ".-" for c in args.version):
        parser.error("Version must contain only letters, digits, dots and hyphens")
    records = json.loads((ROOT / "data/artworks.json").read_text("utf-8-sig"))
    image_files = []
    for row in records:
        relative = Path(row["file"])
        full = (ROOT / relative).resolve()
        if relative.is_absolute() or not full.is_relative_to((ROOT / "images").resolve()):
            raise ValueError(f"Unsafe image path: {relative}")
        if hashlib.sha256(full.read_bytes()).hexdigest() != row["sha256"]:
            raise ValueError(f"Checksum mismatch: {relative}")
        image_files.append(relative.as_posix())
    gallery = json.loads((ROOT / "gallery-data.json").read_text("utf-8-sig"))
    if [row["id"] for row in records] != [row["id"] for row in gallery["artworks"]]:
        raise ValueError("Catalog/gallery artwork IDs differ")
    args.output.mkdir(parents=True, exist_ok=True)
    target = args.output / f"ArtDesk-v{args.version}-Windows.zip"
    files = SOURCE_FILES + ["gallery-data.json"] + image_files
    for name in files:
        if not (ROOT / name).is_file():
            raise FileNotFoundError(name)
    with zipfile.ZipFile(target, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for name in files:
            archive.write(ROOT / name, "ArtDesk/" + name)
    with zipfile.ZipFile(target) as archive:
        bad = archive.testzip()
        if bad:
            raise ValueError(f"Bad ZIP member: {bad}")
        if len(archive.namelist()) != len(files):
            raise ValueError("ZIP file count mismatch")
    checksum = hashlib.sha256(target.read_bytes()).hexdigest()
    (args.output / "SHA256SUMS.txt").write_text(f"{checksum}  {target.name}\n", "ascii")
    print(f"Verified {target.name}: {len(files)} files, {len(records)} artworks, {target.stat().st_size:,} bytes")
    print(f"SHA256: {checksum}")


if __name__ == "__main__":
    main()
