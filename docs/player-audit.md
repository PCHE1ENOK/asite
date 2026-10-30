# Аудит кода плеера (приложение, не дизайн)

Дата: 2026-10-30. Ветка `claude/anime-viewer-app-86n4mk`.

В приложении нет своего видеоплеера (mpv): этап 4 ждёт источника, этап 6
сделан через официальные ролики YouTube. Поэтому «плеер» сейчас — это
экран официального плеера YouTube (`YouTubePlayerScreen`), экран
«Источники видео не подключены» (`NoSourcesScreen`) и кнопки запуска на
карточке тайтла. Тесты — виджет-тесты на поддельных данных; реальные
WebView, WebView2 и YouTube в контейнере не запускались.

Статусы: **работает** — есть обработчик и тест проверяет результат;
**исправлено** — было сломано, тест сначала падал, теперь проходит;
**добавлено** — элемента не было, сделан по дизайну §11, есть тест;
**не проверено** — обработчик есть, но проверить без устройства нельзя;
**нет** — элемент из дизайна в коде отсутствует.

## Элементы

| # | Элемент | Файл:строка | Что вызывает | Тест | Статус | Что сделано |
|---|---|---|---|---|---|---|
| 1 | «Начать просмотр» / «Смотреть серию N» / «… на YouTube» в шапке тайтла | `lib/ui/title/title_screen.dart:450` (обработчик `:163`) | `_play` → `YouTubePlayerScreen` или `NoSourcesScreen` | `player_sources_test`, `player_audit_test` | работает | — (см. проблему П1) |
| 2 | Кнопка YouTube у серии | `lib/ui/title/title_screen.dart:609` (`:329`) | `_play(d, n)` для этой серии | `player_audit_test` «YouTube button on an episode row» | работает | добавлен тест нажатия |
| 3 | Отметка серии в списке серий (кружок/галочка) | `lib/ui/title/title_screen.dart` `_EpisodeRow` | `toggleEpisodeWatched`, тост «Отменить» | `lists_and_status_test` | работает | — |
| 4 | «Отметить серию N просмотренной» (нет источников) | `lib/ui/player/no_sources_screen.dart:82` | `toggleEpisodeWatched` | `player_sources_test` | работает | — |
| 5 | «Вернуться к тайтлу» | `lib/ui/player/no_sources_screen.dart:99` | `Navigator.pop` | `player_sources_test` | работает | — |
| 6 | «Открыть на YouTube» (верхняя панель плеера) | `lib/ui/player/youtube_player_screen.dart:135` | `openExternally(watchUrl)` | `player_audit_test` (успех и ошибка) | исправлено | результат `launchUrl` игнорировался: если браузер не открылся, кнопка «ничего не делала». Теперь — сообщение «Не удалось открыть YouTube» |
| 7 | «Смотреть на YouTube» (нет WebView/WebView2) | `lib/ui/player/youtube_player_screen.dart:255` | `openExternally(watchUrl)` | `player_audit_test` | исправлено | то же, что п. 6 |
| 8 | «Отметить серию N просмотренной» под плеером YouTube | `lib/ui/player/youtube_player_screen.dart:171` | `toggleEpisodeWatched` | `player_audit_test` «mark watched» | работает | добавлен тест |
| 9 | Кнопка полного экрана iframe YouTube | `lib/ui/player/youtube_embed.dart:45` | — | `youtube_embed_test` (`fs=0`) | исправлено | в WebView (Android) и WebView2 полноэкранный режим iframe не работает без поддержки приложения — кнопка была нерабочей. Скрыта (`fs=0`, как в дизайне §11) |
| 10 | «Полный экран» (наш) | `lib/ui/player/youtube_player_screen.dart:141` | `_setFullscreen(true)`: прячет панели, на телефоне — immersive | `player_audit_test` «fullscreen» | добавлено | раньше не было |
| 11 | Клавиша F | `lib/ui/player/youtube_player_screen.dart:81` | переключает полный экран, по физической клавише | `player_audit_test` | добавлено | работает и на русской раскладке |
| 12 | Esc | `lib/ui/player/youtube_player_screen.dart:85` | выход из полного экрана | `player_audit_test` | добавлено | — |
| 13 | «Назад» (жест/кнопка) в полном экране | `lib/ui/player/youtube_player_screen.dart:96` | `PopScope`: сначала выход из полного экрана | — | не проверено | системный жест «назад» в тестах не эмулировался |
| 14 | Панели не перекрывают iframe | `lib/ui/player/youtube_player_screen.dart:154` | `Column`: панель / видео 16:9 / кнопка | `player_audit_test` «controls sit above and below» | работает | — |
| 15 | Встроенный плеер WebView2 (Windows) и переход в браузер без него | `lib/ui/player/windows_youtube_player.dart:44`, `:66` | WebView2 или `fallback` | `player_sources_test`, `player_audit_test` (fallback) | не проверено | переход в браузер проверен; сам WebView2 — только на Windows |
| 16 | Встроенный плеер WebView (Android/iOS) | `lib/ui/player/youtube_player_screen.dart:202` | `loadHtmlString` с iframe | — | не проверено | WebView в тестах не запускается |
| 17 | Кнопки внутри iframe (пауза, перемотка, громкость, субтитры) | плеер YouTube | обрабатывает YouTube | — | не проверено | принадлежат YouTube, приложение их не трогает |

## Проблемы, которые остались (перечислены, не исправлены)

| # | Проблема | Где | Почему не исправлено |
|---|---|---|---|
| П1 | Кнопка «Начать просмотр» неактивна, пока не загрузились подробности тайтла, и остаётся неактивной, если они не загрузились (нет сети, нет кэша) | `title_screen.dart:163` | нужно решение: открывать ли экран §10 без данных о сериях; под ошибкой уже есть «Повторить» |
| П2 | Windows: клик по логотипу/ссылкам YouTube внутри iframe ничего не делает (всплывающие окна запрещены) | `windows_youtube_player.dart:62` | `webview_windows` не отдаёт адрес нового окна; для перехода есть наша кнопка «Открыть на YouTube» |
| П3 | Android/iOS: ссылки внутри iframe открывают youtube.com прямо в WebView, плеер пропадает до «Назад» | `youtube_player_screen.dart:202` | нужен `NavigationDelegate` с открытием во внешнем браузере — сделать вместе с IFrame API |
| П4 | На Windows «Полный экран» прячет панели приложения, но окно не разворачивается на весь экран | `youtube_player_screen.dart` `_setFullscreen` | нужен `window_manager` (дизайн §4) — отдельная задача |

## Нет в коде (дизайн §11, режим официального видео YouTube)

- Кнопка «Серии» и панель серий с метками «YouTube» / «нет видео».
- «Серия N+1» в нижней панели и переход по окончании (событие ENDED, отсчёт, «Остаться»).
- Автоотметка «просмотрено» на 85% (`getCurrentTime` / `getDuration` через IFrame API).
- Карточки ошибок плеера вместо iframe: 100 «Видео удалено», 101/150 «Недоступно в вашем регионе», «Повторить».
- «Официального видео для серии N нет» внутри плеера (сейчас без видео открывается экран §10).

Для всего этого нужен мост к YouTube IFrame API (JavaScript-канал в WebView
и WebView2) — это следующая задача, а не исправление существующих кнопок.

## Проверка

`flutter analyze` — без замечаний; `flutter test` — все тесты проходят.
Тесты, которые сначала падали на старом коде: `youtube_embed_test`
(`fs=0`), `player_audit_test` «failed browser launch is reported»,
`player_audit_test` «fullscreen: button, F and Esc».
