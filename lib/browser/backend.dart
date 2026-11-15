import 'package:flutter/widgets.dart';

import 'webview_backend.dart';

/// Sahifadagi video / audio holati (sahifa skriptidan keladi)
class BrowserMedia {
  final bool playing;
  final bool hasMedia;
  final String title;
  const BrowserMedia({required this.playing, required this.hasMedia, this.title = ""});
}

/// Mini-brauzer dvigateli. Ekran faqat shu interfeysga tayanadi: telefonda WebView, testlarda soxta ob'ekt.
abstract class BrowserBackend {
  void Function(String url)? onPageStarted;
  void Function(String url)? onPageFinished;
  void Function(int percent)? onProgress;

  /// Sahifa skripti (detektor) yuborgan xabar
  void Function(String message)? onMessage;

  /// Sahifadagi video / audio ijro holati o'zgardi
  void Function(BrowserMedia media)? onMedia;

  Widget view();
  Future<void> load(Uri url);
  Future<void> goBack();
  Future<void> goForward();
  Future<void> reload();
  Future<bool> canGoBack();
  Future<bool> canGoForward();
  Future<String?> currentUrl();

  /// Sahifadagi videoni boshqarish: play, pause, toggle, next, previous
  Future<void> mediaCommand(String command);

  /// Ilova fonda: sayt videoni o'zi to'xtatsa, davom ettiriladi
  Future<void> setBackground(bool on);

  /// Yuklashda ishlatiladigan sarlavhalar: Referer, Cookie, User-Agent
  Future<Map<String, String>> requestHeaders(Uri page);

  void dispose();
}

BrowserBackend Function() browserBackendFactory = () => WebViewBackend();
