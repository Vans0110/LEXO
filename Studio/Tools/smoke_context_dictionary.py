from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from engine.context_dictionary_resolver import ContextDictionaryResolver


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser()
    parser.add_argument("--word", default="classroom")
    parser.add_argument("--lemma", default="")
    parser.add_argument("--pos", default="noun")
    parser.add_argument("--target-lang", default="uk")
    args = parser.parse_args()
    resolver = ContextDictionaryResolver(Path("."))
    entry = resolver.build_entry(
        surface=args.word,
        lemma=args.lemma or args.word,
        pos=args.pos,
        target_lang=args.target_lang,
    )
    print(
        json.dumps(
            {
                "target_lang": entry.get("target_lang"),
                "source": entry["entries"][0]["source"] if entry["entries"] else "",
                "has_content": entry.get("has_content"),
                "translations": entry.get("translations", [])[:12],
            },
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    main()
