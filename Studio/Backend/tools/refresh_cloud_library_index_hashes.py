from __future__ import annotations

import argparse
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--library", type=Path, required=True)
    parser.add_argument("--book-id", action="append", required=True)
    args = parser.parse_args()
    library = args.library.resolve()
    index_path = library / "library_index.json"
    payload = json.loads(index_path.read_text(encoding="utf-8"))
    selected = set(args.book_id)
    updated = []
    now = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
    for book in payload.get("books") or []:
        book_id = str(book.get("book_id") or "")
        if book_id not in selected:
            continue
        zip_path = library / str(book.get("zip_path") or "")
        if not zip_path.exists():
            raise FileNotFoundError(zip_path)
        book["content_hash"] = sha256(zip_path)
        book["size_bytes"] = zip_path.stat().st_size
        book["updated_at"] = now
        updated.append(book_id)
    missing = selected - set(updated)
    if missing:
        raise RuntimeError(f"Books absent from library index: {sorted(missing)}")
    payload["updated_at"] = now
    temporary = index_path.with_suffix(".json.tmp")
    temporary.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    temporary.replace(index_path)
    print(json.dumps({"updated": updated, "updated_at": now}, indent=2))


if __name__ == "__main__":
    main()
