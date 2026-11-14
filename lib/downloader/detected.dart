import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'common.dart';
import 'hls.dart';
import 'job_runner.dart';
import 'segmented.dart';

/// Sahifada topilgan media turi
enum DetectedKind { video, hls, dash, audio, blob }

/// Brauzer sahifasida topilgan bitta video yoki audio
class DetectedMedia {
  DetectedMedia({required this.url, required this.kind, required this.pageTitle, required this.page, this.mime = ''});

  final Uri url;
  final DetectedKind kind;
  final String pageTitle;
  final Uri page;
  final String mime;

  int? bytes;
  double? seconds;
  String? error; // masalan DRM
  bool hidden = false;
  List<HlsVariant> qualities = const [];
  bool checked = false;

  bool get downloadable => kind != DetectedKind.blob && error == null;

  MediaKind get mediaKind => switch (kind) {
        DetectedKind.hls => MediaKind.hls,
        DetectedKind.dash => MediaKind.dash,
        _ => MediaKind.direct,
      };

  String get typeLabel => switch (kind) {
        DetectedKind.video => "Video",
        DetectedKind.hls => "Video (HLS)",
        DetectedKind.dash => "Video (DASH)",
        DetectedKind.audio => "Audio",
        DetectedKind.blob => "Himoyalangan oqim",
      };
}

/// Sahifa skripti yuborgan xabarlarni to'playdi, takrorlarni olib tashlaydi va ma'lumot qo'shadi.
class MediaDetector extends ChangeNotifier {
  MediaDetector({Future<ProbeResult> Function(Uri, Map<String, String>)? probe, Future<(String, Uri)> Function(Uri, Map<String, String>)? fetch})
      : _probe = probe ?? ((u, h) => probeUrl(u, headers: h)),
        _fetch = fetch ?? ((u, h) => fetchText(u, headers: h));

  final Future<ProbeResult> Function(Uri, Map<String, String>) _probe;
  final Future<(String, Uri)> Function(Uri, Map<String, String>) _fetch;

  /// Sahifa sarlavhalari (Referer, Cookie): saytlar himoyalangan fayllarni faqat shu bilan beradi
  Map<String, String> headers = const {};

  final List<DetectedMedia> _all = [];
  final Set<Uri> _childPlaylists = {};

  /// Foydalanuvchiga ko'rsatiladiganlar
  List<DetectedMedia> get items => _all.where((m) => !m.hidden).toList();
  int get count => items.length;

  void reset() {
    if (_all.isEmpty) return;
    _all.clear();
    _childPlaylists.clear();
    notifyListeners();
  }

  /// JS kanalidan kelgan xabar
  void onMessage(String message) {
    try {
      final data = jsonDecode(message) as Map<String, dynamic>;
      add(
        url: (data['url'] ?? '').toString(),
        mime: (data['type'] ?? '').toString(),
        pageTitle: (data['title'] ?? '').toString(),
        page: (data['page'] ?? '').toString(),
      );
    } catch (_) {}
  }

