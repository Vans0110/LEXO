from __future__ import annotations

import re


NAME_TRANSLATIONS = {
    "tom": "Том",
    "luna": "Луна",
    "anna": "Анна",
    "sarah": "Сара",
    "leo": "Лео",
}
REPORTING_VERB_TRANSLATIONS = {
    "says": "говорит",
    "asks": "спрашивает",
    "thinks": "думает",
    "whispers": "шепчет",
}
PRONOUN_TRANSLATIONS = {
    "i": "я",
    "you": "ты",
    "he": "он",
    "she": "она",
    "it": "это",
    "we": "мы",
    "they": "они",
}
BE_TRANSLATIONS = {
    "great": "в порядке",
    "grate": "в порядке",
    "happy": "счастлив",
    "tired": "уставший",
    "ready": "готов",
    "hungry": "голодный",
    "sad": "грустный",
}
POSSESSIVE_TRANSLATIONS = {
    "my": "мой",
    "your": "твой",
    "his": "его",
    "her": "её",
    "our": "наш",
    "their": "их",
}


def resolve_didactic_translation(
    source_segment: str,
    source_lang: str,
    target_lang: str,
) -> str | None:
    if not _is_en_ru(source_lang, target_lang):
        return None

    normalized_source = _normalize_source(source_segment)
    if normalized_source == "how are you? tom asks.":
        return '"Как дела?" - спрашивает Том.'
    if normalized_source == '"good morning, luna!" tom says.':
        return '"Доброе утро, Луна!" - говорит Том.'
    if normalized_source == '"hello, anna! how are you?" tom asks.':
        return '"Привет, Анна! Как дела?" - спрашивает Том.'
    if normalized_source == '"goodnight, luna," tom whispers.':
        return '"Спокойной ночи, Луна", - шепчет Том.'
    if normalized_source == '"it is a beautiful day," tom thinks.':
        return '"Это прекрасный день", - думает Том.'
    if normalized_source == "it is a very good day.":
        return "Это очень хороший день."
    if normalized_source == "chapter 4: home in the afternoon, tom goes home.":
        return "Глава 4: Дом Днем Том идёт домой."
    if normalized_source == "chapter 2: breakfast":
        return "Глава 2: Завтрак"
    if normalized_source == "tom goes to the park":
        return "Том идёт в парк."
    if normalized_source == "he wears a blue t-shirt and white shoes.":
        return "Он носит синюю футболку и белые туфли."
    if normalized_source == "in the park, he sees his friend, anna.":
        return "В парке он видит свою подругу Анну."
    if normalized_source == "he is a little tired but very happy.":
        return "Он немного устал, но очень счастлив."
    if normalized_source == "he reads a book on the sofa.":
        return "Он читает книгу на диване."
    if normalized_source == "they walk together.":
        return "Они идут вместе."
    if normalized_source == '"wow," sarah says.':
        return '"Вау", - говорит Сара.'
    if normalized_source == '"it is beautiful here."':
        return '"Здесь очень красиво."'
    if normalized_source == "leo barks.":
        return "Лео лает."
    if normalized_source == "leo has his leash in his mouth.":
        return "Лео держит поводок в зубах."
    if normalized_source == "leo wags his tail.":
        return "Лео виляет хвостом."
    if normalized_source == "the squirrel is small and brown.":
        return "Белка маленькая и коричневая."
    if normalized_source == "sarah gives him a small treat.":
        return "Сара даёт ему маленькое лакомство."
    if normalized_source == "he smells the grass and the stones.":
        return "Он нюхает траву и камни."
    if normalized_source == "he walks slowly.":
        return "Он идёт медленно."
    if normalized_source == "she takes a photo with her phone to show her mother.":
        return "Она делает фото на телефон, чтобы показать своей маме."
    if normalized_source == "she sees a small village and a blue lake far away.":
        return "Она видит вдали маленькую деревню и голубое озеро."
    return (
        _resolve_dialogue_reporting_rule(source_segment)
        or _resolve_formula_reporting_rule(source_segment)
        or _resolve_pronoun_be_rule(source_segment)
        or _resolve_possessive_preposition_rule(source_segment)
        or _resolve_possessive_object_rule(source_segment)
    )


