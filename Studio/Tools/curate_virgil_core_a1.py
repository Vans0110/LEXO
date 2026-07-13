from __future__ import annotations

import argparse
import hashlib
import json
import sys
import tempfile
import zipfile
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CORE = (
    ROOT / "Backend" / "data" / "dictionaries" / "virgil_core" / "virgil_core_dictionary.json"
)
DEFAULT_OUTPUT_ROOT = ROOT / "Runtime" / "workbench_output" / "a1" / "chapters"
DEFAULT_CLOUD_ROOT = ROOT / "CloudLibrary"

BACKEND_ROOT = ROOT / "Backend"
sys.path.insert(0, str(BACKEND_ROOT))

from engine.virgil_core_dictionary import (  # noqa: E402
    TITLE_PROPN_ALIASES,
    VirgilCoreDictionary,
)


# Virgil Core is a compact learning dictionary, not a catalogue of every
# historical, slang, technical, or domain-specific meaning of a word.
OVERRIDES: dict[str, dict[str, list[str]]] = {
    "age|NOUN": {"ru": ["возраст"], "uk": ["вік"]},
    "answer|VERB": {"ru": ["отвечать", "ответить"], "uk": ["відповідати", "відповісти"]},
    "appear|VERB": {"ru": ["появляться", "казаться"], "uk": ["з'являтися", "здаватися"]},
    "arrive|VERB": {"ru": ["приезжать", "прибывать"], "uk": ["приїжджати", "прибувати"]},
    "ask|VERB": {"ru": ["спрашивать", "спросить", "просить"], "uk": ["питати", "запитати", "просити"]},
    "basic|ADJ": {"ru": ["основной", "базовый", "элементарный"], "uk": ["основний", "базовий", "елементарний"]},
    "be|AUX": {"ru": ["быть"], "uk": ["бути"]},
    "be|VERB": {"ru": ["быть", "находиться"], "uk": ["бути", "знаходитися"]},
    "birthday|NOUN": {"ru": ["день рождения"], "uk": ["день народження"]},
    "book|NOUN": {"ru": ["книга"], "uk": ["книга"]},
    "bread|NOUN": {"ru": ["хлеб"], "uk": ["хліб"]},
    "brother|NOUN": {"ru": ["брат"], "uk": ["брат"]},
    "building|NOUN": {"ru": ["здание"], "uk": ["будівля"]},
    "bus|NOUN": {"ru": ["автобус"], "uk": ["автобус"]},
    "but|CCONJ": {"ru": ["но", "а"], "uk": ["але", "а"]},
    "card|NOUN": {"ru": ["карточка", "карта"], "uk": ["картка", "карта"]},
    "chicken|NOUN": {"ru": ["курица", "курятина"], "uk": ["курка", "курятина"]},
    "child|NOUN": {"ru": ["ребёнок"], "uk": ["дитина"]},
    "classroom|NOUN": {"ru": ["класс", "классная комната"], "uk": ["клас", "класна кімната"]},
    "correct|ADJ": {"ru": ["правильный", "верный"], "uk": ["правильний", "вірний"]},
    "country|NOUN": {"ru": ["страна", "государство"], "uk": ["країна", "держава"]},
    "course|NOUN": {"ru": ["курс"], "uk": ["курс"]},
    "digit|NOUN": {"ru": ["цифра"], "uk": ["цифра"]},
    "dinner|NOUN": {"ru": ["ужин", "обед"], "uk": ["вечеря", "обід"]},
    "entrance|NOUN": {"ru": ["вход"], "uk": ["вхід"]},
    "evening|NOUN": {"ru": ["вечер"], "uk": ["вечір"]},
    "face|NOUN": {"ru": ["лицо", "выражение лица"], "uk": ["обличчя", "вираз обличчя"]},
    "family|NOUN": {"ru": ["семья"], "uk": ["сім'я", "родина"]},
    "friend|NOUN": {"ru": ["друг", "подруга"], "uk": ["друг", "подруга"]},
    "girl|NOUN": {"ru": ["девочка", "девушка"], "uk": ["дівчинка", "дівчина"]},
    "good|ADJ": {"ru": ["хороший", "добрый"], "uk": ["хороший", "добрий"]},
    "great|ADJ": {"ru": ["отличный", "замечательный"], "uk": ["чудовий", "відмінний"]},
    "holiday|NOUN": {"ru": ["праздник", "отпуск", "каникулы"], "uk": ["свято", "відпустка", "канікули"]},
    "i|PRON": {"ru": ["я"], "uk": ["я"]},
    "information|NOUN": {"ru": ["информация", "сведения"], "uk": ["інформація", "відомості"]},
    "into|ADP": {"ru": ["в", "внутрь"], "uk": ["у", "в", "до"]},
    "it|PRON": {"ru": ["оно", "это"], "uk": ["воно", "це"]},
    "job|NOUN": {"ru": ["работа", "должность"], "uk": ["робота", "посада"]},
    "juice|NOUN": {"ru": ["сок"], "uk": ["сік"]},
    "kind|ADJ": {"ru": ["добрый"], "uk": ["добрий"]},
    "language|NOUN": {"ru": ["язык"], "uk": ["мова"]},
    "late|ADJ": {"ru": ["поздний", "опоздавший"], "uk": ["пізній", "запізнілий"]},
    "laugh|NOUN": {"ru": ["смех"], "uk": ["сміх"]},
    "live|VERB": {"ru": ["жить", "проживать"], "uk": ["жити", "мешкати"]},
    "lunch|NOUN": {"ru": ["обед"], "uk": ["обід"]},
    "man|NOUN": {"ru": ["мужчина", "человек"], "uk": ["чоловік", "людина"]},
    "map|NOUN": {"ru": ["карта"], "uk": ["карта", "мапа"]},
    "meet|VERB": {"ru": ["встречать", "встречаться", "знакомиться"], "uk": ["зустрічати", "зустрічатися", "знайомитися"]},
    "morning|NOUN": {"ru": ["утро"], "uk": ["ранок"]},
    "mother|NOUN": {"ru": ["мать", "мама"], "uk": ["мати", "мама"]},
    "name|NOUN": {"ru": ["имя", "название"], "uk": ["ім'я", "назва"]},
    "new|ADJ": {"ru": ["новый"], "uk": ["новий"]},
    "night|NOUN": {"ru": ["ночь"], "uk": ["ніч"]},
    "now|ADV": {"ru": ["сейчас", "теперь"], "uk": ["зараз", "тепер"]},
    "nurse|NOUN": {"ru": ["медсестра", "медбрат"], "uk": ["медсестра", "медбрат"]},
    "old|ADJ": {"ru": ["старый", "пожилой"], "uk": ["старий", "літній"]},
    "please|INTJ": {"ru": ["пожалуйста"], "uk": ["будь ласка"]},
    "real|ADJ": {"ru": ["настоящий", "реальный"], "uk": ["справжній", "реальний"]},
    "rice|NOUN": {"ru": ["рис"], "uk": ["рис"]},
    "room|NOUN": {"ru": ["комната"], "uk": ["кімната"]},
    "school|NOUN": {"ru": ["школа"], "uk": ["школа"]},
    "spain|PROPN": {"ru": ["Испания"], "uk": ["Іспанія"]},
    "spanish|PROPN": {"ru": ["испанский язык"], "uk": ["іспанська мова"]},
    "stranger|NOUN": {"ru": ["незнакомец", "незнакомка"], "uk": ["незнайомець", "незнайомка"]},
    "teacher|NOUN": {"ru": ["учитель", "учительница"], "uk": ["учитель", "учителька"]},
    "tell|VERB": {"ru": ["говорить", "сказать", "рассказывать"], "uk": ["говорити", "сказати", "розповідати"]},
    "there|PRON": {"ru": ["есть", "имеется"], "uk": ["є", "існує"]},
    "time|NOUN": {"ru": ["время", "раз"], "uk": ["час", "раз"]},
    "to|ADP": {"ru": ["к", "в", "на", "до"], "uk": ["до", "у", "в", "на"]},
    "two|NUM": {"ru": ["два", "две"], "uk": ["два", "дві"]},
    "upstairs|ADV": {"ru": ["наверху", "наверх", "на верхнем этаже"], "uk": ["нагорі", "нагору", "на верхньому поверсі"]},
    "very|ADV": {"ru": ["очень"], "uk": ["дуже"]},
    "welcome|INTJ": {"ru": ["добро пожаловать"], "uk": ["ласкаво просимо"]},
    "wrong|ADJ": {"ru": ["неправильный", "неверный"], "uk": ["неправильний", "невірний"]},
    "young|ADJ": {"ru": ["молодой", "юный"], "uk": ["молодий", "юний"]},
    "hill|PROPN": {"ru": ["Хилл"], "uk": ["Гілл"]},
    "kate|PROPN": {"ru": ["Кейт"], "uk": ["Кейт"]},
    "lee|PROPN": {"ru": ["Ли"], "uk": ["Лі"]},
    "leo|PROPN": {"ru": ["Лео"], "uk": ["Лео"]},
    "maple|PROPN": {"ru": ["Мейпл"], "uk": ["Мейпл"]},
    "mina|PROPN": {"ru": ["Мина"], "uk": ["Міна"]},
    "nora|PROPN": {"ru": ["Нора"], "uk": ["Нора"]},
    "ortiz|PROPN": {"ru": ["Ортис"], "uk": ["Ортіс"]},
    "pine|PROPN": {"ru": ["Пайн"], "uk": ["Пайн"]},
    "sara|PROPN": {"ru": ["Сара"], "uk": ["Сара"]},
    "westbridge|PROPN": {"ru": ["Уэстбридж"], "uk": ["Вестбридж"]},
    "yuki|PROPN": {"ru": ["Юки"], "uk": ["Юкі"]},
}