  DetectedMedia? add({required String url, String mime = '', String pageTitle = '', String page = ''}) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return null;
    final kind = classifyDetected(uri, mime);
    if (kind == null) return null;
    final key = uri.removeFragment();
    if (_all.any((m) => m.url == key)) return null;
    final media = DetectedMedia(url: key, kind: kind, pageTitle: pageTitle, page: Uri.tryParse(page) ?? key, mime: mime);
    if (_childPlaylists.contains(key)) media.hidden = true;
    _all.add(media);
    if (media.kind == DetectedKind.blob) {
      media.checked = true; // blob manzilni tekshirib bo'lmaydi
    } else {
      unawaited(_enrich(media));
    }
    notifyListeners();
    return media;
  }

  /// Qo'lda kiritilgan havolani tekshiradi (ro'yxatga qo'shmaydi). Tur aniqlanmasa null.
  Future<DetectedMedia?> inspect(String url, {String title = ''}) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme) return null;
    var kind = classifyDetected(uri, '');
    if (kind == null) {
      // kengaytmasiz havola: serverning Content-Type'iga qaraymiz
      try {
        final p = await _probe(uri, headers).timeout(const Duration(seconds: 20));
        kind = classifyDetected(p.url, p.contentType ?? '') ?? classifyDetected(uri, p.contentType ?? '');
        if (kind == null) return null;
        final m = DetectedMedia(url: uri, kind: kind, pageTitle: title, page: uri, mime: p.contentType ?? '')..bytes = p.length;
        if (kind == DetectedKind.hls || kind == DetectedKind.dash) await _enrich(m);
        m.checked = true;
        return m;
      } catch (_) {
        return null;
      }
    }
    final m = DetectedMedia(url: uri.removeFragment(), kind: kind, pageTitle: title, page: uri);
    await _enrich(m);
    return m;
  }

  /// Hajm, davomiylik, sifatlar va DRM ni aniqlaydi
  Future<void> _enrich(DetectedMedia m) async {
    try {
      switch (m.kind) {
        case DetectedKind.hls:
          final (text, url) = await _fetch(m.url, headers).timeout(const Duration(seconds: 20));
          final parsed = parseHls(text, url);
          if (parsed is HlsMaster) {
            m.qualities = parsed.byQuality;
            for (final v in parsed.variants) {
              _childPlaylists.add(v.url);
              for (final other in _all.where((o) => o.url == v.url)) {
                other.hidden = true;
              }
            }
          } else if (parsed is HlsMedia) {
            m.seconds = parsed.totalSeconds;
            if (parsed.drmReason != null) m.error = parsed.drmReason;
            if (!parsed.endList) m.error = "Jonli efir";
          }
        case DetectedKind.dash:
          final (text, _) = await _fetch(m.url, headers).timeout(const Duration(seconds: 20));
          try {
            checkDashManifest(text);
          } on DownloadException catch (e) {
            m.error = e.message;
          }
        case DetectedKind.video:
        case DetectedKind.audio:
          final p = await _probe(m.url, headers).timeout(const Duration(seconds: 20));
          m.bytes = p.length;
          // kichik fayllar (reklama, ikonka) odatda kerak emas
          if (p.length != null && p.length! < 30 * 1024) m.hidden = true;
        case DetectedKind.blob:
          break;
      }
    } catch (_) {
      // ma'lumot olinmasa ham element qoladi
    }
    m.checked = true;
    notifyListeners();
  }

  /// Yuklash sarlavhi: sahifa nomi (bo'lmasa fayl nomi)
  String suggestedTitle(DetectedMedia m) {
    final t = m.pageTitle.trim();
    if (t.isNotEmpty) return safeFileName(t);
    final last = m.url.pathSegments.where((s) => s.isNotEmpty).lastOrNull ?? 'video';
    return safeFileName(last.replaceAll(RegExp(r'\.[A-Za-z0-9]{2,5}$'), ''));
  }
}

/// Manzil va tur bo'yicha: video/audio/oqim/himoyalangan. Kerak bo'lmasa null.
DetectedKind? classifyDetected(Uri url, String mime) {
  if (url.scheme == 'blob') return DetectedKind.blob;
  if (url.scheme != 'http' && url.scheme != 'https') return null;
  final path = url.path.toLowerCase();
  final m = mime.toLowerCase();
  if (RegExp(r'\.(ts|m4s|cmfv|cmfa|cmft|vtt|srt|webvtt|jpg|jpeg|png|gif|webp|css|js|json|html|svg|ico)$').hasMatch(path) &&
      !m.contains('video/') &&
      !m.contains('audio/')) {
    return null;
  }
  if (path.endsWith('.m3u8') || m.contains('mpegurl')) return DetectedKind.hls;
  if (path.endsWith('.mpd') || m.contains('dash+xml')) return DetectedKind.dash;
  if (RegExp(r'\.(mp3|m4a|aac|ogg|opus|wav)$').hasMatch(path) || m.startsWith('audio/')) return DetectedKind.audio;
  if (RegExp(r'\.(mp4|m4v|mov|webm|mkv|flv)$').hasMatch(path) || m.startsWith('video/')) return DetectedKind.video;
  return null;
}
