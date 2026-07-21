# Google Play Data Safety Draft

Дата: 30 июня 2026 года

## Краткий вывод

Virgil не использует рекламу, стороннюю аналитику, Firebase Analytics или Crashlytics.

Приложение использует интернет для загрузки каталога и книг из облачного хранилища, локально хранит настройки, загруженные книги, сохраненные слова/карточки и прогресс чтения.

## Данные, которые пользователь явно может отправить

- Email feedback: только если пользователь сам нажмет Feedback и отправит письмо через свой почтовый клиент.
- Адрес поддержки: `virgil.reader.app@gmail.com`.

## Данные, которые хранятся локально

- Настройки приложения.
- Выбранный язык перевода книг.
- Выбранный язык интерфейса.
- Загруженные книги.
- Сохраненные слова и карточки.
- Локальный прогресс/состояние чтения.

## Разрешения Android

- `INTERNET`: загрузка каталога и книг.
- `ACCESS_NETWORK_STATE`: проверка сетевого состояния зависимостями.
- `WAKE_LOCK`: корректная работа аудио.
- `FOREGROUND_SERVICE` и `FOREGROUND_SERVICE_MEDIA_PLAYBACK`: управление аудио во время чтения.
- `POST_NOTIFICATIONS`: уведомление аудиоплеера на Android 13+.

## Предварительные ответы для Play Console

- App collects or shares user data: проверить в Play Console формулировку. Если email feedback считается collection, указать email/user-provided feedback как optional и user-initiated.
- Data encrypted in transit: да, книги загружаются по HTTPS.
- Users can request data deletion: для email feedback - через контакт поддержки; локальные данные удаляются удалением приложения или очисткой данных приложения.
- Ads: нет.
- Analytics: нет.
- Crash logs: нет.
- Account creation: нет.
- Location: нет.
- Contacts: нет.
- Photos/videos/audio recording: нет.
- Files outside app storage: нет для mobile release.

## Что проверить перед отправкой формы

- Не добавлена ли аналитика или crash reporting после этого аудита.
- Не изменился ли механизм feedback.
- Не появились ли аккаунты, покупки, реклама или push-уведомления не для аудиоплеера.
