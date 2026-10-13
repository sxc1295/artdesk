"""Rebuild offline thumbnails from the catalog and verified local images."""
from __future__ import annotations

import base64
from collections import Counter
import hashlib
import io
import json
from pathlib import Path

from PIL import Image, ImageOps

ROOT = Path(__file__).resolve().parents[1]


def image_path(relative: str) -> Path:
    path = (ROOT / relative).resolve()
    if not path.is_relative_to((ROOT / "images").resolve()):
        raise ValueError(f"Image outside images/: {relative}")
    return path


def main() -> None:
    records = json.loads((ROOT / "data/artworks.json").read_text("utf-8-sig"))
    ids = [row["id"] for row in records]
    if len(ids) != len(set(ids)):
        raise ValueError("Duplicate artwork IDs")
    gallery = []
    for row in records:
        path = image_path(row["file"])
        raw = path.read_bytes()
        if hashlib.sha256(raw).hexdigest() != row["sha256"]:
            raise ValueError(f"Image checksum mismatch: {row['file']}")
        with Image.open(io.BytesIO(raw)) as source:
            source.load()
            preview = ImageOps.exif_transpose(source).convert("RGB")
            preview.thumbnail((1000, 800), Image.Resampling.LANCZOS)
            output = io.BytesIO()
            preview.save(output, "JPEG", quality=76, optimize=True)
        public = {key: value for key, value in row.items()
                  if key not in ("file", "sha256", "imageSource")}
        public["thumb"] = "data:image/jpeg;base64," + base64.b64encode(output.getvalue()).decode("ascii")
        gallery.append(public)
    stats = {
        "total": len(records),
        "newCount": 0,
        "categories": dict(Counter(row["category"] for row in records)),
        "museums": dict(Counter(row["museumZh"] for row in records)),
    }
    target = ROOT / "gallery-data.json"
    temporary = target.with_suffix(".json.tmp")
    temporary.write_text(json.dumps({"artworks": gallery, "stats": stats},
                                   ensure_ascii=False, separators=(",", ":")), "utf-8")
    temporary.replace(target)
    print(f"Built offline gallery for {len(gallery)} verified artworks.")


if __name__ == "__main__":
    main()
