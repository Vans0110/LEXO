from __future__ import annotations

import argparse
import copy
import json
import sys
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BACKEND_ROOT = ROOT / "Backend"
CORE_PATH = BACKEND_ROOT / "data" / "dictionaries" / "virgil_core" / "virgil_core_dictionary.json"
OUTPUT_ROOT = ROOT / "Runtime" / "workbench_output" / "a1" / "chapters"
ZIP_ROOT = ROOT / "CloudLibrary" / "a1" / "chapters" / "books_zip"

sys.path.insert(0, str(BACKEND_ROOT))

from engine.virgil_core_dictionary import VirgilCoreDictionary  # noqa: E402


RAW_ADDITIONS = """
addition|NOUN	добавление;сложение	додавання
advice|NOUN	совет	порада
amount|NOUN	сумма;количество	сума;кількість
ankle|NOUN	лодыжка;щиколотка	щиколотка;кісточка
anywhere|ADV	где угодно;куда угодно	де завгодно;куди завгодно
back|NOUN	спина;задняя часть	спина;задня частина
bandage|NOUN	бинт;повязка	бинт;пов'язка
bench|NOUN	скамейка	лавка
bill|PROPN	счёт	рахунок
blanket|NOUN	одеяло	ковдра
block|VERB	блокировать;закрывать	блокувати;закривати
body|NOUN	тело	тіло
budget|NOUN	бюджет	бюджет
caring|ADJ	заботливый	турботливий
case|NOUN	случай;дело	випадок;справа
catch|VERB	ловить;подхватить	ловити;підхопити
choice|NOUN	выбор	вибір
chris|PROPN	Крис	Кріс
clear|ADJ	ясный;понятный	ясний;зрозумілий
clinic|NOUN	клиника	клініка
cold|NOUN	простуда;холод	застуда;холод
cold|PROPN	простуда;холод	застуда;холод
compare|VERB	сравнивать	порівнювати
cough|NOUN	кашель	кашель
describe|VERB	описывать	описувати
dizzy|ADJ	с головокружением	запаморочений
dose|NOUN	доза	доза
dozen|NOUN	дюжина	дюжина
dr|PROPN	доктор	доктор
ear|NOUN	ухо	вухо
electricity|NOUN	электричество	електрика
energy|NOUN	энергия	енергія
equal|ADJ	равный	рівний
equally|ADV	поровну;одинаково	порівну;однаково
eva|NOUN	Ева	Єва
examine|VERB	осматривать;проверять	оглядати;перевіряти
explain|VERB	объяснять	пояснювати
few|ADJ	несколько;мало	кілька;мало
fifty-dollar|NUM	пятьдесят долларов	п'ятдесят доларів
fill|VERB	заполнять;наполнять	заповнювати;наповнювати
fine|ADJ	хороший;нормальный	добрий;нормальний
finger|NOUN	палец	палець
four-dollar|NUM	четыре доллара	чотири долари
four-hundred-metre|NUM	четыреста метров	чотириста метрів
fund|NOUN	фонд;накопление	фонд;накопичення
fund|PROPN	фонд;накопление	фонд;накопичення
goal|NOUN	цель	мета
head|NOUN	голова	голова
headache|NOUN	головная боль	головний біль
headache|PROPN	головная боль	головний біль
health|NOUN	здоровье	здоров'я
herself|PRON	сама;себя	сама;себе
hold|VERB	держать	тримати
honest|ADJ	честный	чесний
hurt|NOUN	боль	біль
include|VERB	включать	включати
instruction|NOUN	инструкция	інструкція
jon|PROPN	Джон	Джон
kind|PROPN	добрый	добрий
land|NOUN	земля;поверхность	земля;поверхня
leg|NOUN	нога	нога
less|ADJ	меньше;меньший	менше;менший
level|NOUN	уровень	рівень
lost|PROPN	потерянный	загублений
main|ADJ	главный;основной	головний;основний
manager|NOUN	менеджер	менеджер
medicine|NOUN	лекарство	ліки
mila|PROPN	Мила	Міла
moment|NOUN	момент	момент
money|NOUN	деньги	гроші
most|ADV	больше всего;самый	найбільше;найбільш
mouth|NOUN	рот	рот
nearby|ADJ	ближайший;рядом	найближчий;поруч
neck|NOUN	шея	шия
nobody|PRON	никто	ніхто
normal|ADJ	нормальный	нормальний
nose|NOUN	нос	ніс
outside|ADP	снаружи;за пределами	зовні;за межами
owen|PROPN	Оуэн	Овен
owner|NOUN	владелец	власник
pain|NOUN	боль	біль
past|ADP	мимо;после	повз;після
patient|NOUN	пациент	пацієнт
pharmacy|NOUN	аптека	аптека
phone|PROPN	телефон	телефон
pillow|NOUN	подушка	подушка
plus|CCONJ	плюс	плюс
potato|NOUN	картофель;картошка	картопля
power|NOUN	электроэнергия;сила	електроенергія;сила
quality|NOUN	качество	якість
race|NOUN	забег;гонка	забіг;перегони
race|VERB	бежать наперегонки;соревноваться	бігти наввипередки;змагатися
record|VERB	записывать;фиксировать	записувати;фіксувати
runner|NOUN	бегун	бігун
running|NOUN	бег	біг
sad|ADJ	грустный	сумний
sale|NOUN	продажа;распродажа	продаж;розпродаж
sara|ADV	Сара	Сара
save|VERB	копить;сохранять	заощаджувати;зберігати
saving|NOUN	сбережение;экономия	заощадження;економія
saving|PROPN	сбережение;экономия	заощадження;економія
shah|PROPN	Шах	Шах
share|NOUN	доля;часть	частка;частина
sick|ADJ	больной	хворий
sick|PROPN	больной	хворий
sixty-five|NUM	шестьдесят пять	шістдесят п'ять
sleep|NOUN	сон	сон
sore|ADJ	больной;воспалённый	болючий;запалений
sports|PROPN	спорт	спорт
step|NOUN	шаг	крок
stomach|NOUN	живот;желудок	живіт;шлунок
stone|NOUN	камень	камінь
strawberry|NOUN	клубника	полуниця
stretch|VERB	растягивать;потянуться	розтягувати;потягнутися
symptom|NOUN	симптом	симптом
tablet|NOUN	таблетка	таблетка
than|ADP	чем	ніж
thank|NOUN	благодарность;спасибо	подяка;дякую
thirty-eight|NUM	тридцать восемь	тридцять вісім
thirty-seven|NUM	тридцать семь	тридцять сім
thirty-two|NUM	тридцать два	тридцять два
throat|NOUN	горло	горло
tip|NOUN	чаевые;подсказка	чайові;порада
toe|NOUN	палец ноги	палець ноги
tooth|NOUN	зуб	зуб
total|NOUN	итог;сумма	підсумок;сума
twenty-dollar|NUM	двадцать долларов	двадцять доларів
twice|ADV	дважды;два раза	двічі;два рази
valuable|ADJ	ценный	цінний
waiting|NOUN	ожидание	очікування
wallet|NOUN	кошелёк	гаманець
wallet|PROPN	кошелёк	гаманець
weigh|VERB	взвешивать	зважувати
worry|VERB	беспокоиться	хвилюватися
zipped|ADJ	застёгнутый на молнию	застебнутий на блискавку
""".strip()


