import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:webview_windows/webview_windows.dart';

import 'youtube_embed.dart';

/// Официальный плеер YouTube в WebView2 (Windows). Страница с iframe
/// отдаётся с виртуального хоста [playerHost]. Если WebView2 Runtime нет
/// или он не запустился, показывается [fallback] (открыть на youtube.com).
class WindowsYouTubePlayer extends StatefulWidget {
  const WindowsYouTubePlayer({
    super.key,
    required this.videoId,
    required this.fallback,
  });

  final String videoId;
  final Widget fallback;

  @override
  State<WindowsYouTubePlayer> createState() => _WindowsYouTubePlayerState();
}

class _WindowsYouTubePlayerState extends State<WindowsYouTubePlayer> {
  final _controller = WebviewController();
  bool _ready = false;
  bool _failed = false;

  /// `dispose()` контроллера падает, если `initialize()` не вызывался
  /// (например, нет WebView2 Runtime).
  bool _initStarted = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      if (await WebviewController.getWebViewVersion() == null) {
        throw StateError('WebView2 Runtime не установлен');
      }
      final dir = Directory(
        p.join((await getTemporaryDirectory()).path, 'youtube_player'),
      );
      await dir.create(recursive: true);
      await File(p.join(dir.path, 'index.html'))
          .writeAsString(youtubePlayerHtml(widget.videoId));

      _initStarted = true;
      await _controller.initialize();
      await _controller.addVirtualHostNameMapping(
        playerHost,
        dir.path,
        WebviewHostResourceAccessKind.allow,
      );
      // Ссылки «Смотреть на YouTube» внутри плеера не открывают окна.
      await _controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);
      await _controller.loadUrl('$playerOrigin/index.html');
      if (mounted) setState(() => _ready = true);
    } on Object {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    if (_initStarted) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return widget.fallback;
    if (!_ready) return const Center(child: CircularProgressIndicator());
    return Center(
      child: AspectRatio(aspectRatio: 16 / 9, child: Webview(_controller)),
    );
  }
}