# Exact keys requested by current book manifests. They intentionally preserve
# the package lemma/POS contract instead of rewriting it to another article.
ADDITIONS: dict[str, dict[str, list[str]]] = {
    "bag|PROPN": {"ru": ["сумка"], "uk": ["сумка"]},
    "bakery|PROPN": {"ru": ["пекарня"], "uk": ["пекарня"]},
    "bin|PROPN": {"ru": ["мусорное ведро"], "uk": ["смітник"]},
    "bread|PROPN": {"ru": ["хлеб"], "uk": ["хліб"]},
    "cafe|PROPN": {"ru": ["кафе"], "uk": ["кафе"]},
    "chicken|VERB": {"ru": ["курица", "курятина"], "uk": ["курка", "курятина"]},
    "clean|ADJ": {"ru": ["уборщик", "уборщица"], "uk": ["прибиральник", "прибиральниця"]},
    "clothe|NOUN": {"ru": ["одежда"], "uk": ["одяг"]},
    "cooking|PROPN": {"ru": ["готовка"], "uk": ["готування"]},
    "corner|PROPN": {"ru": ["угол"], "uk": ["кут"]},
    "cup|PROPN": {"ru": ["чашка"], "uk": ["чашка"]},
    "david|PROPN": {"ru": ["Дэвид"], "uk": ["Девід"]},
    "don't|AUX": {"ru": ["не"], "uk": ["не"]},
    "family|PROPN": {"ru": ["семья"], "uk": ["сім'я", "родина"]},
    "five-dollar|NUM": {"ru": ["пятидолларовый"], "uk": ["п’ятидоларовий"]},
    "flat|PROPN": {"ru": ["квартира"], "uk": ["квартира"]},
    "fork|VERB": {"ru": ["вилка"], "uk": ["виделка"]},
    "keys|PROPN": {"ru": ["ключи"], "uk": ["ключі"]},
    "kind|NOUN": {"ru": ["добрый"], "uk": ["добрий"]},
    "knock|NOUN": {"ru": ["стучать", "постучать"], "uk": ["стукати", "постукати"]},
    "library|PROPN": {"ru": ["библиотека"], "uk": ["бібліотека"]},
    "living|NOUN": {"ru": ["гостиная"], "uk": ["вітальня"]},
    "mine|NOUN": {"ru": ["мой", "моя", "моё", "мои"], "uk": ["мій", "моя", "моє", "мої"]},
    "new|PROPN": {"ru": ["новый"], "uk": ["новий"]},
    "night|PROPN": {"ru": ["ночь"], "uk": ["ніч"]},
    "north|PROPN": {"ru": ["северный"], "uk": ["північний"]},
    "oats|PROPN": {"ru": ["овсянка", "овсяные хлопья"], "uk": ["вівсянка", "вівсяні пластівці"]},
    "one|NOUN": {"ru": ["один", "тот"], "uk": ["один", "той"]},
    "oven|PROPN": {"ru": ["духовка"], "uk": ["духовка"]},
    "pan|ADJ": {"ru": ["сковорода"], "uk": ["сковорода"]},
    "photo|PROPN": {"ru": ["фото", "фотография"], "uk": ["фото", "фотографія"]},
    "picnic|PROPN": {"ru": ["пикник"], "uk": ["пікнік"]},
    "plant|PROPN": {"ru": ["растение"], "uk": ["рослина"]},
    "problem|PROPN": {"ru": ["проблема"], "uk": ["проблема"]},
    "quiet|PROPN": {"ru": ["тихий", "спокойный"], "uk": ["тихий", "спокійний"]},
    "sofia|NOUN": {"ru": ["София"], "uk": ["Софія"]},
    "soup|PROPN": {"ru": ["суп"], "uk": ["суп"]},
    "tall|PROPN": {"ru": ["высокий"], "uk": ["високий"]},
    "teacher|PROPN": {"ru": ["учитель", "учительница"], "uk": ["учитель", "учителька"]},
    "twelve|ADJ": {"ru": ["двенадцать"], "uk": ["дванадцять"]},
    "university|PROPN": {"ru": ["университет"], "uk": ["університет"]},
    "upstairs|PROPN": {"ru": ["наверху", "на верхнем этаже"], "uk": ["нагорі", "на верхньому поверсі"]},
    "wave|NOUN": {"ru": ["махать"], "uk": ["махати"]},
    "wrong|PROPN": {"ru": ["неправильный", "неверный"], "uk": ["неправильний", "невірний"]},
    "your|NOUN": {"ru": ["твой", "ваш"], "uk": ["твій", "ваш"]},
}