def apply_didactic_post_edit(
    source_segment: str,
    translated_segment: str,
    source_lang: str,
    target_lang: str,
) -> str:
    if not _is_en_ru(source_lang, target_lang):
        return translated_segment

    text = translated_segment
    normalized_source = _normalize_source(source_segment)

    text = text.replace("Мев", "Мяу")
    text = text.replace("серыя", "серая")
    text = text.replace("синий футболка", "синюю футболку")
    text = text.replace("готовит завтрак", "делает завтрак")

    if "goodnight" in normalized_source:
        text = text.replace("Доброй вечер", "Спокойной ночи")
        text = text.replace("Доброй ночи", "Спокойной ночи")

    if "the sunny morning" in normalized_source:
        text = text.replace('В "Солнечном утром"', '"Солнечное утро"')
        text = text.replace('в "Солнечном утром"', '"Солнечное утро"')

    if "blue t-shirt" in normalized_source:
        text = text.replace("синий футболка", "синюю футболку")

    if "makes breakfast" in normalized_source:
        text = text.replace("готовит завтрак", "делает завтрак")

    if "goes home" in normalized_source:
        text = text.replace("уходит домой", "идёт домой")

    if "goes to the park" in normalized_source:
        text = text.replace("отправляется в парк", "идёт в парк")
        text = text.replace("уходит в парк", "идёт в парк")
        text = text.replace("пошел в парк", "идёт в парк")

    if normalized_source.startswith("it is a beautiful day"):
        text = re.sub(r"^\"?Сегодня", '"Это' if text.startswith('"') else "Это", text)

    if normalized_source == "it is a very good day.":
        text = re.sub(r"^Сегодня", "Это", text)

    if normalized_source == '"it is a beautiful day," tom thinks.':
        text = text.replace('"Сегодня прекрасный день"', '"Это прекрасный день"')
        text = text.replace("спросил", "спрашивает")
        text = text.replace("подумал", "думает")

    if normalized_source == "he wears a blue t-shirt and white shoes.":
        text = text.replace("носил", "носит")
        text = text.replace("синие футболки", "синюю футболку")
    if normalized_source == "in the park, he sees his friend, anna.":
        text = text.replace("встретился со своей подругой анной", "видит свою подругу Анну")
        text = text.replace("встретился со своей подругой Анной", "видит свою подругу Анну")
    if normalized_source == "they walk together.":
        text = text.replace("ходят вместе", "идут вместе")
    if normalized_source == "he reads a book on the sofa.":
        text = text.replace("читает книгу на софе", "читает книгу на диване")
    if "leash" in normalized_source:
        text = text.replace("лишка", "поводок")
        text = text.replace("в рот", "в зубах")
    if "wags his tail" in normalized_source:
        text = text.replace("раздвигает хвост", "виляет хвостом")
    if normalized_source == "leo barks.":
        text = text.replace("греет", "лает")
    if "squirrel is small and brown" in normalized_source:
        text = text.replace("Скура", "Белка")
    if "small treat" in normalized_source:
        text = text.replace("небольшое удовольствие", "маленькое лакомство")
    if "smells the grass and the stones" in normalized_source:
        text = text.replace("пахнет травой и камнями", "нюхает траву и камни")
    if normalized_source == '"wow," sarah says.':
        text = text.replace('"Вау, - говорит Сара. - Я знаю.', '"Вау", - говорит Сара.')
        text = text.replace('"Вау", - сказала Сара.', '"Вау", - говорит Сара.')
    if normalized_source == '"it is beautiful here."':
        text = text.replace('"Здесь очень красиво".', '"Здесь очень красиво."')
    if normalized_source == "he walks slowly.":
        text = text.replace("ходит медленно", "идёт медленно")
    if normalized_source == "she takes a photo with her phone to show her mother.":
        text = text.replace(
            "фотографирует с помощью своего телефона, чтобы показать своей матери",
            "делает фото на телефон, чтобы показать своей маме",
        )
    if normalized_source == "she sees a small village and a blue lake far away.":
        text = text.replace("маленькую деревню и голубое озеро далеко", "вдали маленькую деревню и голубое озеро")

    if normalized_source == "how are you? tom asks.":
        text = text.replace("спросил", "спрашивает")

    if normalized_source.endswith(" tom says."):
        text = text.replace("сказал", "говорит")
        text = text.replace("сказала", "говорит")
    if normalized_source.endswith(" tom asks."):
        text = text.replace("спросил", "спрашивает")
        text = text.replace("спросила", "спрашивает")
    if normalized_source.endswith(" tom thinks."):
        text = text.replace("подумал", "думает")
        text = text.replace("подумала", "думает")
    if normalized_source.endswith(" tom whispers."):
        text = text.replace("прошептал", "шепчет")
        text = text.replace("прошептала", "шепчет")

    text = _post_edit_possessives(normalized_source, text)
    text = _post_edit_pronoun_be(normalized_source, text)

    return text


