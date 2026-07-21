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
across|ADP	через;поперёк	через;упоперек
ada|PROPN	Ада	Ада
again|ADV	снова;опять	знову;ще раз
air|NOUN	воздух	повітря
alarm|NOUN	будильник;сигнал	будильник;сигнал
alarm|PROPN	будильник	будильник
along|ADP	вдоль	вздовж
anna|PROPN	Анна	Анна
appointment|NOUN	приём;встреча	прийом;зустріч
asleep|ADJ	спящий;уснувший	сплячий;заснулий
assistant|NOUN	помощник;продавец-консультант	помічник;продавець-консультант
as|SCONJ	как;когда	як;коли
away|ADV	далеко;прочь	далеко;геть
bank|NOUN	банк	банк
battery|NOUN	батарея;аккумулятор	батарея;акумулятор
begin|VERB	начинать;начинаться	починати;починатися
bicycle|NOUN	велосипед	велосипед
block|NOUN	квартал;блок	квартал;блок
blue|PROPN	синий;голубой	синій;блакитний
bookshop|NOUN	книжный магазин	книжкова крамниця
boot|NOUN	ботинок;сапог	черевик;чобіт
break|NOUN	перерыв	перерва
bridge|NOUN	мост	міст
bridge|PROPN	мост	міст
bright|ADJ	яркий;светлый	яскравий;світлий
bus|PROPN	автобус	автобус
cash|NOUN	наличные деньги	готівка
central|PROPN	центральный	центральний
chooses|AUX	выбирает	обирає
cleaner|NOUN	уборщик;уборщица	прибиральник;прибиральниця
clock|PROPN	часы	годинник
close|ADJ	близкий	близький
clothing|NOUN	одежда	одяг
colder|ADJ	холоднее;более холодный	холодніший;більш холодний
colour|NOUN	цвет	колір
comfortable|ADJ	удобный;комфортный	зручний;комфортний
complete|ADJ	выполненный;полный	завершений;повний
cost|NOUN	стоимость;цена	вартість;ціна
cotton|NOUN	хлопок;хлопчатобумажная ткань	бавовна;бавовняна тканина
count|VERB	считать;подсчитывать	рахувати;підраховувати
cross|NOUN	переходить;пересекать	переходити;перетинати
cross|VERB	переходить;пересекать	переходити;перетинати
dead|ADJ	разряженный;неработающий	розряджений;непрацюючий
degree|NOUN	градус;степень	градус;ступінь
direction|NOUN	направление;указание пути	напрямок;вказівка шляху
direct|ADJ	прямой;без пересадок	прямий;без пересадок
discount|NOUN	скидка	знижка
dish|NOUN	посуда;блюдо	посуд;страва
distance|NOUN	расстояние	відстань
dress|NOUN	платье	сукня
dress|PROPN	платье	сукня
dress|VERB	одеваться;одевать	одягатися;одягати
driver|PROPN	водитель	водій
drive|VERB	водить;ехать	водити;їхати
eighty|NUM	восемьдесят	вісімдесят
ethan|PROPN	Итан	Ітан
exchange|VERB	обменивать;менять	обмінювати;міняти
fall|VERB	падать;опускаться	падати;опускатися
fare|NOUN	плата за проезд	плата за проїзд
far|ADV	далеко	далеко
fast|ADV	быстро	швидко
fifth|ADV	в-пятых	по-п’яте
fifth|NOUN	пятый;пятая	п’ятий;п’ята
fifty-eight|NUM	пятьдесят восемь	п’ятдесят вісім
fit|ADJ	подходящий;помещающийся	відповідний;такий, що поміщається
fit|VERB	подходить по размеру;помещаться	підходити за розміром;поміщатися
fix|VERB	чинить;исправлять	лагодити;виправляти
follow|VERB	следовать;идти за	слідувати;йти за
foot|NOUN	ступня;нога	ступня;нога
forty-five|NUM	сорок пять	сорок п’ять
forty-three|NUM	сорок три	сорок три
forty-two|NUM	сорок два	сорок два
forty|NUM	сорок	сорок
fourth|ADV	в-четвёртых	по-четверте
free|ADJ	свободный;бесплатный	вільний;безкоштовний
friday|PROPN	пятница	п’ятниця
gift|NOUN	подарок	подарунок
gift|PROPN	подарок	подарунок
glove|NOUN	перчатка	рукавичка
hall|PROPN	зал;холл	зал;хол
hang|NOUN	висеть;вешать	висіти;вішати
heavy|ADJ	тяжёлый;сильный	важкий;сильний
holder|NOUN	держатель;футляр	тримач;футляр
hurry|VERB	спешить;торопиться	поспішати;квапитися
hurt|VERB	болеть;причинять боль	боліти;завдавати болю
if|SCONJ	если	якщо
immediately|ADV	сразу;немедленно	одразу;негайно
inside|ADP	внутри;в	усередині;у
instead|ADV	вместо этого	натомість;замість цього
item|NOUN	предмет;вещь	предмет;річ
jacket|PROPN	куртка	куртка
jamie|PROPN	Джейми	Джеймі
jean|NOUN	джинсы;джинсовая ткань	джинси;джинсова тканина
journey|NOUN	поездка;путешествие	поїздка;подорож
kai|PROPN	Кай	Кай
kim|PROPN	Ким	Кім
king|PROPN	Кинг	Кінг
label|NOUN	этикетка;ярлык	етикетка;ярлик
lake|PROPN	Лейк	Лейк
leah|PROPN	Лия	Лія
leather|NOUN	кожа	шкіра
length|NOUN	длина	довжина
light|ADJ	лёгкий;светлый	легкий;світлий
lina|PROPN	Лина	Ліна
line|NOUN	линия;очередь	лінія;черга
loose|ADJ	свободный;просторный	вільний;просторий
lose|VERB	терять;потерять	губити;загубити
map|PROPN	карта	карта;мапа
maria|PROPN	Мария	Марія
market|PROPN	рынок	ринок
medium|ADJ	средний	середній
medium|NOUN	средний размер	середній розмір
message|NOUN	сообщение	повідомлення
metro|NOUN	метро	метро
metro|PROPN	метро	метро
miss|VERB	пропускать;пропустить	пропускати;пропустити
mistake|NOUN	ошибка	помилка
morning|PROPN	утро	ранок
museum|NOUN	музей	музей
museum|PROPN	музей	музей
must|AUX	должен;нужно	мусить;потрібно
narrow|ADJ	узкий	вузький
never|ADV	никогда	ніколи
nick|PROPN	Ник	Нік
ninety|NUM	девяносто	дев’яносто
north|NOUN	север	північ
now|INTJ	сейчас;теперь	зараз;тепер
o'clock|PROPN	часов	годин
officer|NOUN	офицер;полицейский	офіцер;поліцейський
off|ADP	выключать;снимать;выходить	вимикати;знімати;виходити
once|ADV	один раз;сразу	один раз;одразу
opposite|ADJ	противоположный;напротив	протилежний;навпроти
opposite|ADP	напротив	навпроти
pair|NOUN	пара	пара
party|NOUN	вечеринка;праздник	вечірка;свято
passenger|NOUN	пассажир;пассажирка	пасажир;пасажирка
perfectly|ADV	идеально;совершенно	ідеально;цілком
perfect|ADJ	идеальный;точный	ідеальний;точний
plan|NOUN	план	план
platform|NOUN	платформа;перрон	платформа;перон
platform|PROPN	платформа;перрон	платформа;перон
police|NOUN	полиция	поліція
practice|NOUN	тренировка;практика	тренування;практика
previous|ADJ	предыдущий	попередній
rarely|ADV	редко	рідко
receipt|NOUN	чек;квитанция	чек;квитанція
red|PROPN	красный	червоний
report|NOUN	отчёт;прогноз	звіт;прогноз
rest|VERB	отдыхать	відпочивати
river|NOUN	река	річка
river|PROPN	Ривер	Рівер
road|NOUN	дорога	дорога
road|PROPN	Роуд	Роуд
route|NOUN	маршрут	маршрут
route|PROPN	маршрут	маршрут
saturday|PROPN	суббота	субота
scarf|ADJ	шарф	шарф
scarf|NOUN	шарф	шарф
send|VERB	отправлять;посылать	надсилати;відправляти
sheet|NOUN	лист;таблица	аркуш;таблиця
shirt|NOUN	рубашка	сорочка
shoe|NOUN	туфля;обувь	туфля;взуття
shoe|PROPN	туфля;обувь	туфля;взуття
shopping|NOUN	покупки	покупки
shop|PROPN	магазин	магазин
simply|ADV	просто	просто
sixteen|NOUN	шестнадцать	шістнадцять
sixteen|NUM	шестнадцать	шістнадцять
sixth|ADJ	шестой	шостий
sixty|NUM	шестьдесят	шістдесят
size|NOUN	размер	розмір
skirt|NOUN	юбка	спідниця
sleeve|NOUN	рукав	рукав
slow|ADJ	медленный	повільний
smallest|PROPN	самый маленький	найменший
snow|NOUN	снег	сніг
snow|PROPN	снег	сніг
so|SCONJ	поэтому;так что	тому;так що
soon|ADV	скоро	скоро
south|ADV	к югу;на юге	на південь;на півдні
south|PROPN	южный	південний
sport|NOUN	спорт	спорт
square|PROPN	площадь	площа
start|NOUN	начало;старт	початок;старт
station|PROPN	станция;вокзал	станція;вокзал
stay|VERB	оставаться;жить	залишатися;жити
stop|PROPN	остановка	зупинка
straight|ADV	прямо	прямо
strong|ADJ	сильный	сильний
style|NOUN	стиль;фасон	стиль;фасон
sweater|NOUN	свитер	светр
t-shirts|NOUN	футболки	футболки
taxi|NOUN	такси	таксі
temperature|NOUN	температура	температура
ten-dollar|NUM	десятидолларовый	десятидоларовий
thick|ADJ	толстый;плотный	товстий;щільний
third|ADV	в-третьих	по-третє
thirty-five|NUM	тридцать пять	тридцять п’ять
thirty|NUM	тридцать	тридцять
ticket|NOUN	билет	квиток
tight|ADJ	тесный;тугой	тісний;тугий
toward|ADP	к;в сторону	до;у бік
town|NOUN	город	місто
traffic|NOUN	дорожное движение;пробки	дорожній рух;затори
trip|NOUN	поездка	поїздка
trouser|NOUN	брюки	штани
turn|NOUN	поворот	поворот
twenty-five|NUM	двадцать пять	двадцять п’ять
twenty-minute|NUM	двадцатиминутный	двадцятихвилинний
two-dollar|NUM	двухдолларовый	дводоларовий
visitor|NOUN	посетитель;посетительница	відвідувач;відвідувачка
walk|NOUN	прогулка	прогулянка
waterproof|ADJ	водонепроницаемый	водонепроникний
way|NOUN	путь;способ	шлях;спосіб
weather|NOUN	погода	погода
weekday|NOUN	будний день	будній день
weekend|NOUN	выходные	вихідні
well|ADJ	хорошо	добре
whole|ADJ	весь;целый	весь;цілий
wind|NOUN	ветер	вітер
winter|NOUN	зима	зима
without|ADP	без	без
wool|NOUN	шерсть	вовна
wool|PROPN	шерсть	вовна
working|NOUN	рабочий;работа	робочий;робота
wrap|VERB	заворачивать;упаковывать	загортати;пакувати
zero|NUM	ноль	нуль
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


