#!/bin/bash

# Запуск скрипта для извлечения ссылок на видео
node tool/extract_video_links.js > tool/video_links.txt

# Сборка Flutter приложения
flutter build web

# Копирование собранного приложения в папку docs/app/
cp -r build/web/* docs/app/

# Добавление ссылок на видео в index.html
sed -i '/<\/body>/i <script src="/video_links.js"></script>' docs/app/index.html

# Проверка на наличие ключей
grep -rl '\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b' docs/app/ | while read file; do
  echo "Ключ найден в файле: $file"
  exit 1
done
