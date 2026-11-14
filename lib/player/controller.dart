import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/background.dart';
import '../services/native_bridge.dart';
import '../services/screenshots.dart';
import '../services/media_tools.dart';
import 'aspect.dart';
import 'engine.dart';
import 'play_queue.dart';

/// Video ustida ikki marta bosilgan joy: chap = orqaga, o'rta = pauza, o'ng = oldinga
enum TapZone { left, center, right }

TapZone tapZoneFor(double x, double width) {
  if (width <= 0) return TapZone.center;
  final f = x / width;
  if (f < 1 / 3) return TapZone.left;
  if (f > 2 / 3) return TapZone.right;
  return TapZone.center;
}

const Duration seekStep = Duration(seconds: 10);
const double minSpeed = 0.25;
const double maxSpeed = 4.0;

/// Pleyer holati va amallari: navbat, ijro, tezlik, dekoder, o'lcham, skrinshot, PiP, fon xizmati.
/// Dvigatel va native qatlam interfeys orqali ulanadi, shuning uchun testlarda soxta ob'ektlar bilan sinaladi.
class PlayerController extends ChangeNotifier {
  PlayerController({
    required this.engine,
    required this.queue,
    NativeBridge? bridge,
    BackgroundCoordinator? background,
    ScreenshotSaver? saver,
  })  : _bridge = bridge ?? nativeBridge,
        _background = background,
        _saver = saver;

  final PlayerEngine engine;
  final PlayQueue queue;
  final NativeBridge _bridge;
  final BackgroundCoordinator? _background;
  final ScreenshotSaver? _saver;

  /// Ijro vaqti alohida: tez-tez o'zgargani uchun butun ekranni qayta chizmaydi
  final ValueNotifier<Duration> position = ValueNotifier(Duration.zero);

  bool playing = false;
  Duration duration = Duration.zero;
  double speed = 1.0;
  DecoderMode decoder = DecoderMode.auto;
  AspectMode aspect = AspectMode.original;
  bool loading = true;
  bool ended = false;
  bool inPip = false;
  String? error;
  int? videoWidth;
  int? videoHeight;

  final List<StreamSubscription<Object?>> _subs = [];
  int _openGeneration = 0;
  bool _disposed = false;
  bool _started = false;