def empty_manifest_keys() -> set[str]:
    result: set[str] = set()
    for path in OUTPUT_ROOT.glob("*/dictionary_*.json"):
        payload = json.loads(path.read_text(encoding="utf-8"))
        for key, entry in payload.get("entries", {}).items():
            if not entry.get("has_content") or not entry.get("translations"):
                result.add(key)
    return result


def refresh_empty_entries(dictionary: VirgilCoreDictionary, *, apply: bool) -> tuple[int, int]:
    manifests = 0
    entries = 0
    for path in sorted(OUTPUT_ROOT.glob("*/dictionary_*.json")):
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
    empty_keys = empty_manifest_keys()
    required_new = empty_keys - set(core)
    missing = sorted(required_new - set(additions))
    if missing:
        raise ValueError(f"Missing additions for empty keys: {missing}")

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

    dictionary = VirgilCoreDictionary(BACKEND_ROOT) if args.apply else None
    if dictionary is None:
        print(f"CHECK OK: create={created}, existing_untouched={len(original_core)}")
        return 0

    manifests, entries = refresh_empty_entries(dictionary, apply=True)
    remaining = empty_manifest_keys()
    if remaining:
        raise ValueError(f"Empty manifest keys remain: {sorted(remaining)}")
    print(
        f"APPLY OK: created={created}, existing_untouched={len(original_core)}, "
        f"manifests={manifests}, refreshed_entries={entries}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
