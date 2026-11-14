import 'dart:async';

import 'native_bridge.dart';

/// Pleyerda ijro etilayotgan narsa haqida qisqa ma'lumot (bildirishnoma uchun)
class MediaInfo {
  final String title;
  final String subtitle;
  final bool playing;
  const MediaInfo({required this.title, this.subtitle = "", required this.playing});
}

/// Faol yuklashlar xulosasi (bildirishnoma uchun)
class DownloadSummary {
  final int active;
  final int progress; // 0..100, noma'lum bo'lsa -1
  final String title;
  const DownloadSummary({required this.active, required this.progress, this.title = ""});
}

/// Fon xizmatini boshqaradi: ijro yoki yuklash bor ekan, ilova fonda to'xtab qolmaydi.
/// Pleyer ustuvor; ikkalasi ham bo'lmasa xizmat o'chiriladi.
class BackgroundCoordinator {
  BackgroundCoordinator(this._bridge);
  final NativeBridge _bridge;

  MediaInfo? _media;
  DownloadSummary? _downloads;
  bool _running = false;
  String _lastKey = "";

  bool get running => _running;

  void setMedia(MediaInfo? media) {
    _media = media;
    unawaited(_apply());
  }

  void setDownloads(DownloadSummary? downloads) {
    _downloads = (downloads == null || downloads.active <= 0) ? null : downloads;
    unawaited(_apply());
  }

  Future<void> _apply() async {
    final media = _media;
    final downloads = _downloads;
    if (media == null && downloads == null) {
      if (_running) {
        _running = false;
        _lastKey = "";
        await _bridge.stopForeground();
      }
      return;
    }
    final String kind;
    final String title;
    final String text;
    final int progress;
    final bool playing;
    if (media != null) {
      kind = "media";
      title = media.title;
      text = media.subtitle;
      progress = -1;
      playing = media.playing;
    } else {
      kind = "download";
      title = downloads!.active == 1 ? "Yuklanmoqda" : "Yuklanmoqda: ${downloads.active} ta";
      text = downloads.title;
      progress = downloads.progress;
      playing = false;
    }
    final key = "$kind|$title|$text|$progress|$playing";
    if (key == _lastKey) return;
    _lastKey = key;
    _running = await _bridge.showForeground(kind: kind, title: title, text: text, progress: progress, playing: playing);
  }
}
