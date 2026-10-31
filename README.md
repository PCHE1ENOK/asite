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
- [ ] Этап 4.5 — распознавание музыки (Chromaprint + AcoustID): заложена архитектура и заглушка.
- [x] Этап 5 — статусы «смотрю» и «просмотрено», «Мои списки», синхронизация через GitHub Gist (вход не проверен на реальном GitHub).
- [x] Этап 6 — источник видео: официальные бесплатные видео правообладателей на YouTube (Data API v3, ключ `YOUTUBE_API_KEY`), воспроизведение только встроенным плеером YouTube; без ключа источник пустой. Серии — только с каналов Muse Asia и Ani-One Asia; трейлеры (кнопка «Трейлер на YouTube», нет трейлера — нет кнопки) — с Crunchyroll и Netflix Anime (`YouTubeMatch.trailerChannels`), опенинги, клипы и музыка отсеиваются. Трейлер сначала берётся из AniList и проверяется `videos.list`; поиск по каналам — только по «Найти трейлер» / «Проверить снова». Пустой поиск кэшируется 6 часов, найденное — 3 дня.

Русские названия и описания — из открытого API Shikimori (`shikimori.one/api`, без ключа, свой User-Agent, не больше 4 запросов в секунду): AniList русского не отдаёт. Сопоставление по id MyAnimeList (`idMal` AniList = id Shikimori), без него — поиск по названию с проверкой года. Русские названия в каталоге и списках — одним запросом на страницу; кэш — 7 дней. Нет на Shikimori — английское название и описание AniList с пометкой «на английском». Перевод описаний не выполняется.

Квота YouTube Data API — 10 000 единиц в сутки: серии нового тайтла — 2 × 100 (`search.list`), проверка трейлера AniList — 1, поиск трейлера по нажатию — до 2 × 100, комментарии — 1 за страницу; повторные открытия берутся из кэша и квоту не тратят.

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
    notes/notes_repository.dart   заметки о тайтлах профиля
    sync/                         слияние списков и заметок, формат файла Gist, SyncService
    settings/app_preferences.dart первый запуск, 18+, тема, недавние запросы, музыка
    music/                        интерфейс распознавания музыки (этап 4.5, заглушка)
    sources/                      источники видео (YouTube, официальные каналы), фрагмент звука
  app_services.dart               сборка сервисов
  ui/
    theme/                        токены design/tokens.json → ThemeData + AppTokens
    shell/app_shell.dart          NavRail / нижняя навигация, вкладки, Ctrl+K
    catalog/                      каталог: фильтры, сортировка, сетка
    search/                       поиск: debounce 300 мс, подсказки, недавние
    title/                        карточка тайтла, список серий, графики
    settings/                     настройки: аккаунт, 18+, тема, версия
    lists/                        «Мои списки»: сводка, вкладки, сетка/список
    player/                       плеер YouTube (iframe), экран «нет источников»
    profiles/                     профили: аватар, меню, диалоги
    widgets/                      PosterCard, бейджи, скелетоны, состояния
    login_flow.dart               вход через GitHub (заготовка без дизайна)
