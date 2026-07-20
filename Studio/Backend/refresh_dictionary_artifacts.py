from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import tempfile
import zipfile
from pathlib import Path

from engine.library_dictionary import LibraryDictionaryStore, library_dictionary_source

TOKEN_RE = re.compile(r"[^\W_]+", re.UNICODE)


def _load(path: Path) -> dict:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError(f"Expected object: {path}")
    return payload


def _write(path: Path, payload: dict) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    os.replace(temporary, path)


def _tokens(value: object) -> list[str]:
    return [match.group(0).lower() for match in TOKEN_RE.finditer(str(value or ""))]


def _common_score(left: str, right: str) -> float:
    shortest = min(len(left), len(right))
    common = 0
    while common < shortest and left[common] == right[common]:
        common += 1
    if common < 3 or common / shortest < 0.6:
        return 0.0
    return common / shortest - abs(len(left) - len(right)) * 0.01


def _contains_sequence(haystack: list[str], wanted: list[str]) -> bool:
    if not wanted or len(wanted) > len(haystack):
        return False
    return any(
        haystack[index : index + len(wanted)] == wanted
        for index in range(len(haystack) - len(wanted) + 1)
    )


def _translation_candidates(
    translations: list[str],
    target_text: str,
) -> list[tuple[str, int, int, bool]]:
    target_tokens = _tokens(target_text)
    result: list[tuple[str, int, int, bool]] = []
    for translation in translations:
        wanted = _tokens(translation)
        if not wanted or len(wanted) > len(target_tokens):
            continue
        for index in range(len(target_tokens) - len(wanted) + 1):
            if target_tokens[index : index + len(wanted)] == wanted:
                result.append((translation, index, index + len(wanted) - 1, True))
    for translation in translations:
        wanted = _tokens(translation)
        if len(wanted) != 1:
            continue
        for index, target in enumerate(target_tokens):
            score = _common_score(wanted[0], target)
            if score > 0 and not any(
                item[0] == translation and item[1] == index for item in result
            ):
                result.append((translation, index, index, False))
    return result


def _select_translation(
    translations: list[str],
    target_text: str,
    *,
    source_index: int = 0,
    source_count: int = 1,
    claimed_spans: set[int] | None = None,
) -> tuple[str, int, int]:
    target_tokens = _tokens(target_text)
    claimed = claimed_spans or set()
    source_position = (source_index + 0.5) / max(source_count, 1)
    candidates = []
    for translation, start, end, exact in _translation_candidates(translations, target_text):
        occupied = set(range(start, end + 1))
        if occupied & claimed:
            continue
        target_position = ((start + end) / 2 + 0.5) / max(len(target_tokens), 1)
        candidates.append(
            (
                -(end - start + 1),
                0 if exact else 1,
                abs(source_position - target_position),
                translations.index(translation),
                translation,
                start,
                end,
            )
        )
    if not candidates:
        return "", -1, -1
    _, _, _, _, translation, start, end = min(candidates)
    return translation, start, end

def _block_in_source(block: str, source: str) -> bool:
    wanted = _tokens(block)
    haystack = _tokens(source)
    if not wanted or len(wanted) > len(haystack):
        return False
    for index in range(len(haystack) - len(wanted) + 1):
        matches = True
        for offset, token in enumerate(wanted):
            actual = haystack[index + offset]
            if actual == token:
                continue
            suffix = actual[len(token) :] if actual.startswith(token) else ""
            if suffix not in {"s", "es", "ed", "ing"}:
                matches = False
                break
        if matches:
            return True
    return False


def _segments(reader: dict) -> dict[str, dict]:
    result = {}
    for paragraph in reader.get("paragraphs") or []:
        if not isinstance(paragraph, dict):
            continue
        for segment in paragraph.get("segments_v2") or []:
            if isinstance(segment, dict):
                segment_id = str(segment.get("id") or "")
                if segment_id:
                    result[segment_id] = segment
    return result


def _canonical_dictionary_key(value: object) -> str:
    lemma, separator, pos = str(value or "").strip().partition("|")
    if not separator:
        return lemma.lower()
    return f"{lemma.lower()}|{pos.upper()}"


def _manifest_with_reader_lexicons(manifest: dict, languages: list[str]) -> dict:
    next_manifest = dict(manifest)
    files = dict(next_manifest.get("files") or {})
    lexicons = dict(files.get("reader_lexicons") or {})
    for lang in languages:
        lexicons[lang] = f"reader_lexicon_{lang}.json"
    files["reader_lexicons"] = lexicons
    files.pop("dictionaries", None)
    files.pop("word_to_word", None)
    files.pop("word_to_word_by_lang", None)
    next_manifest["files"] = files
    return next_manifest