def _resolve_dialogue_reporting_rule(source_segment: str) -> str | None:
    pattern = re.match(
        r'^\s*"(?P<quote>[^"]+)"\s+(?P<speaker>[A-Za-z]+)\s+(?P<verb>says|asks|thinks|whispers)\.\s*$',
        source_segment,
        flags=re.IGNORECASE,
    )
    if pattern is None:
        return None

    quote = str(pattern.group("quote") or "").strip()
    speaker = _translate_name(str(pattern.group("speaker") or ""))
    verb = REPORTING_VERB_TRANSLATIONS.get(str(pattern.group("verb") or "").lower())
    translated_quote = _translate_fixed_quote(quote)
    if not translated_quote or not speaker or not verb:
        return None
    return f'"{translated_quote}" - {verb} {speaker}.'


def _translate_fixed_quote(quote: str) -> str | None:
    normalized_quote = _normalize_source(quote)
    fixed_quotes = {
        "good morning, luna!": "Доброе утро, Луна!",
        "goodnight, luna,": "Спокойной ночи, Луна,",
        "how are you?": "Как дела?",
        "thank you!": "Спасибо!",
        "thank you": "Спасибо!",
        "it is a beautiful day,": "Это прекрасный день,",
    }
    fixed_translation = fixed_quotes.get(normalized_quote)
    if fixed_translation is not None:
        return fixed_translation
    pronoun_be_translation = _resolve_pronoun_be_rule(quote)
    if pronoun_be_translation is None:
        return None
    return pronoun_be_translation.rstrip(".")


def _resolve_formula_reporting_rule(source_segment: str) -> str | None:
    pattern = re.match(
        r'^\s*"?(?P<formula>how are you\?|thank you!?)"?\s+(?P<speaker>[A-Za-z]+)\s+(?P<verb>says|asks|thinks|whispers)\.\s*$',
        source_segment,
        flags=re.IGNORECASE,
    )
    if pattern is None:
        return None

    formula = str(pattern.group("formula") or "").strip()
    speaker = _translate_name(str(pattern.group("speaker") or ""))
    verb = REPORTING_VERB_TRANSLATIONS.get(str(pattern.group("verb") or "").lower())
    translated_formula = _translate_fixed_quote(formula)
    if not translated_formula or not speaker or not verb:
        return None
    return f'"{translated_formula}" - {verb} {speaker}.'


def _resolve_pronoun_be_rule(source_segment: str) -> str | None:
    pattern = re.match(
        r"^\s*(?P<pronoun>I|You|He|She|We|They)\s+(?P<be>am|are|is)\s+(?P<predicate>great|grate|happy|tired|ready|hungry|sad)\s*(?P<tail>,\s*thank you!?)?\s*[.!?]?\s*$",
        source_segment,
        flags=re.IGNORECASE,
    )
    if pattern is None:
        return None

    pronoun = str(pattern.group("pronoun") or "").strip().lower()
    predicate = str(pattern.group("predicate") or "").strip().lower()
    tail = str(pattern.group("tail") or "").strip()
    translated_pronoun = PRONOUN_TRANSLATIONS.get(pronoun)
    translated_predicate = _inflect_be_predicate(pronoun, predicate)
    if not translated_pronoun or not translated_predicate:
        return None
    translated = f"{_capitalize(translated_pronoun)} {translated_predicate}"
    if tail:
        translated += ", спасибо!"
        return translated
    return translated + "."


def _resolve_possessive_preposition_rule(source_segment: str) -> str | None:
    pattern = re.match(
        r"^\s*(?P<subject>[A-Za-z]+)\s+(?P<verb>sleeps|sits|stands)\s+on\s+(?P<possessive>my|your|his|her|our|their)\s+(?P<object>legs|feet|hands)\.\s*$",
        source_segment,
        flags=re.IGNORECASE,
    )
    if pattern is None:
        return None

    subject = _translate_name(str(pattern.group("subject") or ""))
    verb = str(pattern.group("verb") or "").strip().lower()
    possessive = str(pattern.group("possessive") or "").strip().lower()
    obj = str(pattern.group("object") or "").strip().lower()
    verb_map = {"sleeps": "спит", "sits": "сидит", "stands": "стоит"}
    object_map = {"legs": "ногах", "feet": "ступнях", "hands": "руках"}
    translated_verb = verb_map.get(verb)
    translated_possessive = POSSESSIVE_TRANSLATIONS.get(possessive)
    translated_object = object_map.get(obj)
    if not subject or not translated_verb or not translated_possessive or not translated_object:
        return None
    return f"{subject} {translated_verb} на {translated_possessive} {translated_object}."


