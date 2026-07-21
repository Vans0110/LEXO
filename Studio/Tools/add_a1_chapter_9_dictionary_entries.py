from __future__ import annotations

import argparse
import copy
import json
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BACKEND_ROOT = ROOT / "Backend"
CORE_PATH = BACKEND_ROOT / "data" / "dictionaries" / "virgil_core" / "virgil_core_dictionary.json"
OUTPUT_ROOT = ROOT / "Runtime" / "workbench_output" / "a1" / "chapters"

sys.path.insert(0, str(BACKEND_ROOT))

from engine.virgil_core_dictionary import VirgilCoreDictionary  # noqa: E402


RAW_ADDITIONS = """
afternoon|PROPN	вторая половина дня;после полудня	друга половина дня;після полудня
autumn|NOUN	осень	осінь
below|ADV	внизу;ниже	внизу;нижче
bird|NOUN	птица	птах
branch|NOUN	ветка;ветвь	гілка
chen|PROPN	Чен	Чен
cloud|NOUN	облако	хмара
colour|VERB	окрашивать;придавать цвет	забарвлювати;надавати колір
cool|ADJ	прохладный	прохолодний
cover|VERB	покрывать;накрывать	покривати;накривати
decide|VERB	решать;принимать решение	вирішувати;приймати рішення
deep|ADV	глубокий	глибокий
down|ADV	вниз;внизу	вниз;унизу
drink|NOUN	напиток	напій
drop|NOUN	капля	крапля
drop|VERB	капать;падать каплями	капати;падати краплями
dry|ADJ	сухой	сухий
flower|NOUN	цветок	квітка
forest|NOUN	лес	ліс
forest|PROPN	лес	ліс
fountain|NOUN	фонтан	фонтан
freeze|VERB	замерзать;замораживать	замерзати;заморожувати
fresh|ADJ	свежий	свіжий
garden|NOUN	сад	сад
grass|NOUN	трава	трава
grow|VERB	расти;вырастать	рости;виростати
hill|NOUN	холм	пагорб
hit|VERB	ударять;стучать	ударяти;стукати
hottest|PROPN	самый жаркий	найспекотніший
hot|ADJ	жаркий;горячий	спекотний;гарячий
hundred|NUM	сто	сто
ice|NOUN	лёд	лід
icy|ADJ	ледяной;обледенелый	крижаний;обмерзлий
imagine|VERB	представлять;воображать	уявляти
january|PROPN	январь	січень
julia|PROPN	Юлия	Юлія
july|PROPN	июль	липень
jump|VERB	прыгать;перепрыгивать	стрибати;перестрибувати
lake|NOUN	озеро	озеро
loud|ADJ	громкий	гучний
march|PROPN	март	березень
melt|VERB	таять;растапливать	танути;розтоплювати
nature|NOUN	природа	природа
nephew|NOUN	племянник	племінник
noon|NOUN	полдень	полудень
october|PROPN	октябрь	жовтень
only|ADJ	только;лишь	тільки;лише
onto|ADP	на	на
open|ADJ	открываться;распускаться	відкриватися;розкриватися
orange|ADJ	оранжевый	помаранчевий
path|NOUN	тропа;дорожка	стежка;доріжка
pip|PROPN	Пип	Піп
point|NOUN	указывать;показывать	вказувати;показувати
pool|NOUN	лужа;бассейн	калюжа;басейн
rainy|ADJ	дождливый	дощовий
rainy|PROPN	дождливый	дощовий
rain|NOUN	дождь	дощ
rise|VERB	подниматься;повышаться	підніматися;підвищуватися
roof|NOUN	крыша	дах
rubbish|ADJ	мусор	сміття
ruin|VERB	портить;разрушать	псувати;руйнувати
seasons|PROPN	времена года	пори року
season|NOUN	сезон;время года	сезон;пора року
shade|NOUN	тень	тінь
shine|VERB	сиять;блестеть	сяяти;блищати
shin|VERB	сиять;блестеть	сяяти;блищати
should|AUX	следует;должен	слід;повинен
sing|VERB	петь	співати
sky|NOUN	небо	небо
snowman|NOUN	снеговик	сніговик
spend|VERB	проводить;тратить	проводити;витрачати
spring|NOUN	весна	весна
storm|NOUN	буря;гроза	буря;гроза
summer|NOUN	лето	літо
sun|NOUN	солнце	сонце
tennis|NOUN	теннис	теніс
thirsty|ADJ	испытывающий жажду;хотящий пить	спраглий;той, хто хоче пити
thirty-one|NUM	тридцать один	тридцять один
thirty-six|NUM	тридцать шесть	тридцять шість
thunder|NOUN	гром	грім
top|NOUN	верх;вершина	верх;вершина
touch|VERB	касаться;трогать	торкатися;доторкатися
until|ADP	до	до
visible|ADJ	видимый	видимий
wall|NOUN	стена	стіна
wet|ADJ	мокрый;влажный	мокрий;вологий
""".strip()