def _manifest_entry(key: str, record: dict, lang: str, existing: dict | None) -> dict:
    lemma, _, pos = key.partition("|")
    translations = [str(value) for value in record.get("translations") or []]
    entry = dict(existing or {})
    entry.update(
        {
            "query": str(entry.get("query") or lemma),
            "lemma": lemma,
            "detected_part_of_speech": pos,
            "translations": translations,
            "part_of_speech": pos,
            "word_found": bool(translations),
            "has_content": bool(translations),
            "dictionary_key": key,
            "target_lang": lang,
            "offline_manifest": True,
            "translation_variants": record.get("variants") or [],
        }
    )
    nested = entry.get("entries")
    if not isinstance(nested, list) or not nested:
        nested = [{}]
    first = dict(nested[0]) if isinstance(nested[0], dict) else {}
    first.update(
        {
            "source": library_dictionary_source(lang),
            "lemma": lemma,
            "part_of_speech": pos,
            "translations": translations,
            "translation_variants": record.get("variants") or [],
            "mt_generated": False,
        }
    )
    entry["entries"] = [first]
    return entry


def _refresh_language(
    output_dir: Path,
    *,
    lang: str,
    reader: dict,
    words: dict,
    blocks: dict,
    function_words: dict | None = None,
    absorbed_word_keys: set[str] | None = None,
) -> dict:
    function_words = function_words or {}
    absorbed_word_keys = {
        _canonical_dictionary_key(item) for item in (absorbed_word_keys or set())
    }
    dictionary_path = output_dir / f"dictionary_{lang}.json"
    existing_dictionary = _load(dictionary_path) if dictionary_path.exists() else {}
    existing_entries = existing_dictionary.get("entries") or {}
    reader_words: list[dict] = []
    reader_keys: set[str] = set()
    segments = _segments(reader)
    for paragraph in reader.get("paragraphs") or []:
        if not isinstance(paragraph, dict):
            continue
        for word in paragraph.get("words") or []:
            if not isinstance(word, dict):
                continue
            lemma = str(word.get("lemma") or word.get("text") or "").strip().lower()
            pos = str(word.get("pos") or "").strip().upper()
            if not lemma:
                continue
            reader_words.append(word)
            reader_keys.add(f"{lemma}|{pos}")
    entries = {
        key: _manifest_entry(
            key,
            {} if key in absorbed_word_keys else words[key],
            lang,
            existing_entries.get(key) if isinstance(existing_entries, dict) else None,
        )
        for key in sorted(reader_keys)
        if key in words or key in absorbed_word_keys
    }
    dictionary = {
        "book_id": reader.get("book_id") or existing_dictionary.get("book_id") or "",
        "target_lang": lang,
        "source": library_dictionary_source(lang),
        "entry_count": len(entries),
        "entries": entries,
        "block_count": len(blocks),
        "blocks": blocks,
    }

    words_by_segment: dict[str, list[dict]] = {}
    for word in reader_words:
        words_by_segment.setdefault(str(word.get("segment_id") or ""), []).append(word)
    word_entries = []
    for segment_id, segment_words in words_by_segment.items():
        ordered_words = sorted(
            segment_words,
            key=lambda item: int(item.get("order_index_in_segment") or 0),
        )
        segment = segments.get(segment_id) or {}
        target_text = str(segment.get("target_text") or "")
        claimed_spans: set[int] = set()
        for source_index, word in enumerate(ordered_words):
            lemma = str(word.get("lemma") or word.get("text") or "").strip().lower()
            pos = str(word.get("pos") or "").strip().upper()
            key = f"{lemma}|{pos}"
            record = {} if key in absorbed_word_keys else words.get(key) or {}
            translations = [str(value) for value in record.get("translations") or []]
            selected, target_start, target_end = _select_translation(
                translations,
                target_text,
                source_index=source_index,
                source_count=len(ordered_words),
                claimed_spans=claimed_spans,
            )
            if target_start >= 0:
                claimed_spans.update(range(target_start, target_end + 1))
            word_entries.append(
                {
                    "word_id": str(word.get("id") or ""),
                    "segment_id": segment_id,
                    "surface": str(word.get("text") or ""),
                    "lemma": str(word.get("lemma") or ""),
                    "pos": str(word.get("pos") or ""),
                    "translation": selected,
                    "translations": translations,
                    "dictionary_key": key,
                    "target_start_index": target_start,
                    "target_end_index": target_end,
                    "source": library_dictionary_source(lang),
                    "note": "" if selected else "no_contextual_target_match",
                }
            )
    block_entries = []
    for segment_id, segment in segments.items():
        source_text = str(segment.get("source_text") or "")
        target_text = str(segment.get("target_text") or "")
        for block, record in blocks.items():
            if not _block_in_source(block, source_text):
                continue
            translations = [str(value) for value in record.get("translations") or []]
            selected, _, _ = _select_translation(translations, target_text)
            if not selected:
                continue
            block_entries.append(
                {
                    "segment_id": segment_id,
                    "source": block,
                    "translation": selected,
                    "translations": translations,
                    "dictionary_key": block,
                    "alignment_kind": "block",
                    "components": record.get("components") or [],
                    "block_type": str(record.get("type") or ""),
                    "explanation": str(record.get("explanation") or ""),
                }
            )
    word_to_word = {
        "version": 2,
        "book_id": reader.get("book_id") or "",
        "source_lang": "en",
        "target_lang": lang,
        "source": library_dictionary_source(lang),
        "entries": word_entries,
        "blocks": block_entries,
    }
    word_alignments = []
    for item in word_entries:
        next_item = dict(item)
        next_item.pop("translations", None)
        word_alignments.append(next_item)
    block_alignments = []
    for item in block_entries:
        next_item = dict(item)
        next_item["block_key"] = str(
            next_item.pop("dictionary_key", None) or next_item.get("source") or ""
        )
        next_item.pop("translations", None)
        next_item.pop("components", None)
        block_alignments.append(next_item)
    used_block_keys = {
        str(item.get("block_key") or "") for item in block_alignments
    }
    book_blocks = {
        key: value for key, value in blocks.items() if key in used_block_keys
    }
    book_function_words: dict[str, dict] = {}
    for word in reader_words:
        surface = str(word.get("text") or "").strip().lower()
        lemma = str(word.get("lemma") or surface).strip().lower()
        pos = str(word.get("pos") or "").strip().upper()
        actual_key = f"{surface}|{pos}"
        candidates = (actual_key, f"{lemma}|{pos}")
        matched_key = next((key for key in candidates if key in function_words), "")
        if not matched_key:
            matched_key = next(
                (
                    key
                    for key, value in function_words.items()
                    if actual_key in (value.get("match_keys") or [])
                ),
                "",
            )
        if matched_key:
            record = dict(function_words[matched_key])
            record.pop("match_keys", None)
            record["source_key"] = matched_key
            book_function_words[actual_key] = record
    return {
        "version": 3,
        "book_id": word_to_word["book_id"],
        "source_lang": "en",
        "target_lang": lang,
        "source": library_dictionary_source(lang),
        "words": entries,
        "blocks": book_blocks,
        "function_words": book_function_words,
        "word_alignments": word_alignments,
        "block_alignments": block_alignments,
    }