  /// Hozirgi fayl audiomi (kengaytma bo'yicha): shunda video maydoni o'rniga rasm ko'rsatiladi
  bool get isAudio => isAudioFile(queue.current.nameForType);

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _subs.addAll([
      engine.playingStream.listen((v) {
        if (playing == v) return;
        playing = v;
        if (v) ended = false;
        _afterStateChange();
      }),
      engine.positionStream.listen((p) => position.value = p),
      engine.durationStream.listen((d) {
        duration = d;
        notifyListeners();
      }),
      engine.completedStream.listen((c) {
        if (c) unawaited(_onCompleted());
      }),
      engine.errorStream.listen((e) {
        if (e.isEmpty || loading) return;
        error = "Bu faylni ijro etib bo'lmadi";
        notifyListeners();
      }),
      engine.videoSizeStream.listen((s) {
        videoWidth = s.width;
        videoHeight = s.height;
        _syncPip();
        notifyListeners();
      }),
      _bridge.events.listen(_onNativeEvent),
    ]);
    await _openCurrent();
  }

  Future<void> _openCurrent({Duration start = Duration.zero, bool play = true}) async {
    final generation = ++_openGeneration;
    loading = true;
    error = null;
    ended = false;
    notifyListeners();
    final String? source;
    try {
      source = await queue.current.source();
    } catch (_) {
      if (generation == _openGeneration) _fail("Faylni ochib bo'lmadi");
      return;
    }
    if (_disposed || generation != _openGeneration) return;
    if (source == null) {
      _fail("Fayl topilmadi");
      return;
    }
    try {
      await engine.open(source, start: start, play: play);
      await engine.setRate(speed);
    } catch (_) {
      if (generation == _openGeneration) _fail("Bu faylni ijro etib bo'lmadi");
      return;
    }
    if (_disposed || generation != _openGeneration) return;
    position.value = start;
    loading = false;
    _afterStateChange();
  }

  void _fail(String message) {
    if (_disposed) return;
    loading = false;
    error = message;
    playing = false;
    _afterStateChange();
  }

  /// Fayl tugadi: navbat qoidasiga ko'ra keyingisi, qayta yoki to'xtash
  Future<void> _onCompleted() async {
    if (_disposed || loading) return;
    if (queue.repeat == QueueRepeat.one) {
      await engine.seek(Duration.zero);
      await engine.play();
      return;
    }
    if (queue.next(auto: true)) {
      await _openCurrent();
    } else {
      ended = true;
      playing = false;
      _afterStateChange();
    }
  }

  void _afterStateChange() {
    if (_disposed) return;
    _syncPip();
    _syncBackground();
    notifyListeners();
  }

  void _syncBackground() {
    final bg = _background;
    if (bg == null) return;
    if (loading && !playing) return;
    bg.setMedia(MediaInfo(
      title: queue.current.title,
      subtitle: queue.length > 1 ? "${queue.index + 1} / ${queue.length}" : "",
      playing: playing,
    ));
  }

  /// "Home" bosilganda video avtomatik qalqib chiquvchi oynaga o'tishi uchun
  void _syncPip() {
    final bool armed = playing && !isAudio && error == null;
    _bridge.setPipArmed(armed, width: videoWidth ?? 16, height: videoHeight ?? 9);
  }

  void _onNativeEvent(NativeEvent e) {
    switch (e.name) {
      case 'mediaAction':
        switch (e.data) {
          case 'previous':
            unawaited(previous());
          case 'next':
            unawaited(next());
          case 'playpause':
            unawaited(togglePlay());
        }
      case 'pipChanged':
        inPip = e.data == true;
        notifyListeners();
    }
  }

  // ---------- ijro ----------

  Future<void> togglePlay() async {
    if (error != null || loading) return;
    if (ended) {
      ended = false;
      await engine.seek(Duration.zero);
      await engine.play();
    } else if (playing) {
      await engine.pause();
    } else {
      await engine.play();
    }
  }

  Future<void> seekTo(Duration target) async {
    var t = target;
    if (t < Duration.zero) t = Duration.zero;
    if (duration > Duration.zero && t > duration) t = duration;
    position.value = t;
    await engine.seek(t);
  }

  /// Hozirgi joydan [delta] ga suradi (manfiy = orqaga). Yangi joyni qaytaradi.
  Future<Duration> seekBy(Duration delta) async {
    final target = position.value + delta;
    await seekTo(target);
    return position.value;
  }

  Future<void> onDoubleTap(TapZone zone) async {
    switch (zone) {
      case TapZone.left:
        await seekBy(-seekStep);
      case TapZone.right:
        await seekBy(seekStep);
      case TapZone.center:
        await togglePlay();
    }
  }

  // ---------- navbat ----------

  Future<void> next() async {
    if (queue.next()) await _openCurrent();
  }

  /// Oldingi fayl; fayl 3 soniyadan ko'proq ijro etilgan bo'lsa, avval boshiga qaytadi
  Future<void> previous() async {
    if (position.value > const Duration(seconds: 3)) {
      await seekTo(Duration.zero);
      return;
    }
    if (queue.previous()) {
      await _openCurrent();
    } else {
      await seekTo(Duration.zero);
    }
  }

  Future<void> jumpTo(int index) async {
    queue.jumpTo(index);
    await _openCurrent();
  }

  void cycleRepeat() {
    queue.repeat = nextQueueRepeat(queue.repeat);
    notifyListeners();
  }

  void toggleShuffle() {
    queue.shuffle = !queue.shuffle;
    notifyListeners();
  }

  // ---------- sozlamalar ----------

  /// Tezlik 0.25x .. 4x oralig'ida, 0.05 qadam bilan
  Future<void> setSpeed(double value) async {
    final v = (value.clamp(minSpeed, maxSpeed) * 20).round() / 20;
    speed = v;
    notifyListeners();
    await engine.setRate(v);
  }

  /// Dekoderni almashtiradi va faylni shu joydan qayta ochadi (o'zgarish shundan keyin kuchga kiradi)
  Future<void> setDecoder(DecoderMode mode) async {
    if (mode == decoder) return;
    decoder = mode;
    final at = position.value;
    final wasPlaying = playing;
    notifyListeners();
    await engine.setDecoder(mode);
    await _openCurrent(start: at, play: wasPlaying);
  }

  void setAspect(AspectMode mode) {
    aspect = mode;
    notifyListeners();
  }

  /// Hozirgi kadrni rasm sifatida saqlaydi. Saqlangan joy tavsifini qaytaradi (bo'lmasa null).
  Future<String?> screenshot() async {
    final png = await engine.screenshot();
    if (png == null || png.isEmpty) return null;
    final saver = _saver ?? screenshotSaver;
    return saver(png, baseNameOf(queue.current.title));
  }

  /// Qalqib chiquvchi oyna (faqat Android)
  Future<bool> enterPip() async {
    if (isAudio) return false;
    return _bridge.enterPip(width: videoWidth ?? 16, height: videoHeight ?? 9);
  }

  bool get pipSupported => _bridge.supported;

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final s in _subs) {
      s.cancel();
    }
    _bridge.setPipArmed(false);
    _background?.setMedia(null);
    position.dispose();
    unawaited(engine.dispose());
    super.dispose();
  }
}