def parse_additions() -> dict[str, dict[str, list[str]]]:
    result: dict[str, dict[str, list[str]]] = {}
    for line in RAW_ADDITIONS.splitlines():
        key, ru, uk = line.split("\t")
        if key in result:
            raise ValueError(f"Duplicate addition: {key}")
        result[key] = {
            "ru": [item.strip() for item in ru.split(";") if item.strip()],
            "uk": [item.strip() for item in uk.split(";") if item.strip()],
        }
    return result


def chapter_paths() -> list[Path]:
    result = []
    for directory in OUTPUT_ROOT.iterdir():
        manifest_path = directory / "manifest.json"
        if not manifest_path.exists():
            continue
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        if manifest.get("chapter_id") == "chapter_09_weather_nature":
            result.extend(directory.glob("dictionary_*.json"))
    return sorted(result)


def empty_keys() -> set[str]:
    result: set[str] = set()
    for path in chapter_paths():
        payload = json.loads(path.read_text(encoding="utf-8"))
        for key, entry in payload.get("entries", {}).items():
            if not entry.get("has_content") or not entry.get("translations"):
                result.add(key)
    return result


def refresh_empty_entries(dictionary: VirgilCoreDictionary, *, apply: bool) -> tuple[int, int]:
    manifests = 0
    entries = 0
    for path in chapter_paths():
        payload = json.loads(path.read_text(encoding="utf-8"))
        original_entries = copy.deepcopy(payload.get("entries", {}))
        changed = 0
        for key, old_entry in payload.get("entries", {}).items():
            if old_entry.get("has_content") and old_entry.get("translations"):
                continue
            refreshed = dictionary.lookup(
                surface=str(old_entry.get("query") or old_entry.get("lemma") or ""),
                lemma=str(old_entry.get("lemma") or ""),
                pos=str(old_entry.get("part_of_speech") or ""),
                target_lang=str(payload.get("target_lang") or "ru"),
                source_segment=str(old_entry.get("source_segment") or ""),
                target_segment=str(old_entry.get("target_segment") or ""),
            )
            if not refreshed.get("has_content") or not refreshed.get("translations"):
                raise ValueError(f"Still empty after refresh: {path}: {key}")
            payload["entries"][key] = refreshed
            changed += 1
        for key, old_entry in original_entries.items():
            if old_entry.get("has_content") and old_entry.get("translations"):
                if payload["entries"][key] != old_entry:
                    raise AssertionError(f"Existing manifest entry changed: {path}: {key}")
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


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()

    additions = parse_additions()
    core = json.loads(CORE_PATH.read_text(encoding="utf-8"))
    original_core = copy.deepcopy(core)
    required_new = empty_keys() - set(core)
    missing = sorted(required_new - set(additions))
    extra = sorted(set(additions) - required_new - set(core))
    if missing or extra:
        raise ValueError(f"Addition set mismatch: missing={missing}, extra={extra}")

    created = 0
    for key, translations in additions.items():
        word, pos = key.rsplit("|", 1)
        expected = {"pos": pos, "translations": translations, "word": word}
        if key in core:
            if core[key] != expected:
                raise AssertionError(f"Existing Core entry differs: {key}")
            continue
        core[key] = expected
        created += 1

    for key, old_entry in original_core.items():
        if core[key] != old_entry:
            raise AssertionError(f"Existing Core entry changed: {key}")

    if args.apply:
        CORE_PATH.write_text(
            json.dumps(core, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
            newline="\r\n",
        )
    else:
        print(f"CHECK OK: create={created}, existing_untouched={len(original_core)}")
        return 0

    dictionary = VirgilCoreDictionary(BACKEND_ROOT)
    manifests, entries = refresh_empty_entries(dictionary, apply=True)
    remaining = empty_keys()
    if remaining:
        raise ValueError(f"Empty chapter 9 keys remain: {sorted(remaining)}")
    print(
        f"APPLY OK: created={created}, existing_untouched={len(original_core)}, "
        f"manifests={manifests}, refreshed_entries={entries}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