def parse_additions() -> dict[str, dict[str, object]]:
    result: dict[str, dict[str, object]] = {}
    for line in RAW_ADDITIONS.splitlines():
        key, ru, uk = line.split("\t")
        word, pos = key.rsplit("|", 1)
        result[key] = {
            "word": word,
            "pos": pos,
            "translations": {
                "ru": [item.strip() for item in ru.split(";") if item.strip()],
                "uk": [item.strip() for item in uk.split(";") if item.strip()],
            },
        }
    return result


def entry_is_empty(entry: dict[str, object]) -> bool:
    translations = entry.get("translations")
    return (
        not isinstance(translations, list)
        or not any(isinstance(item, str) and item.strip() for item in translations)
        or entry.get("has_content") is False
        or entry.get("word_found") is False
    )


def empty_keys() -> set[str]:
    result: set[str] = set()
    for path in OUTPUT_ROOT.glob("*/dictionary_*.json"):
        payload = json.loads(path.read_text(encoding="utf-8"))
        for key, entry in payload.get("entries", {}).items():
            if entry_is_empty(entry):
                result.add(key)
    return result


def refresh_workbench_dictionaries(dictionary: VirgilCoreDictionary, *, apply: bool) -> tuple[int, int]:
    manifests = 0
    entries = 0
    for path in sorted(OUTPUT_ROOT.glob("*/dictionary_*.json")):
        payload = json.loads(path.read_text(encoding="utf-8"))
        original_entries = copy.deepcopy(payload.get("entries", {}))
        changed = 0
        for key, old_entry in payload.get("entries", {}).items():
            if not entry_is_empty(old_entry):
                continue
            refreshed = dictionary.lookup(
                surface=str(old_entry.get("query") or old_entry.get("lemma") or ""),
                lemma=str(old_entry.get("lemma") or ""),
                pos=str(old_entry.get("part_of_speech") or old_entry.get("detected_part_of_speech") or ""),
                target_lang=str(payload.get("target_lang") or "ru"),
                source_segment=str(old_entry.get("source_segment") or ""),
                target_segment=str(old_entry.get("target_segment") or ""),
            )
            if entry_is_empty(refreshed):
                raise ValueError(f"Still empty after refresh: {path}: {key}")
            payload["entries"][key] = refreshed
            changed += 1
        for key, old_entry in original_entries.items():
            if not entry_is_empty(old_entry) and payload["entries"][key] != old_entry:
                raise AssertionError(f"Existing dictionary entry changed: {path}: {key}")
        if changed:
            manifests += 1
            entries += changed
            if apply:
                path.write_text(
                    json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
                    encoding="utf-8",
                    newline="\n",
                )
    return manifests, entries


