import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/cache/image_disk_cache.dart';

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
