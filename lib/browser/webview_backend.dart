import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import 'dart:convert';

import '../downloader/detector_js.dart';
import '../downloader/media_keepalive_js.dart';
import 'backend.dart';

/// Android va iPhone'dagi haqiqiy WebView
class WebViewBackend extends BrowserBackend {
  WebViewBackend() {
    // iPhone: video sahifa ichida ochilsin va foydalanuvchi bosishini talab qilmasin (pleylistda keyingi video uchun)
    final PlatformWebViewControllerCreationParams params = WebViewPlatform.instance is WebKitWebViewPlatform
        ? WebKitWebViewControllerCreationParams(
            allowsInlineMediaPlayback: true,
            mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
          )
        : const PlatformWebViewControllerCreationParams();
    _controller = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..addJavaScriptChannel('CoreDetector', onMessageReceived: (m) => onMessage?.call(m.message))
      ..addJavaScriptChannel('CoreMedia', onMessageReceived: (m) => _onMediaMessage(m.message))
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (url) {
          onPageStarted?.call(url);
          _inject();
        },
        onProgress: (p) {
          onProgress?.call(p);
          // sahifa yuklanishi davomida skriptni qayta kiritamiz (skript o'zi takrorlanishni to'xtatadi)
          if (p >= 20) _inject();
        },
        onPageFinished: (url) {
          _inject();
          onPageFinished?.call(url);
        },
        onNavigationRequest: (request) {
          // faqat http(s); boshqa ilovalarni ochishga urinishlar bloklanadi
          final scheme = Uri.tryParse(request.url)?.scheme ?? '';
          if (scheme == 'http' || scheme == 'https' || scheme == 'about' || scheme == 'blob') {
            return NavigationDecision.navigate;
          }
          return NavigationDecision.prevent;
        },
      ));
    // Android: keyingi video (pleylist) foydalanuvchi bosishisiz ham o'zi boshlansin
    final platform = _controller.platform;
    if (platform is AndroidWebViewController) {
      platform.setMediaPlaybackRequiresUserGesture(false);
    }
  }

  late final WebViewController _controller;
  bool _background = false;

  void _onMediaMessage(String message) {
    try {
      final data = jsonDecode(message) as Map<String, dynamic>;
      onMedia?.call(BrowserMedia(
        playing: data['playing'] == true,
        hasMedia: data['hasMedia'] == true,
        title: (data['title'] ?? '').toString(),
      ));
    } catch (_) {}
  }

  void _inject() {
    _controller.runJavaScript(detectorScript).catchError((Object _) {});
    _controller.runJavaScript(mediaKeepAliveScript).catchError((Object _) {});
    if (_background) setBackground(true);
  }

  @override
  Future<void> mediaCommand(String command) async {
    const allowed = {'play', 'pause', 'toggle', 'next', 'previous'};
    if (!allowed.contains(command)) return;
    try {
      await _controller.runJavaScript("window.__coreMedia && window.__coreMedia.$command();");
    } catch (_) {}
  }

  @override
  Future<void> setBackground(bool on) async {
    _background = on;
    try {
      await _controller.runJavaScript("window.__coreMedia && window.__coreMedia.setBackground($on);");
    } catch (_) {}
  }

  @override
  Widget view() => WebViewWidget(controller: _controller);

  @override
  Future<void> load(Uri url) => _controller.loadRequest(url);
  @override
  Future<void> goBack() => _controller.goBack();
  @override
  Future<void> goForward() => _controller.goForward();
  @override
  Future<void> reload() => _controller.reload();
  @override
  Future<bool> canGoBack() => _controller.canGoBack();
  @override
  Future<bool> canGoForward() => _controller.canGoForward();
  @override
  Future<String?> currentUrl() => _controller.currentUrl();

  @override
  Future<Map<String, String>> requestHeaders(Uri page) async {
    final headers = <String, String>{'Referer': page.toString()};
    try {
      final ua = await _controller.getUserAgent();
      if (ua != null && ua.isNotEmpty) headers['User-Agent'] = ua;
    } catch (_) {}
    try {
      // HttpOnly bo'lmagan cookie'lar; ko'p saytlar uchun yetarli
      final raw = await _controller.runJavaScriptReturningResult('document.cookie');
      var cookie = raw.toString();
      if (cookie.length >= 2 && cookie.startsWith('"') && cookie.endsWith('"')) {
        cookie = cookie.substring(1, cookie.length - 1);
      }
      if (cookie.isNotEmpty && cookie != 'null') headers['Cookie'] = cookie;
    } catch (_) {}
    return headers;
  }

  @override
  void dispose() {}
}
