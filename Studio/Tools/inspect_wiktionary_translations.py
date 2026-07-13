from __future__ import annotations

import argparse
import gzip
import json
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("source")
    parser.add_argument("--needle", default="Ukrainian")
    parser.add_argument("--limit", type=int, default=5)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    source = Path(args.source)
    hits = 0
    lines = 0
    with gzip.open(source, "rt", encoding="utf-8", errors="ignore") as handle:
        for line in handle:
            lines += 1
            if args.needle not in line and '"uk"' not in line:
                continue
            item = json.loads(line)
            for sense in item.get("senses") or []:
                for translation in sense.get("translations") or []:
                    if (
                        args.needle in str(translation)
                        or translation.get("code") == "uk"
                        or translation.get("lang_code") == "uk"
                        or translation.get("lang") == "Ukrainian"
                    ):
                        print(
                            json.dumps(
                                {
                                    "word": item.get("word"),
                                    "pos": item.get("pos"),
                                    "translation": translation,
                                },
                                ensure_ascii=False,
                            )
                        )
                        hits += 1
                        break
                if hits >= args.limit:
                    break
            if hits >= args.limit:
                break
    print(json.dumps({"lines": lines, "hits": hits}, ensure_ascii=False))


if __name__ == "__main__":
    main()
