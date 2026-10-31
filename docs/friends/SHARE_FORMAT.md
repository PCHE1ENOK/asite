# Формат `share.json` (каталог для друзей), версия 1

Страница просмотра: `docs/friends/index.html` (GitHub Pages),
адрес `https://pche1enok.github.io/asite/friends/?g=<id Gist>`.

Приложение («Настройки → Аккаунт профиля → Поделиться каталогом») создаёт
**секретный** Gist (`public: false`: не виден в списках и поиске GitHub,
но открывается любым, у кого есть ссылка) с единственным файлом
`share.json`. Страница загружает его без входа:
`GET https://api.github.com/gists/<id>` → `files["share.json"]`
(если `truncated` — по `raw_url`).

- Обновление: после каждой синхронизации, если данные менялись, но не
  чаще раза в 5 минут.
- «Прекратить показ» удаляет Gist — ссылка перестаёт работать.
- Приватный Gist синхронизации (`anime-viewer-library.json`) — отдельный,
  в `share.json` из него ничего не копируется, кроме данных каталога.

## Что в файле нет никогда

Токен GitHub, Client ID, ключи API (YouTube, AcoustID), логин GitHub,
id приватного Gist синхронизации, пути и настройки устройства. Код,
собирающий файл (`lib/data/share/share_codec.dart`), эти данные не
получает; тест `test/share_test.dart` это проверяет.

## Поля

```json
{
  "version": 1,
  "owner": "Основной",
  "updatedAt": "2026-10-31T12:30:00.000Z",
  "titles": [
    {
      "id": 171018,
      "title": { "ru": "Дандадан", "en": "DAN DA DAN", "romaji": "Dandadan" },
      "cover": "https://s4.anilist.co/…",
      "coverColor": "#7a2e4a",
      "format": "TV",
      "year": 2024,
      "episodes": 12,
      "score": { "value": 8.4, "source": "shikimori" },
      "status": "CURRENT",
      "progress": 5,
      "favorite": true,
      "adult": false,
      "updatedAt": "2026-10-31T10:00:00.000Z",
      "note": {
        "verdict": "recommend",
        "summary": "…",
        "liked": "…",
        "dropReasons": ["Затянуто"],
        "dropText": "…",
        "moments": [{ "episode": 1, "time": "05:12", "text": "…" }]
      }
    }
  ]
}
```

| Поле | Тип | Обязательно | Что это |
|---|---|---|---|
| `version` | число | да | версия формата, сейчас `1`; новые версии только добавляют поля |
| `owner` | строка | да | имя профиля в приложении (не логин GitHub) |
| `updatedAt` | ISO 8601, UTC | да | когда файл собран |
| `titles` | массив | да | все тайтлы профиля: из списков, «Понравилось» и заметок |
| `titles[].id` | число | да | id AniList |
| `title.ru` | строка | нет | русское название (Shikimori) |
| `title.en`, `title.romaji` | строка | нет | названия AniList |
| `cover` | https-URL | нет | обложка AniList (large) |
| `coverColor` | `#rrggbb` | нет | средний цвет обложки |
| `format` | строка | нет | `TV`, `MOVIE`, `OVA`, … (AniList) |
| `year` | число | нет | год сезона |
| `episodes` | число | нет | число серий |
| `score.value` | число 0–10, 1 знак | нет | оценка: Shikimori, если есть и не 0, иначе AniList / 10 |
| `score.source` | `shikimori` \| `anilist` | при `score` | источник оценки |
| `status` | `CURRENT` \| `PLANNING` \| `COMPLETED` \| `DROPPED` \| `PAUSED` \| `REPEATING` | нет | статус в списках; нет — тайтл только в «Понравилось» или с заметкой |
| `progress` | число | при `status` | просмотрено серий |
| `favorite` | bool | да | «Понравилось» (независимо от статуса) |
| `adult` | bool | да | 18+ (показывается с меткой, не скрывается) |
| `updatedAt` | ISO 8601, UTC | нет | последнее изменение статуса, отметки или заметки |
| `trailer` | https-URL YouTube | нет | зарезервировано, в версии 1 приложение его пока не пишет |
| `note.verdict` | `rewatch` \| `recommend` \| `not` \| `none` | при `note` | вердикт заметки |
| `note.summary` | строка ≤ 140 | нет | итог |
| `note.liked` | строка | нет | что понравилось |
| `note.dropReasons` | массив строк | нет | причины бросания (чипы) |
| `note.dropText` | строка | нет | причина своими словами |
| `note.moments[]` | `{episode, time?, text}` | нет | моменты; `time` — «мм:сс» или «ч:мм:сс» |

Страница игнорирует неизвестные поля и пропускает битые записи; все
тексты выводит как текст (не HTML).