def curate(core_path: Path, *, check: bool) -> tuple[int, int]:
    payload = json.loads(core_path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError("Core dictionary must be a JSON object")

    created = 0
    for key, translations in ADDITIONS.items():
        word, pos = key.rsplit("|", 1)
        if key not in payload:
            payload[key] = {
                "pos": pos,
                "translations": translations,
                "word": word,
            }
            created += 1
        elif payload[key].get("translations") != translations:
            payload[key]["translations"] = translations
            created += 1

    for source_key, target_key in TITLE_PROPN_ALIASES.items():
        if target_key in payload or source_key not in payload:
            continue
        target_word, target_pos = target_key.rsplit("|", 1)
        payload[target_key] = {
            **payload[source_key],
            "word": target_word,
            "pos": target_pos,
        }
        created += 1

    missing = sorted(set(OVERRIDES) - set(payload))
    missing_alias_targets = sorted(set(TITLE_PROPN_ALIASES.values()) - set(payload))
    if missing or missing_alias_targets:
        raise KeyError(
            f"Missing override keys={missing}; alias targets={missing_alias_targets}"
        )

    changed = created
    for key, translations in OVERRIDES.items():
        if payload[key].get("translations") != translations:
            payload[key]["translations"] = translations
            changed += 1

    removed = 0
    for key in TITLE_PROPN_ALIASES:
        if key in payload:
            del payload[key]
            removed += 1

    if not check and (changed or removed):
        rendered = json.dumps(payload, ensure_ascii=False, indent=2) + "\n"
        core_path.write_text(rendered, encoding="utf-8", newline="\r\n")
    return changed, removed


def refresh_manifest(path: Path, dictionary: VirgilCoreDictionary) -> int:
    payload = json.loads(path.read_text(encoding="utf-8"))
    lang = str(payload.get("target_lang") or path.stem.removeprefix("dictionary_"))
    entries = payload.get("entries")
    if not isinstance(entries, dict):
        raise ValueError(f"Invalid dictionary entries: {path}")

    changed = 0
    refreshed: dict[str, dict] = {}
    for dictionary_key, old_entry in entries.items():
        if dictionary_key == "s|":
            changed += 1
            continue
        entry = dictionary.lookup(
            surface=str(old_entry.get("query") or old_entry.get("lemma") or ""),
            lemma=str(old_entry.get("lemma") or ""),
            pos=str(old_entry.get("part_of_speech") or ""),
            target_lang=lang,
            source_segment=str(old_entry.get("source_segment") or ""),
            target_segment=str(old_entry.get("target_segment") or ""),
        )
        refreshed[dictionary_key] = entry
        if entry != old_entry:
            changed += 1
    payload["entries"] = refreshed
    payload["entry_count"] = len(refreshed)
    if changed:
        path.write_text(
            json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
            newline="\n",
        )
    return changed


def refresh_outputs(output_root: Path, dictionary: VirgilCoreDictionary) -> tuple[int, int]:
    manifests = 0
    entries = 0
    for path in sorted(output_root.glob("*/dictionary_*.json")):
        changed = refresh_manifest(path, dictionary)
        if changed:
            manifests += 1
            entries += changed
    return manifests, entries


def replace_zip_manifests(zip_path: Path, source_dir: Path) -> bool:
    replacements = {
        name: (source_dir / name).read_bytes()
        for name in ("dictionary_ru.json", "dictionary_uk.json")
        if (source_dir / name).exists()
    }
    if not replacements:
        return False

    temp_path: Path | None = None
    try:
        with zipfile.ZipFile(zip_path, "r") as source:
            current = {
                name: source.read(name)
                for name in replacements
                if name in source.namelist()
            }
            if current == replacements:
                return False
            with tempfile.NamedTemporaryFile(
                dir=zip_path.parent, suffix=".zip", delete=False
            ) as handle:
                temp_path = Path(handle.name)
            with zipfile.ZipFile(temp_path, "w") as target:
                for item in source.infolist():
                    data = replacements.get(item.filename, source.read(item.filename))
                    target.writestr(item, data)
        assert temp_path is not None
        temp_path.replace(zip_path)
        return True
    finally:
        if temp_path is not None and temp_path.exists():
            temp_path.unlink()


def refresh_cloud_packages(cloud_root: Path, output_root: Path) -> int:
    index_path = cloud_root / "library_index.json"
    payload = json.loads(index_path.read_text(encoding="utf-8"))
    changed = 0
    timestamp = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
    for book in payload.get("books", []):
        zip_path = cloud_root / str(book.get("zip_path") or "")
        source_dir = next(output_root.glob(f"{zip_path.stem}"), None)
        if source_dir is None or not zip_path.exists():
            continue
        if not replace_zip_manifests(zip_path, source_dir):
            continue
        data = zip_path.read_bytes()
        book["content_hash"] = hashlib.sha256(data).hexdigest()
        book["size_bytes"] = len(data)
        book["updated_at"] = timestamp
        changed += 1
    if changed:
        payload["updated_at"] = timestamp
        index_path.write_text(
            json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
            newline="\n",
        )
    return changed


def main() -> None:
    parser = argparse.ArgumentParser(description="Apply reviewed A1 Core corrections.")
    parser.add_argument("--core", type=Path, default=DEFAULT_CORE)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--refresh-outputs", action="store_true")
    parser.add_argument("--refresh-cloud-packages", action="store_true")
    args = parser.parse_args()
    changed, removed = curate(args.core, check=args.check)
    print(f"changed={changed} removed_title_propn={removed} check={args.check}")
    if args.check:
        return
    dictionary = VirgilCoreDictionary(BACKEND_ROOT)
    if args.refresh_outputs or args.refresh_cloud_packages:
        manifests, entries = refresh_outputs(DEFAULT_OUTPUT_ROOT, dictionary)
        print(f"refreshed_manifests={manifests} refreshed_entries={entries}")
    if args.refresh_cloud_packages:
        packages = refresh_cloud_packages(
            DEFAULT_CLOUD_ROOT, DEFAULT_OUTPUT_ROOT
        )
        print(f"refreshed_cloud_packages={packages}")


if __name__ == "__main__":
    main()
