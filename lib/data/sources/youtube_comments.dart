import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Порядок комментариев: по популярности или по времени.
enum CommentOrder {
  relevance('relevance'),
  time('time');

  const CommentOrder(this.apiValue);

  final String apiValue;
}

/// Комментарий верхнего уровня к ролику YouTube. Текст — простой текст:
/// приложение его не разбирает как HTML и не делает ссылки активными.
class YouTubeComment {
  const YouTubeComment({
    required this.id,
    required this.author,
    required this.text,
    required this.likes,
    required this.publishedAt,
    this.authorAvatar,
    this.replies = 0,
  });

  final String id;
  final String author;
  final String? authorAvatar;
  final String text;
  final int likes;
  final int replies;
  final DateTime publishedAt;

  /// Комментарий на странице ролика.
  Uri urlFor(String videoId) =>
      Uri.https('www.youtube.com', '/watch', {'v': videoId, 'lc': id});
}

/// Страница комментариев и токен следующей.
class CommentsPage {
  const CommentsPage({required this.comments, this.nextPageToken});

  final List<YouTubeComment> comments;
  final String? nextPageToken;

  bool get hasMore => nextPageToken != null;
}

sealed class CommentsResult {
  const CommentsResult();
}

class CommentsLoaded extends CommentsResult {
  const CommentsLoaded(this.page);

  final CommentsPage page;
}

/// Автор отключил комментарии (403 commentsDisabled).
class CommentsDisabled extends CommentsResult {
  const CommentsDisabled();
}

/// Нет ключа API, сети, квоты и т.п.
class CommentsFailed extends CommentsResult {
  const CommentsFailed(this.reason);

  final String reason;
}

/// Комментарии к официальным роликам: YouTube Data API v3
/// `commentThreads.list` (1 единица квоты за запрос). Страницы хранятся
/// только в памяти до закрытия приложения (кэш на сессию): в базу
/// данные YouTube не пишутся.
class YouTubeCommentsClient {
  YouTubeCommentsClient({
    required this.apiKey,
    http.Client? httpClient,
    this.pageSize = 20,
  }) : _http = httpClient ?? http.Client();

  final String apiKey;
  final http.Client _http;
  final int pageSize;
  final _session = <String, Map<String, dynamic>>{};

  bool get isConfigured => apiKey.isNotEmpty;

  Future<CommentsResult> fetch(
    String videoId, {
    CommentOrder order = CommentOrder.relevance,
    String? pageToken,
  }) async {
    if (!isConfigured) return const CommentsFailed('Не задан ключ YouTube');
    final key = 'ytc:$videoId:${order.apiValue}:${pageToken ?? ''}';
    final cached = _session[key];
    if (cached != null) return parse(cached);

    final uri = Uri.https('www.googleapis.com', '/youtube/v3/commentThreads', {
      'part': 'snippet',
      'videoId': videoId,
      'order': order.apiValue,
      'maxResults': '$pageSize',
      'textFormat': 'plainText',
      'pageToken': ?pageToken,
      'key': apiKey,
    });
    final http.Response response;
    try {
      response = await _http.get(uri).timeout(const Duration(seconds: 15));
    } on Object {
      return const CommentsFailed('Нет связи с YouTube');
    }
    Map<String, dynamic>? json;
    try {
      json =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } on Object {
      json = null;
    }
    if (response.statusCode != 200 || json == null) {
      return isCommentsDisabled(json)
          ? const CommentsDisabled()
          : CommentsFailed('YouTube API ${response.statusCode}');
    }
    _session[key] = json;
    return parse(json);
  }

  /// Ответ 403 с причиной `commentsDisabled`.
  static bool isCommentsDisabled(Map<String, dynamic>? json) {
    final errors = (json?['error'] as Map?)?['errors'] as List? ?? const [];
    return errors.any((e) => e is Map && e['reason'] == 'commentsDisabled');
  }

  /// Разбирает ответ `commentThreads.list`.
  static CommentsLoaded parse(Map<String, dynamic> json) {
    final comments = <YouTubeComment>[];
    for (final item in (json['items'] as List? ?? const [])) {
      if (item is! Map) continue;
      final thread = item['snippet'] as Map? ?? const {};
      final top = thread['topLevelComment'] as Map? ?? const {};
      final s = top['snippet'] as Map? ?? const {};
      final published = DateTime.tryParse(s['publishedAt'] as String? ?? '');
      final text = (s['textOriginal'] ?? s['textDisplay']) as String?;
      if (text == null || published == null) continue;
      comments.add(
        YouTubeComment(
          id: (top['id'] ?? item['id']) as String? ?? '',
          author: s['authorDisplayName'] as String? ?? 'Без имени',
          authorAvatar: s['authorProfileImageUrl'] as String?,
          text: text,
          likes: (s['likeCount'] as num?)?.toInt() ?? 0,
          replies: (thread['totalReplyCount'] as num?)?.toInt() ?? 0,
          publishedAt: published.toUtc(),
        ),
      );
    }
    return CommentsLoaded(
      CommentsPage(
        comments: comments,
        nextPageToken: json['nextPageToken'] as String?,
      ),
    );
  }
}