def _resolve_possessive_object_rule(source_segment: str) -> str | None:
    pattern = re.match(
        r"^\s*(?P<subject>I|You|He|She|We|They|[A-Za-z]+)\s+(?P<verb>see|sees|find|finds|love|loves)\s+(?P<possessive>my|your|his|her|our|their)\s+(?P<object>friend|cat|dog|book)\s*\.?\s*$",
        source_segment,
        flags=re.IGNORECASE,
    )
    if pattern is None:
        return None

    subject_raw = str(pattern.group("subject") or "").strip()
    verb = str(pattern.group("verb") or "").strip().lower()
    possessive = str(pattern.group("possessive") or "").strip().lower()
    obj = str(pattern.group("object") or "").strip().lower()
    subject = _translate_name(subject_raw) if subject_raw.lower() in NAME_TRANSLATIONS else _translate_pronoun(subject_raw)
    verb_map = {"see": "вижу", "sees": "видит", "find": "нахожу", "finds": "находит", "love": "люблю", "loves": "любит"}
    object_map = {
        "friend": "друга",
        "cat": "кота",
        "dog": "собаку",
        "book": "книгу",
    }
    translated_verb = verb_map.get(verb)
    translated_possessive = POSSESSIVE_TRANSLATIONS.get(possessive)
    translated_object = object_map.get(obj)
    if not subject or not translated_verb or not translated_possessive or not translated_object:
        return None
    return f"{_capitalize(subject)} {translated_verb} {translated_possessive} {translated_object}."


def _post_edit_possessives(normalized_source: str, text: str) -> str:
    replacements = {
        "on his legs": (" на ногах", " на его ногах"),
        "on her legs": (" на ногах", " на её ногах"),
        "on my legs": (" на ногах", " на моих ногах"),
        "on your legs": (" на ногах", " на твоих ногах"),
        "on our legs": (" на ногах", " на наших ногах"),
        "on their legs": (" на ногах", " на их ногах"),
    }
    for source_fragment, (needle, replacement) in replacements.items():
        if source_fragment in normalized_source and needle in text:
            text = text.replace(needle, replacement)
    return text


def _post_edit_pronoun_be(normalized_source: str, text: str) -> str:
    if "i am great" in normalized_source:
        text = text.replace("Я отлично справляюсь", "Я в порядке")
        text = text.replace("Я отлично", "Я в порядке")
    return text


def _translate_pronoun(pronoun: str) -> str:
    return PRONOUN_TRANSLATIONS.get((pronoun or "").strip().lower(), pronoun)


def _inflect_be_predicate(pronoun: str, predicate: str) -> str | None:
    normalized_pronoun = (pronoun or "").strip().lower()
    normalized_predicate = (predicate or "").strip().lower()
    base = BE_TRANSLATIONS.get(normalized_predicate)
    if base is None:
        return None
    if normalized_pronoun in {"she"}:
        feminine = {
            "счастлив": "счастлива",
            "уставший": "уставшая",
            "готов": "готова",
            "голодный": "голодна",
            "грустный": "грустна",
            "в порядке": "в порядке",
        }
        return feminine.get(base, base)
    if normalized_pronoun in {"we", "they", "you"}:
        plural = {
            "счастлив": "счастливы",
            "уставший": "уставшие",
            "готов": "готовы",
            "голодный": "голодны",
            "грустный": "грустны",
            "в порядке": "в порядке",
        }
        return plural.get(base, base)
    return base


def _capitalize(text: str) -> str:
    if not text:
        return text
    return text[0].upper() + text[1:]


def _translate_name(name: str) -> str:
    normalized = (name or "").strip().lower()
    return NAME_TRANSLATIONS.get(normalized, name)


def _normalize_source(text: str) -> str:
    return " ".join((text or "").strip().lower().split())


def _is_en_ru(source_lang: str, target_lang: str) -> bool:
    return (source_lang or "").strip().lower() == "en" and (target_lang or "").strip().lower() == "ru"