def _rebuild_zip(output_dir: Path, zip_path: Path) -> None:
    temporary = zip_path.with_suffix(".zip.tmp")
    with zipfile.ZipFile(temporary, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(output_dir.rglob("*")):
            if path.is_file():
                archive.write(path, path.relative_to(output_dir).as_posix())
    with zipfile.ZipFile(temporary) as archive:
        if archive.testzip() is not None:
            raise ValueError(f"Broken zip: {zip_path}")
        names = set(archive.namelist())
        if "load_manifest.json" not in names:
            raise ValueError(f"Missing load_manifest.json: {zip_path}")
    os.replace(temporary, zip_path)


def refresh(root: Path, *, write: bool, rebuild_zips: bool) -> dict:
    store = LibraryDictionaryStore(root / "Studio" / "Backend")
    output_root = root / "Studio" / "Runtime" / "workbench_output" / "a1" / "chapters"
    cloud_root = root / "Studio" / "CloudLibrary" / "a1" / "chapters" / "books_zip"
    mobile_root = root / "production_mobile" / "assets" / "library" / "a1" / "chapters" / "books_zip"
    globals_by_lang = {
        lang: (
            _load(store.global_words_path_for(lang)),
            _load(store.global_blocks_path_for(lang)),
            _load(store.global_function_words_path_for(lang))
            if store.global_function_words_path_for(lang).exists()
            else {},
        )
        for lang in ("ru", "uk")
    }
    layers_by_title = {
        lang: {
            str(payload.get("title") or "").strip(): payload
            for path in store.books_dir(lang).glob(f"*/book_layer_{lang}.json")
            for payload in [_load(path)]
        }
        for lang in ("ru", "uk")
    }
    layer_titles = {lang: set(items) for lang, items in layers_by_title.items()}
    updated = []
    zip_count = 0
    for output_dir in sorted(path for path in output_root.iterdir() if path.is_dir()):
        manifest_path = output_dir / "load_manifest.json"
        if not manifest_path.exists():
            continue
        manifest = _load(manifest_path)
        title = str(manifest.get("title") or "").strip()
        changed_langs = []
        for lang in ("ru", "uk"):
            reader_path = output_dir / f"reader_{lang}.json"
            if title not in layer_titles[lang] or not reader_path.exists():
                continue
            reader = _load(reader_path)
            audit = layers_by_title[lang][title].get("book_layer_audit") or {}
            absorbed_word_keys = {
                _canonical_dictionary_key(item)
                for item in audit.get("absorbed_word_keys") or []
                if str(item).strip()
            }
            lexicon = _refresh_language(
                output_dir,
                lang=lang,
                reader=reader,
                words=globals_by_lang[lang][0],
                blocks=globals_by_lang[lang][1],
                function_words=globals_by_lang[lang][2],
                absorbed_word_keys=absorbed_word_keys,
            )
            changed_langs.append(lang)
            if write:
                _write(output_dir / f"reader_lexicon_{lang}.json", lexicon)
                (output_dir / f"dictionary_{lang}.json").unlink(missing_ok=True)
                (output_dir / f"word_to_word_{lang}.json").unlink(missing_ok=True)
        if not changed_langs:
            continue
        if write:
            (output_dir / "word_to_word.json").unlink(missing_ok=True)
            _write(
                manifest_path,
                _manifest_with_reader_lexicons(manifest, changed_langs),
            )
        updated.append({"title": title, "languages": changed_langs})
        if write and rebuild_zips:
            zip_path = output_root / f"{output_dir.name}.zip"
            _rebuild_zip(output_dir, zip_path)
            for destination_root in (cloud_root, mobile_root):
                destination = destination_root / zip_path.name
                if destination.exists():
                    shutil.copyfile(zip_path, destination)
            zip_count += 1
    processed_titles = {item["title"] for item in updated}
    wanted_titles = layer_titles["ru"] | layer_titles["uk"]
    for zip_path in sorted(output_root.glob("*.zip")):
        with zipfile.ZipFile(zip_path) as archive:
            if "load_manifest.json" not in archive.namelist():
                continue
            manifest = json.loads(archive.read("load_manifest.json").decode("utf-8"))
            title = str(manifest.get("title") or "").strip()
            if title in processed_titles or title not in wanted_titles:
                continue
            names = set(archive.namelist())
            changed_langs = [
                lang
                for lang in ("ru", "uk")
                if title in layer_titles[lang] and f"reader_{lang}.json" in names
            ]
            if not changed_langs:
                continue
            if write:
                with tempfile.TemporaryDirectory(prefix="lexo_package_refresh_") as temp_dir:
                    package_dir = Path(temp_dir)
                    archive.extractall(package_dir)
                    archive.close()
                    for lang in changed_langs:
                        reader = _load(package_dir / f"reader_{lang}.json")
                        audit = layers_by_title[lang][title].get("book_layer_audit") or {}
                        absorbed_word_keys = {
                            _canonical_dictionary_key(item)
                            for item in audit.get("absorbed_word_keys") or []
                            if str(item).strip()
                        }
                        lexicon = _refresh_language(
                            package_dir,
                            lang=lang,
                            reader=reader,
                            words=globals_by_lang[lang][0],
                            blocks=globals_by_lang[lang][1],
                            function_words=globals_by_lang[lang][2],
                            absorbed_word_keys=absorbed_word_keys,
                        )
                        _write(package_dir / f"reader_lexicon_{lang}.json", lexicon)
                        (package_dir / f"dictionary_{lang}.json").unlink(missing_ok=True)
                        (package_dir / f"word_to_word_{lang}.json").unlink(missing_ok=True)
                    (package_dir / "word_to_word.json").unlink(missing_ok=True)
                    package_manifest_path = package_dir / "load_manifest.json"
                    package_manifest = _load(package_manifest_path)
                    _write(
                        package_manifest_path,
                        _manifest_with_reader_lexicons(
                            package_manifest, changed_langs
                        ),
                    )
                    if rebuild_zips:
                        _rebuild_zip(package_dir, zip_path)
                        for destination_root in (cloud_root, mobile_root):
                            destination = destination_root / zip_path.name
                            if destination.exists():
                                shutil.copyfile(zip_path, destination)
                        zip_count += 1
            updated.append({"title": title, "languages": changed_langs})
            processed_titles.add(title)
    return {"books": len(updated), "zips": zip_count, "updated": updated}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--write", action="store_true")
    parser.add_argument("--rebuild-zips", action="store_true")
    args = parser.parse_args()
    result = refresh(args.root.resolve(), write=args.write, rebuild_zips=args.rebuild_zips)
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
