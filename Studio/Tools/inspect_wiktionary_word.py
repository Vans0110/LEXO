from __future__ import annotations

import argparse
import gzip
import json
import sys
from pathlib import Path


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser()
    parser.add_argument("source")
    parser.add_argument("word")
    args = parser.parse_args()
    source = Path(args.source)
    target = args.word.strip().lower()
    with gzip.open(source, "rt", encoding="utf-8", errors="ignore") as handle:
        for line in handle:
            item = json.loads(line)
            if str(item.get("word") or "").strip().lower() != target:
                continue
            print(json.dumps(item, ensure_ascii=False)[:12000])
            return
    raise SystemExit(f"Word not found: {target}")


if __name__ == "__main__":
    main()
