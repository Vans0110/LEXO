from __future__ import annotations

from pathlib import Path


class ArgosTranslator:
    provider_name = "argos-translate-en_ru-1_9"

    def __init__(self, model_path: Path) -> None:
        self.model_path = model_path
        self._translation = None
        self._error = ""

    @property
    def is_available(self) -> bool:
        if self._translation is not None:
            return True
        self._ensure_loaded()
        return self._translation is not None

    @property
    def error(self) -> str:
        return self._error

    def translate_segments(self, segments: list[str]) -> list[str]:
        if not self.is_available:
            return ["" for _ in segments]
        return [self._translate_one(segment) for segment in segments]

    def _translate_one(self, text: str) -> str:
        normalized = str(text or "").strip()
        if not normalized or self._translation is None:
            return ""
        try:
            return str(self._translation.translate(normalized) or "").strip()
        except Exception as exc:
            self._error = str(exc)
            return ""

    def _ensure_loaded(self) -> None:
        if self._translation is not None:
            return
        if not self.model_path.exists():
            self._error = f"Argos model file not found: {self.model_path}"
            return
        try:
            import argostranslate.package
            import argostranslate.translate
        except Exception as exc:
            self._error = f"argostranslate is not installed: {exc}"
            return

        try:
            self._install_package_if_needed(argostranslate.package, argostranslate.translate)
            self._translation = self._find_translation(argostranslate.translate)
            if self._translation is None:
                self._error = "Argos en->ru translation package is not installed"
        except Exception as exc:
            self._translation = None
            self._error = str(exc)

    def _install_package_if_needed(self, package_module: object, translate_module: object) -> None:
        if self._find_translation(translate_module) is not None:
            return
        package_module.install_from_path(str(self.model_path))

    def _find_translation(self, translate_module: object) -> object | None:
        languages = translate_module.get_installed_languages()
        source_language = next((item for item in languages if item.code == "en"), None)
        target_language = next((item for item in languages if item.code == "ru"), None)
        if source_language is None or target_language is None:
            return None
        return source_language.get_translation(target_language)
