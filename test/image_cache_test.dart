import 'dart:io';
import 'dart:typed_data';

import 'package:anime_viewer/data/cache/image_disk_cache.dart';
import 'package:anime_viewer/data/models/anime.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late Directory dir;
  late List<Uri> requests;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('img_cache_test');
    requests = [];
  });
  tearDown(() => dir.delete(recursive: true));

  ImageDiskCache cache({int max = 1000, int status = 200}) => ImageDiskCache(
    dir,
    maxBytes: max,
    client: MockClient((r) async {
      requests.add(r.url);
      return http.Response.bytes(
        Uint8List.fromList(List.filled(100, r.url.path.length)),
        status,
      );
    }),
  );

  /// Запись на диск идёт в фоне — ждём, пока в каталоге не останется
  /// временных файлов (до 5 с).
  Future<void> settle() async {
    for (var i = 0; i < 100; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final busy = dir.listSync().any((e) => e.path.endsWith('.part'));
      if (!busy && i > 0) return;
    }
  }

  test('downloads once, then reads from disk (even after restart)', () async {
    final c = cache();
    final a = await c.get('https://img.test/a.jpg');
    expect(a, hasLength(100));
    final f = File(
      '${dir.path}/${ImageDiskCache.fileName('https://img.test/a.jpg')}',
    );
    for (var i = 0; i < 100 && !f.existsSync(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(await cache().get('https://img.test/a.jpg'), a);
    expect(requests, hasLength(1));
  });

  test('parallel requests for one URL share a download', () async {
    final c = cache();
    await Future.wait([
      c.get('https://img.test/a.jpg'),
      c.get('https://img.test/a.jpg'),
    ]);
    expect(requests, hasLength(1));
  });

  test('size limit: least recently used files are evicted', () async {
    final c = cache(max: 350);
    for (var i = 0; i < 3; i++) {
      await c.get('https://img.test/$i.jpg');
      await settle();
      await File(
        '${dir.path}/${ImageDiskCache.fileName('https://img.test/$i.jpg')}',
      ).setLastModified(DateTime(2026, 1, 1 + i));
    }
    await c.get('https://img.test/3.jpg');
    await settle();
    await c.trim();
    expect(await c.size(), lessThanOrEqualTo(350));
    final left = dir.listSync().map((e) => e.uri.pathSegments.last).toSet();
    expect(
      left,
      isNot(contains(ImageDiskCache.fileName('https://img.test/0.jpg'))),
    );
    expect(left, contains(ImageDiskCache.fileName('https://img.test/3.jpg')));
  });

  test('HTTP errors are not cached', () async {
    final c = cache(status: 404);
    await expectLater(
      c.get('https://img.test/x.jpg'),
      throwsA(isA<HttpException>()),
    );
    await settle();
    expect(dir.listSync(), isEmpty);
  });

  test('file names are stable and distinct', () {
    expect(
      ImageDiskCache.fileName('https://a/1.jpg'),
      matches(RegExp(r'^[0-9a-f]{16}\.img$')),
    );
    expect(
      ImageDiskCache.fileName('https://a/1.jpg'),
      ImageDiskCache.fileName('https://a/1.jpg'),
    );
    expect(
      ImageDiskCache.fileName('https://a/1.jpg'),
      isNot(ImageDiskCache.fileName('https://a/2.jpg')),
    );
  });

  test('cover size by width on screen', () {
    const c = CoverImage(medium: 'm', large: 'l', extraLarge: 'xl');
    expect(c.forWidth(90), 'm');
    expect(c.forWidth(200), 'l');
    expect(c.forWidth(440), 'xl');
    expect(c.forWidth(null), 'xl');
    expect(const CoverImage(large: 'l').forWidth(90), 'l');
  });
}
