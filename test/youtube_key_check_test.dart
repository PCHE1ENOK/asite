import 'package:anime_viewer/data/sources/youtube_key_check.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  Future<YouTubeKeyCheck> check(String key, http.Response response) {
    Uri? sent;
    final r = checkYouTubeKey(
      key,
      client: MockClient((req) async {
        sent = req.url;
        return response;
      }),
    );
    return r.then((v) {
      if (key.trim().isNotEmpty) {
        expect(sent!.path, '/youtube/v3/i18nLanguages');
        expect(sent!.queryParameters['key'], key.trim());
      }
      return v;
    });
  }

  test('one test request decides the result', () async {
    expect(await check('', http.Response('', 200)), YouTubeKeyCheck.empty);
    expect(
      await check(' AIzaGood ', http.Response('{"items":[]}', 200)),
      YouTubeKeyCheck.ok,
    );
    expect(
      await check(
        'AIzaBad',
        http.Response(
          '{"error":{"code":400,"message":"API key not valid.",'
          '"errors":[{"reason":"keyInvalid"}]}}',
          400,
        ),
      ),
      YouTubeKeyCheck.invalid,
    );
    expect(
      await check(
        'AIzaOff',
        http.Response(
          '{"error":{"code":403,"errors":[{"reason":"accessNotConfigured"}]}}',
          403,
        ),
      ),
      YouTubeKeyCheck.notEnabled,
    );
    expect(
      await check('AIzaX', http.Response('oops', 500)),
      YouTubeKeyCheck.failed,
    );
  });

  test('mask shows only the first and last 4 characters', () {
    expect(maskKey('AIzaSyA1234567890abcdefghijklmnoprsXY'), 'AIza…rsXY');
    expect(maskKey('short'), '…');
  });
}
