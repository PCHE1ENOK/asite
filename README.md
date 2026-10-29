# Anime Viewer

Десктопное приложение для просмотра аниме (Windows 11, позже iOS).
Стек: Flutter, media_kit (libmpv) для плеера, AniList GraphQL для каталога,
Drift (SQLite) для локального кэша.

## Статус

- [x] Этап 1 — каркас проекта, клиент AniList, модели, локальный кэш.
- [ ] Этап 2 — интерфейс каталога (сетка постеров, фильтры, сортировка).
- [ ] Этап 3 — вкладки и карточка аниме.
- [ ] Этап 4 — плеер (media_kit, выбор озвучки через аудиодорожки).
- [ ] Этап 5 — статусы «смотрю» и «просмотрено».
- [ ] Этап 6 — подключаемые источники видео.

## Структура

```
lib/
  main.dart                       временный экран «в тренде» для проверки данных
  data/
    anilist/anilist_queries.dart  GraphQL-запросы (каталог, карточка, жанры)
    anilist/anilist_client.dart   HTTP-клиент, разбор ответов и ошибок, повтор при 429
    models/anime.dart             Anime, AnimeDetails, обложки, студии, связи, оценки
    models/catalog_query.dart     фильтры, сортировка, поиск → переменные GraphQL
    models/page.dart              пагинация
    cache/app_database.dart       схема Drift (+ сгенерированный app_database.g.dart)
    anime_repository.dart         сеть + кэш с TTL, офлайн-режим на устаревшем кэше
test/                             тесты парсинга, клиента, кэша и репозитория
```

Кэш: каталог — 1 час, карточка — 6 часов, жанры — 7 дней. Если сеть
недоступна, отдаются устаревшие данные с флагом `isStale`. База лежит в
каталоге данных приложения (`getApplicationSupportDirectory`).

## Разработка (Windows)

Нужны Flutter SDK (stable) и Visual Studio 2022 с рабочей нагрузкой
«Desktop development with C++».

```
flutter pub get
flutter run -d windows
flutter analyze
flutter test
```

После изменения таблиц в `app_database.dart` перегенерируйте код:

```
dart run build_runner build
```
