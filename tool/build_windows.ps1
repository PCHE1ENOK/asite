<#
.SYNOPSIS
  Собирает Anime Viewer для Windows в dist\AnimeViewer\ и создаёт ярлык
  «AnimeViewer» на рабочем столе.

.DESCRIPTION
  Запуск из корня проекта (папка с pubspec.yaml):

    powershell -ExecutionPolicy Bypass -File tool\build_windows.ps1

  Что делает:
    1. Проверяет, что есть flutter, config\app.json и config\local.json.
    2. flutter pub get
    3. flutter build windows --release с ключами из обоих файлов
       (--dart-define-from-file).
    4. Копирует build\windows\x64\runner\Release\ целиком (exe и DLL рядом)
       в dist\AnimeViewer\.
    5. Создаёт на рабочем столе ярлык «AnimeViewer» на
       dist\AnimeViewer\anime_viewer.exe. Флаги в ярлыке не нужны: они уже
       вшиты в exe при сборке.

  ВНИМАНИЕ: exe содержит ключ YouTube (и другие ключи) из config\local.json —
  он вшивается при сборке. Папку dist\ нельзя передавать другим людям,
  выкладывать в интернет или в git (dist/ в .gitignore).

.PARAMETER NoShortcut
  Не создавать ярлык на рабочем столе.
#>
param(
  [switch]$NoShortcut
)

$ErrorActionPreference = 'Stop'

function Fail([string]$message) {
  Write-Host ''
  Write-Host "ОШИБКА: $message" -ForegroundColor Red
  exit 1
}

# Корень проекта — родитель папки tool\, где лежит этот скрипт.
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
Write-Host "Проект: $root"

# 1. Проверки.
if (-not (Test-Path (Join-Path $root 'pubspec.yaml'))) {
  Fail 'Не найден pubspec.yaml. Скрипт должен лежать в папке tool\ проекта.'
}
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  Fail 'Не найден flutter. Установите Flutter и добавьте его папку bin в PATH.'
}
$appJson = Join-Path $root 'config\app.json'
$localJson = Join-Path $root 'config\local.json'
if (-not (Test-Path $appJson)) {
  Fail 'Не найден config\app.json (он есть в репозитории — обновите код: git pull).'
}
if (-not (Test-Path $localJson)) {
  Fail ('Не найден config\local.json. Скопируйте config\local.json.example ' +
    'в config\local.json и впишите свои ключи (YOUTUBE_API_KEY и другие).')
}

# 2. Зависимости.
Write-Host ''
Write-Host '== flutter pub get'
& flutter pub get
if ($LASTEXITCODE -ne 0) { Fail 'flutter pub get завершился с ошибкой.' }

# 3. Сборка.
Write-Host ''
Write-Host '== flutter build windows --release'
& flutter build windows --release `
  '--dart-define-from-file=config/app.json' `
  '--dart-define-from-file=config/local.json'
if ($LASTEXITCODE -ne 0) { Fail 'Сборка не удалась (сообщения flutter выше).' }

$release = Join-Path $root 'build\windows\x64\runner\Release'
$exeName = 'anime_viewer.exe'
if (-not (Test-Path (Join-Path $release $exeName))) {
  Fail "Сборка прошла, но не найден $release\$exeName."
}

# 4. Копия в dist\AnimeViewer\ (папка целиком: exe работает только с DLL
# и папкой data рядом).
$dist = Join-Path $root 'dist\AnimeViewer'
Write-Host ''
Write-Host "== Копирую в $dist"
if (Test-Path $dist) {
  try {
    Remove-Item -Recurse -Force $dist
  } catch {
    Fail 'Не удалось очистить dist\AnimeViewer. Закройте запущенный AnimeViewer и повторите.'
  }
}
New-Item -ItemType Directory -Force -Path $dist | Out-Null
Copy-Item -Path (Join-Path $release '*') -Destination $dist -Recurse -Force
$exe = Join-Path $dist $exeName

# 5. Ярлык на рабочем столе (без флагов: ключи уже в exe).
if (-not $NoShortcut) {
  $desktop = [Environment]::GetFolderPath('Desktop')
  $lnk = Join-Path $desktop 'AnimeViewer.lnk'
  $shell = New-Object -ComObject WScript.Shell
  $shortcut = $shell.CreateShortcut($lnk)
  $shortcut.TargetPath = $exe
  $shortcut.WorkingDirectory = $dist
  $shortcut.IconLocation = "$exe,0"
  $shortcut.Description = 'Anime Viewer'
  $shortcut.Save()
  Write-Host "== Ярлык: $lnk"
}

Write-Host ''
Write-Host "Готово: $exe" -ForegroundColor Green
Write-Host ('ВНИМАНИЕ: в exe вшит ключ YouTube из config\local.json. ' +
  'Не передавайте папку dist\ другим людям и не выкладывайте её.') -ForegroundColor Yellow
