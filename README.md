# Anime Viewer

Приложение для просмотра аниме: Windows, Android, iOS.
Стек: Flutter, media_kit (libmpv) для плеера, AniList GraphQL для каталога,
Drift (SQLite) для локального кэша, иконки Material Symbols Rounded.

Решения:
- Тайтлы 18+ показываются сразу с пометкой «18+»; фильтр «Показывать 18+»
  по умолчанию включён.
- Списки пользователя (статусы) хранятся локально и синхронизируются в
  приватный GitHub Gist самого пользователя; сервер не нужен. Вход — GitHub
  Device Flow, токен — во `flutter_secure_storage`. Client ID задаётся
  `--dart-define=GITHUB_CLIENT_ID=...` (`lib/config/app_config.dart`).
- Mica-фон — только на Windows 11, на других платформах игнорируется.
- Источники видео подключаются только плагинами на этапе 6.

## Статус

- [x] Этап 1 — каркас проекта, клиент AniList, модели, локальный кэш.
- [x] Этап 2 — интерфейс каталога (сетка постеров, фильтры, сортировка), поиск, настройки.
- [x] Этап 3 — карточка аниме с вкладками «Серии», «Описание», «Статистика», «Похожие».
- [ ] Этап 4 — плеер (media_kit, выбор озвучки через аудиодорожки).
- [ ] Этап 5 — статусы «смотрю» и «просмотрено», синхронизация через GitHub Gist.
- [ ] Этап 6 — подключаемые источники видео.

## Структура

```
lib/
  main.dart                       временный экран «в тренде» для проверки данных
  config/app_config.dart          настройки сборки (GitHub Client ID)
  data/
    anilist/anilist_queries.dart  GraphQL-запросы (каталог, карточка, жанры)
    anilist/anilist_client.dart   HTTP-клиент, разбор ответов и ошибок, повтор при 429
    models/anime.dart             Anime, AnimeDetails, обложки, студии, связи, оценки
    models/catalog_query.dart     фильтры, сортировка, поиск → переменные GraphQL
    models/page.dart              пагинация
    cache/app_database.dart       схема Drift (+ сгенерированный app_database.g.dart)
    anime_repository.dart         сеть + кэш с TTL, офлайн-режим на устаревшем кэше
    library/library_repository.dart  списки пользователя (статус, прогресс, оценка)
    github/                       Device Flow, клиент Gist, хранилище токена
    sync/                         слияние списков, формат файла Gist, SyncService
    settings/app_preferences.dart первый запуск, фильтр 18+
  app_services.dart               сборка сервисов
  ui/
    theme/                        токены design/tokens.json → ThemeData + AppTokens
    shell/app_shell.dart          NavRail / нижняя навигация, вкладки, Ctrl+K
    catalog/                      каталог: фильтры, сортировка, сетка
    search/                       поиск: debounce 300 мс, подсказки, недавние
    title/                        карточка тайтла, список серий, графики
    settings/                     настройки: аккаунт, 18+, тема, версия
    lists/                        «Мои списки» (заготовка до этапа статусов)
    widgets/                      PosterCard, бейджи, скелетоны, состояния
    login_flow.dart               вход через GitHub (заготовка без дизайна)
assets/fonts/                     Unbounded и Golos Text (OFL)
test/                             тесты парсинга, клиента, кэша и репозитория
```

Синхронизация: локальная база — источник правды на устройстве. При запуске
приложения и через 5 с после изменения списки сливаются с файлом
`anime-viewer-library.json` в приватном Gist (по каждому тайтлу остаётся
запись с более поздним `updatedAt`, тайтлы только с одной стороны
сохраняются, удаления хранятся как отметки; при первом входе — так же,
без диалога).
Фоновой синхронизации по расписанию нет (ограничение iOS). Отозванный токен
приводит к выходу; списки на устройстве и Gist при этом сохраняются.

Кэш: каталог — 1 час, карточка — 6 часов, жанры — 7 дней. Если сеть
недоступна, отдаются устаревшие данные с флагом `isStale`. База лежит в
каталоге данных приложения (`getApplicationSupportDirectory`).

## Разработка

Нужен Flutter SDK (stable). Для Windows — Visual Studio 2022 с рабочей
нагрузкой «Desktop development with C++», для Android — Android SDK,
для iOS — macOS с Xcode (собрать iOS на Windows или Linux нельзя).

```
flutter pub get
flutter analyze
flutter test
dart run tool/smoke_anilist.dart   # реальные запросы к AniList
```

Client ID OAuth-приложения GitHub «Anilist Viewer» (Device Flow включён)
передаётся настройкой сборки, в коде значения по умолчанию нет. Client
secret не нужен. Настройки лежат в `config/app.json`; VS Code подключает
файл через `.vscode/launch.json`.

```
# Windows
flutter run -d windows --dart-define-from-file=config/app.json
flutter build windows --release --dart-define=GITHUB_CLIENT_ID=Ov23lixvFjCs94iKTfNX

# iOS (на macOS с Xcode)
flutter run -d ios --dart-define-from-file=config/app.json
flutter build ipa --release --dart-define=GITHUB_CLIENT_ID=Ov23lixvFjCs94iKTfNX

# Android
flutter run -d android --dart-define-from-file=config/app.json
```

Без `GITHUB_CLIENT_ID` приложение работает, но кнопка «Войти через GitHub»
неактивна.

Скриншоты экранов для визуальной проверки (рендер в тестах с настоящими
шрифтами и сгенерированными обложками, результат в `test/screenshots/out/`):

```
flutter test test/screenshots --update-goldens --dart-define=SCREENSHOTS=true
```

После изменения таблиц в `app_database.dart` перегенерируйте код:

```
dart run build_runner build
```