def refresh_zip_dictionaries() -> tuple[int, int]:
    archives = 0
    files = 0
    for zip_path in sorted(ZIP_ROOT.glob("book_*.zip")):
        output_dir = OUTPUT_ROOT / zip_path.stem
        replacements = {
            name: (output_dir / name).read_bytes()
            for name in ("dictionary_ru.json", "dictionary_uk.json")
            if (output_dir / name).exists()
        }
        if not replacements:
            continue
        temp_path = zip_path.with_suffix(".zip.tmp")
        with zipfile.ZipFile(zip_path, "r") as src, zipfile.ZipFile(temp_path, "w", zipfile.ZIP_DEFLATED) as dst:
            seen: set[str] = set()
            for item in src.infolist():
                seen.add(item.filename)
                data = replacements.get(item.filename)
                if data is None:
                    data = src.read(item.filename)
                else:
                    files += 1
                dst.writestr(item, data)
            for name, data in replacements.items():
                if name not in seen:
                    dst.writestr(name, data)
                    files += 1
        temp_path.replace(zip_path)
        archives += 1
    return archives, files


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()

    additions = parse_additions()
    core = json.loads(CORE_PATH.read_text(encoding="utf-8"))
    original_core = copy.deepcopy(core)
    required_new = empty_keys() - set(core)
    missing_additions = sorted(required_new - set(additions))
    if missing_additions:
        raise ValueError(f"Missing additions: {missing_additions}")

    created = 0
    for key in sorted(required_new):
        core[key] = additions[key]
        created += 1

    for key, old_entry in original_core.items():
        if core[key] != old_entry:
            raise AssertionError(f"Existing Core entry changed: {key}")

    if not args.apply:
        print(f"CHECK OK: create={created}, existing_core_untouched={len(original_core)}")
        return 0

    CORE_PATH.write_text(
        json.dumps(dict(sorted(core.items())), ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
        newline="\r\n",
    )
    dictionary = VirgilCoreDictionary(BACKEND_ROOT)
    manifests, entries = refresh_workbench_dictionaries(dictionary, apply=True)
    remaining = empty_keys()
    if remaining:
        raise ValueError(f"Empty workbench keys remain: {sorted(remaining)}")
    archives, zip_files = refresh_zip_dictionaries()
    print(
        "APPLY OK: "
        f"created={created}, existing_core_untouched={len(original_core)}, "
        f"manifests={manifests}, refreshed_entries={entries}, "
        f"zip_archives={archives}, zip_dictionary_files={zip_files}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