assets/fonts/                     Unbounded и Golos Text (OFL)
test/                             тесты парсинга, клиента, кэша и репозитория
```

Комментарии (вкладка «Комментарии», только у тайтлов с официальным роликом
YouTube; в плеере — панель под видео): `commentThreads.list` (1 единица
квоты), по популярности или по времени, по 20 с подгрузкой; страницы
хранятся только в памяти до закрытия приложения (в базу не пишутся).
Текст показывается как простой текст, без HTML и активных ссылок; у
каждого комментария — «Открыть на YouTube», внизу — «Комментарии — с YouTube».

Перевод комментариев на русский (design/screens.md §13.1) — только по кнопке
«Перевести на русский» у комментария не на русском (у даты — метка языка,
если он определён); автоперевода нет. Перевод — под комментарием, оригинал
скрыт до «Показать оригинал». Кэш переводов — только на сессию.
- Android и iOS: ML Kit на устройстве (`google_mlkit_translation`,
  `google_mlkit_language_id`): ключ не нужен, текст не уходит с устройства.
  Языковой пакет (≈ 30 МБ) — по кнопке «Скачать пакет перевода», в том
  числе по мобильной сети; ML Kit не сообщает процент, поэтому полоса
  прогресса без числа. iOS — минимум 15.5 (см. `ios/Podfile`).
- Windows: бесплатный MyMemory без регистрации. Перед первым переводом —
  плашка «Текст комментария отправляется на сервер MyMemory для перевода»
  («Понятно» запоминается в настройках). Язык на ПК определяется только по
  алфавиту (латиница — «Autodetect»). Дневной лимит анонимного доступа
  (5000 символов — из памяти, страница лимитов MyMemory отсюда недоступна,
  проверить) считаем сами; при исчерпании — «Лимит перевода исчерпан,
  попробуйте завтра».

Заметки о тайтлах (блок «Моя заметка» между шапкой карточки и вкладками;
редактор — панель справа на ПК, отдельный экран на телефоне): итог до 140
знаков, вердикт, что понравилось, причины бросания (чипы `dropReasons` +
`dropText` своими словами), запомнившиеся моменты (серия, мм:сс, текст).
Сохраняются только по «Сохранить»; при выходе с изменениями — диалог.
Старое поле `dropReason` читается и переносится в `dropText`. Личные,
в профиле; синхронизируются в том же файле Gist (формат v2, поле `notes`),
объединение — по `updatedAt` на заметку.

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
dart run tool/youtube_check.dart "DAN DA DAN"   # почему у тайтла нет видео YouTube (ключ из config/local.json)
```

Настройки сборки передаются через `--dart-define-from-file`, в коде значений
по умолчанию нет. Файлов два:

| Файл | Что внутри | В git |
|---|---|---|
| `config/app.json` | несекретное: `GITHUB_CLIENT_ID` (OAuth App «Anilist Viewer», Device Flow, client secret не нужен) | да |
| `config/local.json` | секреты: `YOUTUBE_API_KEY`, `ACOUSTID_API_KEY` | **нет** (`.gitignore`) |

Один раз создайте локальный файл из примера и впишите ключи:

```
cp config/local.json.example config/local.json
```

Запуск и сборка (VS Code подключает оба файла через `.vscode/launch.json`):

```
# Windows
flutter run -d windows --dart-define-from-file=config/app.json --dart-define-from-file=config/local.json
flutter build windows --release --dart-define-from-file=config/app.json --dart-define-from-file=config/local.json

# iOS (на macOS с Xcode)
flutter run -d ios --dart-define-from-file=config/app.json --dart-define-from-file=config/local.json
flutter build ipa --release --dart-define-from-file=config/app.json --dart-define-from-file=config/local.json

# Android
flutter run -d android --dart-define-from-file=config/app.json --dart-define-from-file=config/local.json
```

Без `GITHUB_CLIENT_ID` приложение работает, но кнопка «Войти через GitHub»
неактивна. Без `YOUTUBE_API_KEY` источник видео пустой: кнопка «Смотреть»
открывает экран «Источники видео не подключены», серии отмечаются вручную.
`ACOUSTID_API_KEY` понадобится для распознавания музыки (этап 4.5).

Плеер YouTube: Android и iOS — WebView (`webview_flutter`), Windows — WebView2
(`webview_windows`, нужен Microsoft Edge WebView2 Runtime, на Windows 11 он
есть). Без WebView2 ролик открывается на youtube.com в браузере.

Скриншоты экранов (golden-рендер в тестах с настоящими шрифтами и
сгенерированными обложками, результат и подписи в `golden/`):

```
flutter test test/screenshots --update-goldens --dart-define=SCREENSHOTS=true
```

После изменения таблиц в `app_database.dart` перегенерируйте код:

```
dart run build_runner build
```
