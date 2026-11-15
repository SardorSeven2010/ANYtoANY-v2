import 'package:any_to_any/browser/backend.dart';
import 'package:flutter/material.dart';

/// WebView o'rniga testlarda ishlatiladigan soxta brauzer
class FakeBrowser extends BrowserBackend {
  final List<Uri> loaded = [];
  final List<String> history = [];
  int index = -1;
  bool reloaded = false;
  final List<String> commands = [];
  bool background = false;

  @override
  Widget view() => const ColoredBox(key: Key('fakeWebView'), color: Colors.white);

  /// Sahifa yuklanishini taqlid qiladi
  void navigate(String url) {
    history.removeRange(index + 1, history.length);
    history.add(url);
    index = history.length - 1;
    onPageStarted?.call(url);
    onProgress?.call(100);
    onPageFinished?.call(url);
  }

  @override
  Future<void> load(Uri url) async {
    loaded.add(url);
    navigate(url.toString());
  }

  @override
  Future<void> goBack() async {
    if (index > 0) {
      index--;
      onPageStarted?.call(history[index]);
      onPageFinished?.call(history[index]);
    }
  }

  @override
  Future<void> goForward() async {
    if (index < history.length - 1) {
      index++;
      onPageStarted?.call(history[index]);
      onPageFinished?.call(history[index]);
    }
  }

  @override
  Future<void> reload() async => reloaded = true;
  @override
  Future<bool> canGoBack() async => index > 0;
  @override
  Future<bool> canGoForward() async => index < history.length - 1;
  @override
  Future<void> mediaCommand(String command) async => commands.add(command);

  @override
  Future<void> setBackground(bool on) async => background = on;

  bool desktop = false;
  final List<bool> desktopChanges = [];

  @override
  bool get desktopMode => desktop;

  @override
  Future<void> setDesktopMode(bool on) async {
    desktop = on;
    desktopChanges.add(on);
  }

  @override
  int? get nativeWebViewId => 7;

  /// Sahifadagi video holatini taqlid qiladi
  void media({required bool playing, bool hasMedia = true, String title = ''}) =>
      onMedia?.call(BrowserMedia(playing: playing, hasMedia: hasMedia, title: title));

  @override
  Future<String?> currentUrl() async => index >= 0 ? history[index] : null;

  @override
  Future<Map<String, String>> requestHeaders(Uri page) async => {'Referer': page.toString(), 'Cookie': 'sid=42', 'User-Agent': 'FakeUA'};

  @override
  void dispose() {}
}
