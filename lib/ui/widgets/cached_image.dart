import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;

import '../../data/cache/image_disk_cache.dart';

/// Картинка из сети через дисковый кэш [ImageDiskCache.instance]
/// (без кэша — просто из сети).
@immutable
class DiskCachedImage extends ImageProvider<DiskCachedImage> {
  const DiskCachedImage(this.url);

  final String url;

  @override
  Future<DiskCachedImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    DiskCachedImage key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(
    codec: _load(decode),
    scale: 1,
    debugLabel: url,
  );

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final cache = ImageDiskCache.instance;
    final Uint8List bytes;
    if (cache != null) {
      bytes = await cache.get(url);
    } else {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode != 200) {
        throw NetworkImageLoadException(
          statusCode: res.statusCode,
          uri: Uri.parse(url),
        );
      }
      bytes = res.bodyBytes;
    }
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  @override
  bool operator ==(Object other) =>
      other is DiskCachedImage && other.url == url;

  @override
  int get hashCode => url.hashCode;

  @override
  String toString() => 'DiskCachedImage("$url")';
}
