import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../config/app_config.dart';
import '../data/cache/image_disk_cache.dart';
import '../data/github/token_store.dart';

/// Веб-сборка — нет.
const isWeb = false;

/// Дисковый кэш обложек: до 200 МБ, старые файлы вытесняются.
Future<void> setUpPlatform() async {
  final cacheDir = await getApplicationCacheDirectory();
  ImageDiskCache.instance = ImageDiskCache(
    Directory(p.join(cacheDir.path, 'images')),
  );
  unawaited(ImageDiskCache.instance!.trim());
}

/// Токен GitHub профиля — в защищённом хранилище платформы.
TokenStore tokenStoreFor(int profileId) =>
    SecureTokenStore(profileId: profileId);

/// Ключ YouTube Data API — из сборки (`config/local.json`).
String youtubeApiKey() => AppConfig.youtubeApiKey;

/// Ключ AcoustID — из сборки.
bool get hasAcoustIdApiKey => AppConfig.hasAcoustIdApiKey;

/// Свой ключ YouTube вводится только в веб-версии.
Future<void> saveYoutubeApiKey(String? key) =>
    throw UnsupportedError('Только веб-версия');

/// Отложенных до перезагрузки тостов в приложении нет.
String? takePendingToast() => null;
