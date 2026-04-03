# MVP10 — iOS Pipeline And First Install Plan

## 1. Цель этапа

Подготовить LEXO к первой реальной установке на iPhone через удалённую iOS-сборку и sideloading, без Mac как основной локальной машины разработки.

Итог этапа:

- проект размещён в GitHub
- Flutter-проект содержит `iOS` platform
- настроен минимальный GitHub Actions pipeline для iOS build artifact
- получается первый `.ipa` или эквивалентный iOS build artifact
- этот artifact можно подписать и поставить на iPhone через `Sideloadly`
- появляется первый реальный цикл проверки iPhone runtime

## 2. Главный принцип

Не делать:

- пытаться сразу строить идеальную Apple signing-схему внутри CI
- откладывать первую установку на iPhone до полной полировки mobile UX
- смешивать этап build pipeline и этап продуктовой отладки

Делать:

`GitHub repo -> iOS platform -> GitHub Actions build -> artifact -> Sideloadly -> iPhone install`

То есть сначала нужен первый работающий путь до устройства.

## 3. Что должен дать MVP10

После завершения этапа должны существовать:

- git-репозиторий проекта
- public GitHub repository
- первый осмысленный commit baseline под iPhone-stage
- папка `app/ios`
- workflow:
  - checkout
  - setup Flutter
  - `flutter pub get`
  - iOS build
  - upload artifact
- понятный способ скачать artifact на Windows
- установленный `Sideloadly`
- выполненная первая установка на iPhone

## 4. Что не входит в MVP10

На этом этапе не нужно делать:

- App Store release
- TestFlight release
- платную Apple Developer CI signing-схему
- auto-deploy на iPhone
- автоматическое обновление sideloaded app
- polished iOS release engineering

## 5. Предпосылки этапа

К началу `MVP10` считается, что уже есть:

- `MVP8`:
  - общий `Mobile UI`
  - shared logic
- `MVP9`:
  - local mobile packages
  - desktop host processing model
  - host URL configuration
  - manual sync/update flow

То есть теперь есть смысл переходить к реальному iPhone runtime.

## 6. Шаг 1. Завести Git и GitHub

Нужно:

1. инициализировать git в проекте
2. создать новый `public` repository на GitHub
3. привязать локальный проект к remote
4. сделать первый push

### Почему public

Для текущего сценария это упрощает использование GitHub-hosted macOS runners как удалённой build-машины.

## 7. Шаг 2. Подготовить iOS platform в Flutter

Нужно проверить:

- существует ли `app/ios`

Если нет:

- выполнить `flutter create --platforms=ios .` внутри `app/`

Результат:

- проект получает iOS runner
- GitHub Actions сможет реально запускать iOS build

## 8. Шаг 3. Зафиксировать минимальную iOS-ready структуру

Перед первым CI build нужно убедиться, что:

- `pubspec.yaml` согласован
- проект открывается как Flutter app
- mobile-root не завязан на Android-only assumptions
- нет жёсткой привязки к Android emulator logic
- host URL configurable через UI

Главная цель:

- получить не идеальный iOS UX, а первый iOS-runtime executable

## 9. Шаг 4. Настроить GitHub Actions workflow

Нужен минимальный workflow файл:

- `.github/workflows/build-ios.yml`

На первом проходе workflow должен делать:

1. checkout repo
2. setup Flutter
3. `flutter pub get`
4. build iOS artifact
5. upload artifact

На этом этапе не нужно:

- App Store publish
- TestFlight
- сложный signing automation

## 10. Формат первого build результата

Для `MVP10` acceptable result:

- `.ipa`
или
- iOS build output, который можно довести до установки через рабочий sideload path

Предпочтительный результат:

- явный downloadable `.ipa`

## 11. Шаг 5. Установить Sideloadly на Windows

На ПК нужно:

- установить `Sideloadly`
- подготовить кабельное подключение iPhone
- доверить устройство
- включить `Developer Mode` на iPhone

## 12. Шаг 6. Первый install cycle

После успешного GitHub build:

1. скачать artifact на Windows
2. открыть `Sideloadly`
3. выбрать `.ipa`
4. указать Apple ID
5. подписать
6. установить на iPhone

Результат этапа:

- app физически появляется на iPhone

## 13. Шаг 7. Первый runtime check на iPhone

Только после первой установки начинается отдельный runtime-подэтап.

Нужно проверить:

- запускается ли приложение
- не падает ли на старте
- открывается ли mobile shell
- работает ли `Host URL`
- видит ли iPhone desktop host
- работает ли import from desktop
- работает ли import TXT
- открывается ли local mobile book
- работает ли TTS audio download

## 14. Порядок движения внутри этапа

Правильная последовательность такая:

1. GitHub repo
2. `app/ios`
3. GitHub Actions iOS build
4. artifact download
5. `Sideloadly`
6. first install
7. first runtime check

Запрещено перескакивать прямо к runtime check без установленного приложения на iPhone.

## 15. Критерии готовности

Этап считается завершённым, если:

- проект лежит в GitHub
- есть первый push
- `app/ios` существует
- workflow для iOS build существует
- GitHub Actions выдаёт iOS artifact
- artifact реально скачан на Windows
- `Sideloadly` установлен
- приложение хотя бы один раз установлено на iPhone

## 16. Главный продуктовый результат

После `MVP10` LEXO перестаёт быть только подготовленным mobile-проектом.

Он становится проектом, который:

- имеет реальный путь до iPhone
- может устанавливаться на устройство
- может проверяться в настоящем iOS runtime

## 17. Что идёт следующим этапом

После `MVP10` идёт уже device-runtime stage:

- реальные iPhone bugs
- host connectivity check
- iOS-specific layout fixes
- iPhone TTS/network behavior
- polishing mobile installation/update loop
