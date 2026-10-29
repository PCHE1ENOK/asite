import 'package:anime_viewer/data/github/github_auth.dart';
import 'package:anime_viewer/data/github/github_exception.dart';
import 'package:flutter_test/flutter_test.dart';

import 'github_fakes.dart';

void main() {
  late FakeGitHub github;
  late List<Duration> delays;
  late GitHubAuth auth;

  setUp(() {
    github = FakeGitHub();
    delays = [];
    auth = GitHubAuth(
      clientId: 'client',
      httpClient: github.client,
      delay: (d) async => delays.add(d),
    );
  });

  test('requests a device code', () async {
    final code = await auth.requestCode();
    expect(code.userCode, 'ABCD-1234');
    expect(code.verificationUri.toString(), 'https://github.com/login/device');
    expect(code.interval, const Duration(seconds: 5));
  });

  test('polls until the user confirms', () async {
    github.pendingPolls = 2;
    final token = await auth.waitForToken(await auth.requestCode());
    expect(token, 'tok');
    expect(delays, hasLength(3));
  });

  test('maps expired and denied errors', () async {
    final code = await auth.requestCode();
    github.tokenError = 'expired_token';
    await expectLater(
      auth.waitForToken(code),
      throwsA(
        isA<GitHubException>().having(
          (e) => e.kind,
          'kind',
          GitHubErrorKind.expired,
        ),
      ),
    );
    github.tokenError = 'access_denied';
    await expectLater(
      auth.waitForToken(code),
      throwsA(
        isA<GitHubException>().having(
          (e) => e.kind,
          'kind',
          GitHubErrorKind.denied,
        ),
      ),
    );
  });

  test('cancellation stops polling', () async {
    github.pendingPolls = 100;
    var polls = 0;
    await expectLater(
      auth.waitForToken(
        await auth.requestCode(),
        isCancelled: () => ++polls > 2,
      ),
      throwsA(
        isA<GitHubException>().having(
          (e) => e.kind,
          'kind',
          GitHubErrorKind.cancelled,
        ),
      ),
    );
  });

  test('network errors are reported as network', () async {
    github.offline = true;
    await expectLater(
      auth.requestCode(),
      throwsA(
        isA<GitHubException>().having(
          (e) => e.kind,
          'kind',
          GitHubErrorKind.network,
        ),
      ),
    );
  });
}
