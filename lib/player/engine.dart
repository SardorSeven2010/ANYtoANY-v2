import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../platform.dart';

/// Video dekoderi: apparat (GPU/chip), dasturiy (protsessor) yoki avtomatik
enum DecoderMode {
  auto("Avtomatik", "Tizim o'zi eng yaxshisini tanlaydi (tavsiya etiladi)"),
  hardware("Apparat (HW)", "Videochip dekoderi: tez va quvvatni tejaydi"),
  hardwareCopy("Apparat + nusxa (HW+)", "Apparat dekoderi, ayrim qurilmalarda barqarorroq"),
  software("Dasturiy (SW)", "Protsessor: eng ko'p formatni ochadi, lekin ko'proq quvvat sarflaydi");

  final String label;
  final String hint;
  const DecoderMode(this.label, this.hint);
}

/// mpv'ning `hwdec` qiymati (platformaga qarab)
String hwdecValue(DecoderMode mode) {
  switch (mode) {
    case DecoderMode.auto:
      // Android'da "mediacodec-copy" ko'p telefonlarda zero-copy "mediacodec" ga qaraganda barqaror
      // (ayniqsa H.265 / HEVC da qora ekran chiqmaydi); muvaffaqiyatsiz bo'lsa mpv o'zi dasturiyga o'tadi.
      return isAndroidApp ? 'mediacodec-copy' : 'auto-safe';
    case DecoderMode.hardware:
      return isAndroidApp ? 'mediacodec' : 'auto';
    case DecoderMode.hardwareCopy:
      return isAndroidApp ? 'mediacodec-copy' : 'auto-copy';
    case DecoderMode.software:
      return 'no';
  }
}

/// Ijro dvigateli. Pleyer ekrani va boshqaruvi faqat shu interfeysga tayanadi:
/// haqiqiy dvigatel media_kit (libmpv), testlarda soxta dvigatel.
abstract class PlayerEngine {
  bool get playing;
  Duration get position;
  Duration get duration;
  int? get videoWidth;
  int? get videoHeight;

  Stream<bool> get playingStream;
  Stream<Duration> get positionStream;
  Stream<Duration> get durationStream;
  Stream<bool> get completedStream;
  Stream<String> get errorStream;
  Stream<({int? width, int? height})> get videoSizeStream;

  /// Faylni ochadi. [start] - boshlanadigan joy, [play] - darhol ijro.
  Future<void> open(String source, {Duration start = Duration.zero, bool play = true});
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setRate(double rate);
  Future<void> setVolume(double percent);
  Future<void> setDecoder(DecoderMode mode);

  /// Hozir ishlatilayotgan dekoder nomi (aniqlab bo'lmasa null)
  Future<String?> activeDecoder();

  /// Joriy kadrning PNG rasmi (bo'lmasa null)
  Future<Uint8List?> screenshot();

  /// Videoni chizadigan vidjet
  Widget buildVideo({BoxFit fit = BoxFit.contain});

  Future<void> dispose();
}

/// Yaratish funksiyasi: testlarda almashtiriladi
PlayerEngine Function() playerEngineFactory = () => MediaKitEngine();

bool _mediaKitReady = false;

/// media_kit'ni bir marta ishga tushiradi. Xato bo'lsa (masalan, libmpv topilmasa) istisno tashlaydi.
void ensureMediaKit() {
  if (_mediaKitReady) return;
  MediaKit.ensureInitialized();
  _mediaKitReady = true;
}

class MediaKitEngine implements PlayerEngine {
  MediaKitEngine({PlayerConfiguration configuration = const PlayerConfiguration()}) {
    ensureMediaKit();
    _player = Player(configuration: configuration);
  }

  late final Player _player;
  VideoController? _video;
  bool _disposed = false;

  Player get player => _player;

  VideoController get _videoController =>
      _video ??= VideoController(_player, configuration: VideoControllerConfiguration(hwdec: hwdecValue(DecoderMode.auto)));

  @override
  bool get playing => _player.state.playing;
  @override
  Duration get position => _player.state.position;
  @override
  Duration get duration => _player.state.duration;
  @override
  int? get videoWidth => _player.state.width;
  @override
  int? get videoHeight => _player.state.height;

  @override
  Stream<bool> get playingStream => _player.stream.playing;
  @override
  Stream<Duration> get positionStream => _player.stream.position;
  @override
  Stream<Duration> get durationStream => _player.stream.duration;
  @override
  Stream<bool> get completedStream => _player.stream.completed;
  @override
  Stream<String> get errorStream => _player.stream.error;
  @override
  Stream<({int? width, int? height})> get videoSizeStream async* {
    int? w = _player.state.width;
    int? h = _player.state.height;
    final merged = StreamController<({int? width, int? height})>();
    final subs = <StreamSubscription<int?>>[
      _player.stream.width.listen((v) {
        w = v;
        merged.add((width: w, height: h));
      }),
      _player.stream.height.listen((v) {
        h = v;
        merged.add((width: w, height: h));
      }),
    ];
    merged.onCancel = () {
      for (final s in subs) {
        s.cancel();
      }
    };
    yield* merged.stream;
  }

  @override
  Future<void> open(String source, {Duration start = Duration.zero, bool play = true}) =>
      _player.open(Media(source, start: start > Duration.zero ? start : null), play: play);

  @override
  Future<void> play() => _player.play();
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> seek(Duration position) => _player.seek(position);
  @override
  Future<void> setRate(double rate) => _player.setRate(rate);
  @override
  Future<void> setVolume(double percent) => _player.setVolume(percent);

  @override
  Future<void> setDecoder(DecoderMode mode) async {
    final native = _player.platform;
    if (native is NativePlayer) {
      await native.setProperty('hwdec', hwdecValue(mode));
    }
  }

  @override
  Future<String?> activeDecoder() async {
    final native = _player.platform;
    if (native is! NativePlayer) return null;
    try {
      final v = await native.getProperty('hwdec-current');
      return v.isEmpty ? null : v;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Uint8List?> screenshot() async {
    try {
      return await _player.screenshot(format: 'image/png');
    } catch (_) {
      return null;
    }
  }

  @override
  Widget buildVideo({BoxFit fit = BoxFit.contain}) => Video(
        controller: _videoController,
        fit: fit,
        controls: NoVideoControls,
        // Fonda (Home bosilganda) ijro to'xtamasligi kerak: audio davom etadi, PiP ishlaydi
        pauseUponEnteringBackgroundMode: false,
        resumeUponEnteringForegroundMode: false,
        wakelock: true,
      );

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _player.dispose();
  }
}
