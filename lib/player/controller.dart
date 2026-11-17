import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;

import '../services/audio_focus.dart';
import '../services/background.dart';
import '../services/device_controls.dart';
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

/// Surib o'tkazish: ekranning butun eni uchun siljish. Uzun videoda ko'proq (davomiylikning 25%),
/// lekin 1 daqiqadan kam va 5 daqiqadan ko'p emas.
Duration swipeSpan(Duration duration) {
  final quarter = Duration(
    milliseconds: (duration.inMilliseconds * 0.25).round(),
  );
  if (quarter < const Duration(minutes: 1)) return const Duration(minutes: 1);
  if (quarter > const Duration(minutes: 5)) return const Duration(minutes: 5);
  return quarter;
}

/// Chapdan o'ngga surilsa oldinga, o'ngdan chapga surilsa orqaga. Natija 0..davomiylik oralig'ida.
Duration swipeSeekTarget(
  Duration start,
  double dx,
  double width,
  Duration duration,
) {
  if (width <= 0) return start;
  final ms = (dx / width * swipeSpan(duration).inMilliseconds).round();
  var t = start + Duration(milliseconds: ms);
  if (t < Duration.zero) t = Duration.zero;
  if (duration > Duration.zero && t > duration) t = duration;
  return t;
}

/// Rasm chiqishini kutish vaqti (testlarda qisqartiriladi)
Duration blackScreenTimeout = const Duration(seconds: 4);

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
    AudioFocus? focus,
  }) : _bridge = bridge ?? nativeBridge,
       _background = background,
       _saver = saver,
       _focus = focus;

  final PlayerEngine engine;
  final PlayQueue queue;
  final NativeBridge _bridge;
  final BackgroundCoordinator? _background;
  final ScreenshotSaver? _saver;
  final AudioFocus? _focus;
  AudioFocus get _audioFocus => _focus ?? audioFocus;

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

  /// Fonda ovoz: yoqilsa, ilovadan chiqilganda ham video ovozi davom etadi (bildirishnomada pleyer)
  bool backgroundAudio = false;

  /// Bosh ekranga chiqqanda video avtomatik qalqib chiquvchi oynaga o'tadi (Android)
  bool autoPip = true;

  /// Yorug'lik va ovoz (0..1): surish jestlari uchun
  double brightness = 0.5;
  double volume = 0.5;
  bool systemVolume = false;
  double _playerVolume = 1.0;

  /// Foydalanuvchiga qisqa xabar (masalan, dekoder avtomatik almashtirilganda)
  final ValueNotifier<String?> notice = ValueNotifier<String?>(null);
  String? error;
  int? videoWidth;
  int? videoHeight;

  final List<StreamSubscription<Object?>> _subs = [];
  Timer? _blackWatch;
  bool _pausedByBackground = false;
  bool _pausedByFocus = false;
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
      _audioFocus.events.listen(_onFocusEvent),
    ]);
    unawaited(_audioFocus.activate());
    unawaited(loadDeviceState());
    await _openCurrent();
  }

  /// Joriy yorug'lik va ovozni o'qiydi (jestlar shundan boshlanadi)
  Future<void> loadDeviceState() async {
    brightness = await deviceControls.brightness();
    final v = await deviceControls.volume();
    systemVolume = v != null;
    volume = v ?? _playerVolume;
    notifyListeners();
  }

  Future<void> _openCurrent({
    Duration start = Duration.zero,
    bool play = true,
  }) async {
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
    _armBlackWatch();
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
    bg.setMedia(
      MediaInfo(
        title: queue.current.title,
        subtitle: queue.length > 1
            ? "${queue.index + 1} / ${queue.length}"
            : "",
        playing: playing,
      ),
    );
  }

  /// "Home" bosilganda video avtomatik qalqib chiquvchi oynaga o'tishi uchun
  void _syncPip() {
    final bool armed = playing && !isAudio && error == null && autoPip;
    _bridge.setPipArmed(
      armed,
      width: videoWidth ?? 16,
      height: videoHeight ?? 9,
    );
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
          case 'play':
            if (!playing) unawaited(togglePlay());
          case 'pause':
          case 'stop':
            if (playing) unawaited(togglePlay());
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

  // ---------- surish jestlari ----------

  /// Yorug'likni [delta] ga o'zgartiradi (yuqoriga surish = musbat). Yangi qiymatni qaytaradi.
  Future<double> changeBrightness(double delta) async {
    brightness = (brightness + delta).clamp(0.02, 1.0);
    notifyListeners();
    await deviceControls.setBrightness(brightness);
    return brightness;
  }

  /// Ovozni [delta] ga o'zgartiradi. Android'da tizim ovozi, boshqa joyda pleyer ovozi.
  Future<double> changeVolume(double delta) async {
    volume = (volume + delta).clamp(0.0, 1.0);
    if (systemVolume) {
      await deviceControls.setVolume(volume);
    } else {
      _playerVolume = volume;
      await engine.setVolume(volume * 100);
    }
    notifyListeners();
    return volume;
  }

  // ---------- bitta video ----------

  /// Navbatda bitta fayl bo'lsa, "takrorlash" oddiy yoqish/o'chirish tugmasi bo'ladi
  bool get isSingle => queue.length == 1;

  bool get repeatOn => queue.repeat != QueueRepeat.off;

  void toggleRepeatSingle() {
    queue.repeat = queue.repeat == QueueRepeat.one
        ? QueueRepeat.off
        : QueueRepeat.one;
    notifyListeners();
  }

  // ---------- fonda ovoz, oyna, ilova holati ----------

  void setBackgroundAudio(bool on) {
    backgroundAudio = on;
    notifyListeners();
  }

  void setAutoPip(bool on) {
    autoPip = on;
    _syncPip();
    notifyListeners();
  }

  /// Ilova yashirilganda: "Fonda ovoz" yoqilmagan video to'xtatiladi (audio va qalqib chiquvchi oyna davom etadi)
  void onAppLifecycle(AppLifecycleState state) {
    if (_disposed) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (playing && !isAudio && !backgroundAudio && !inPip) {
        _pausedByBackground = true;
        unawaited(engine.pause());
      }
    }
  }

  /// Ilova yana ochilganda, faqat biz to'xtatgan bo'lsak, ijro davom etadi
  void onAppResumed() {
    if (_pausedByBackground && !_disposed) {
      _pausedByBackground = false;
      unawaited(engine.play());
    }
  }

  void _onFocusEvent(AudioFocusEvent e) {
    if (_disposed) return;
    if (e == AudioFocusEvent.pause) {
      if (playing) {
        _pausedByFocus = true;
        unawaited(engine.pause());
      }
    } else if (_pausedByFocus) {
      _pausedByFocus = false;
      unawaited(engine.play());
    }
  }

  // ---------- rasm chiqmasa dekoder zaxirasi ----------

  /// Video ochilgach 4 soniyadan keyin ijro ketayotgan bo'lsa-yu, kadr o'lchami ma'lum bo'lmasa (qora ekran),
  /// dekoder avtomatik almashtiriladi: avtomatik -> apparat+nusxa -> dasturiy.
  void _armBlackWatch() {
    _blackWatch?.cancel();
    if (isAudio) return;
    _blackWatch = Timer(
      blackScreenTimeout,
      () => unawaited(_checkBlackScreen()),
    );
  }

  static const List<DecoderMode> _fallbackChain = [
    DecoderMode.auto,
    DecoderMode.hardwareCopy,
    DecoderMode.software,
  ];

  Future<void> _checkBlackScreen() async {
    if (_disposed || isAudio || error != null || loading) return;
    if (!playing) {
      _armBlackWatch(); // pauzada: kadr chiqmaydi, keyinroq qayta tekshiramiz
      return;
    }
    final w = videoWidth ?? engine.videoWidth ?? 0;
    final h = videoHeight ?? engine.videoHeight ?? 0;
    if (w > 0 && h > 0) return; // rasm bor
    // keyingi dekoder: hozirgisidan keyin keladigan va haqiqatan boshqacha ishlaydigani
    final index = _fallbackChain.indexOf(decoder);
    DecoderMode? next;
    for (var i = index + 1; index >= 0 && i < _fallbackChain.length; i++) {
      if (hwdecValue(_fallbackChain[i]) != hwdecValue(decoder)) {
        next = _fallbackChain[i];
        break;
      }
    }
    if (next == null) {
      notice.value =
          "Video ko'rinmadi. Bu format shu qurilmada ochilmasligi mumkin.";
      return;
    }
    notice.value =
        "Rasm chiqmadi: dekoder avtomatik \"${next.label}\" ga almashtirildi";
    await setDecoder(next);
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
    _blackWatch?.cancel();
    _bridge.setPipArmed(false);
    _background?.setMedia(null);
    unawaited(deviceControls.resetBrightness());
    unawaited(_audioFocus.deactivate());
    notice.dispose();
    position.dispose();
    unawaited(engine.dispose());
    super.dispose();
  }
}
