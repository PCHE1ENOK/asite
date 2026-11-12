#!/usr/bin/env bash
# Собирает веб-версию Anime Viewer в docs/app/ (GitHub Pages:
# https://pche1enok.github.io/asite/app/).
#
#   bash tool/build_web.sh            # сборка и проверка
#   BASE_HREF=/ bash tool/build_web.sh  # для локального сервера
#
# Ключей в сборке нет: страница публичная. config/local.json и
# --dart-define-from-file не используются; ключ YouTube пользователь
# вводит сам в настройках (хранится в его браузере). Если в собранных
# файлах найдётся что-то похожее на ключ или токен — сборка
# останавливается и docs/app/ не меняется.
set -euo pipefail
cd "$(dirname "$0")/.."

BASE_HREF="${BASE_HREF:-/asite/app/}"
OUT=docs/app

# Воркер базы — той же версией drift, что и приложение.
dart compile js -O4 -o web/drift_worker.js tool/web/drift_worker.dart
rm -f web/drift_worker.js.deps web/drift_worker.js.map
sed -i '/sourceMappingURL/d' web/drift_worker.js

flutter pub get
# CanvasKit грузится с gstatic.com (CDN Flutter): в репозитории его нет.
flutter build web --release --base-href "$BASE_HREF" --no-wasm-dry-run

# Отладочные символы и неиспользуемый с CDN CanvasKit — не публикуем.
find build/web -name '*.symbols' -delete
rm -rf build/web/canvaskit build/web/.last_build_id

# Нет ли в сборке ключей и токенов.
pattern='AIza[0-9A-Za-z_-]{35}|gh[pousr]_[0-9A-Za-z]{36}|github_pat_[0-9A-Za-z_]{40,}'
if grep -rEoq "$pattern" build/web; then
  echo 'ОСТАНОВЛЕНО: в сборке найден ключ или токен:' >&2
  grep -rEo "$pattern" build/web | sed -E 's/(.{12}).*/\1…/' >&2
  exit 1
fi
if [ -f config/local.json ]; then
  # Каждое значение из local.json не должно попасть в сборку.
  for v in $(grep -oE '"[^"]{12,}"\s*$|:\s*"[^"]{12,}"' config/local.json \
      | grep -oE '"[^"]+"' | tr -d '"'); do
    if grep -rqF -- "$v" build/web; then
      echo "ОСТАНОВЛЕНО: значение из config/local.json есть в сборке" >&2
      exit 1
    fi
  done
fi

rm -rf "$OUT"
mkdir -p "$OUT"
cp -r build/web/. "$OUT/"
echo "Готово: $OUT ($(du -sh "$OUT" | cut -f1)), ключей нет."
