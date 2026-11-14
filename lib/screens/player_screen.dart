import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_theme.dart';
import '../platform.dart';
import '../player/controller.dart';
import '../player/engine.dart';
import '../player/play_queue.dart';
import '../services/background.dart';
import 'player_sheets.dart';

// ================= VIDEO VA AUDIO PLEYER =================
// Navbat (aralashtirish, takrorlash, oxirigacha ijro), 2 marta bosish jestlari (chap/o'ng/o'rta),
// tezlik 0.25x-4x, dekoderlar, video o'lchamlari, skrinshot, ekranni burish, qalqib chiquvchi oyna
// va fonda ijro (bildirishnoma tugmalari bilan).
class PlayerScreen extends StatefulWidget {
  final String? path;
  final String? title;
  final List<QueueItem>? items;
  final int startIndex;

  /// Bitta fayl
  const PlayerScreen({super.key, required String this.path, required String this.title})
      : items = null,
        startIndex = 0;

  /// Bir necha fayl: tanlangani birinchi bo'lib ochiladi, keyingilari ketma-ket o'ynaydi
  const PlayerScreen.queue({super.key, required List<QueueItem> this.items, this.startIndex = 0})
      : path = null,
        title = null;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  PlayerController? _c;
  String? _fatal;

  bool _controlsVisible = true;
  Timer? _hideTimer;
  Offset _tapDown = Offset.zero;
  double? _dragMs;

  // 2 marta bosilganda chiqadigan "+10 s" belgisi
  TapZone? _feedbackZone;
  int _feedbackSeconds = 0;
  Timer? _feedbackTimer;

  String? _toast;
  Timer? _toastTimer;

  bool get _isMobile => isAndroidApp || isIOSApp;

  List<QueueItem> get _items =>
      widget.items ?? [QueueItem(title: widget.title ?? "", path: widget.path)];

  String get _firstPath => _items[widget.startIndex.clamp(0, _items.length - 1)].path ?? "";

  @override
  void initState() {
    super.initState();
    try {
      final engine = playerEngineFactory();
      final controller = PlayerController(
        engine: engine,
        queue: PlayQueue(_items, start: widget.startIndex),
        background: backgroundService,
      );
      _c = controller;
      controller.addListener(_onChange);
      controller.start();
      if (!controller.isAudio) SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } catch (_) {
      _fatal = isDesktopApp
          ? "Ichki pleyer ishga tushmadi (libmpv topilmadi). Fayl kompyuteringizdagi pleyerda ochiladi."
          : "Bu qurilmada pleyerni ishga tushirib bo'lmadi.";
      if (isDesktopApp) WidgetsBinding.instance.addPostFrameCallback((_) => _openInSystemPlayer());
    }
    _scheduleHide();
  }

  void _onChange() {
    if (!mounted) return;
    // ijro boshlanganda boshqaruv o'zi yashiriladi
    if (_c?.playing == true && _controlsVisible) _scheduleHide();
    setState(() {});
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _feedbackTimer?.cancel();
    _toastTimer?.cancel();
    _c?.removeListener(_onChange);
    _c?.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  // ---------- boshqaruvni ko'rsatish/yashirish ----------

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      if (_c?.playing == true && !(_c?.isAudio ?? true)) setState(() => _controlsVisible = false);
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHide();
  }

  void _keepControls() {
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    _scheduleHide();
  }

  // ---------- jestlar ----------

  void _onDoubleTap(double width) {
    final c = _c;
    if (c == null) return;
    final zone = tapZoneFor(_tapDown.dx, width);
    c.onDoubleTap(zone);
    // ketma-ket bosishlar jamlanadi: 10 s, 20 s, 30 s ...
    setState(() {
      if (zone == _feedbackZone && zone != TapZone.center) {
        _feedbackSeconds += seekStep.inSeconds;
      } else {
        _feedbackSeconds = seekStep.inSeconds;
      }
      _feedbackZone = zone;
    });
    _feedbackTimer?.cancel();
    _feedbackTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _feedbackZone = null);
    });
  }

  void _say(String text) {
    _toastTimer?.cancel();
    setState(() => _toast = text);
    _toastTimer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  // ---------- amallar ----------

  Future<void> _screenshot() async {
    final c = _c;
    if (c == null) return;
    final where = await c.screenshot();
    _say(where == null ? "Skrinshot olib bo'lmadi" : "Skrinshot saqlandi: $where");
  }

  void _rotate() {
    final landscape = MediaQuery.orientationOf(context) == Orientation.landscape;
    SystemChrome.setPreferredOrientations(
      landscape
          ? [DeviceOrientation.portraitUp]
          : [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight],
    );
    _keepControls();
  }

  Future<void> _pip() async {
    final ok = await _c?.enterPip() ?? false;
    if (!ok) _say("Qalqib chiquvchi oyna bu qurilmada ishlamaydi");
  }

  void _repeat() {
    final c = _c!;
    c.cycleRepeat();
    _say(QueueSheet.repeatLabel(c.queue.repeat));
    _keepControls();
  }

  void _shuffle() {
    final c = _c!;
    c.toggleShuffle();
    _say(c.queue.shuffle ? "Aralashtirish yoqildi" : "Aralashtirish o'chirildi");
    _keepControls();
  }

  void _sheet(Widget Function(PlayerController) build) {
    final c = _c;
    if (c == null) return;
    _hideTimer?.cancel();
    showPlayerSheet(context, (_) => build(c)).whenComplete(_scheduleHide);
  }

  /// Kompyuterda: faylni tizimdagi odatiy pleyerda ochadi
  Future<void> _openInSystemPlayer() async {
    bool opened = false;
    try {
      opened = await launchUrl(Uri.file(_firstPath));
    } catch (_) {}
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Tizim pleyerini ochib bo'lmadi")));
    }
  }

  String _format(Duration d) {
    String two(int v) => v.toString().padLeft(2, '0');
    final int h = d.inHours;
    final String ms = "${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}";
    return h > 0 ? "$h:$ms" : ms;
  }

  // ---------- ekran ----------

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null) return _fatalScreen();
    final bool pip = c.inPip;
    return Scaffold(
      backgroundColor: Colors.black,
      body: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.space): c.togglePlay,
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () => c.seekBy(-seekStep),
          const SingleActivator(LogicalKeyboardKey.arrowRight): () => c.seekBy(seekStep),
          const SingleActivator(LogicalKeyboardKey.keyN): c.next,
          const SingleActivator(LogicalKeyboardKey.keyP): c.previous,
          const SingleActivator(LogicalKeyboardKey.keyS): _screenshot,
        },
        child: Focus(
          autofocus: true,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _stage(c),
              if (!pip) _gestureLayer(c),
              if (c.loading) const Center(child: CircularProgressIndicator()),
              if (c.error != null && !c.loading) _errorView(c),
              if (!pip && _feedbackZone != null) _feedback(),
              if (!pip) _controls(c),
              if (_toast != null && !pip) _toastView(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fatalScreen() {
    return AppScaffold(
      appBar: AppBar(title: Text(widget.title ?? widget.items?.first.title ?? "", maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(isDesktopApp ? Icons.play_circle_outline_rounded : Icons.error_outline_rounded, size: 64),
              const SizedBox(height: 12),
              Text(_fatal ?? "", textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
              if (isDesktopApp) ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _openInSystemPlayer,
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text("Tizim pleyerida ochish"),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Video (yoki audio uchun rasm) maydoni
  Widget _stage(PlayerController c) {
    if (c.isAudio) {
      final scheme = Theme.of(context).colorScheme;
      return ThemedBackground(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(40)),
                  child: Icon(Icons.music_note_rounded, size: 96, color: scheme.onPrimaryContainer),
                ),
                const SizedBox(height: 22),
                Text(
                  c.queue.current.title,
                  maxLines: 3,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: scheme.onSurface),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final ratio = c.aspect.ratio;
    final video = ratio == null
        ? c.engine.buildVideo(fit: c.aspect.fit)
        : Center(child: AspectRatio(aspectRatio: ratio, child: c.engine.buildVideo(fit: c.aspect.fit)));
    return ColoredBox(color: Colors.black, child: video);
  }

  /// Chap / o'rta / o'ng uchdan biri: 2 marta bosilganda orqaga / pauza / oldinga
  Widget _gestureLayer(PlayerController c) {
    return LayoutBuilder(
      builder: (context, box) => GestureDetector(
        key: const Key("gestureLayer"),
        behavior: HitTestBehavior.opaque,
        onTap: _toggleControls,
        onDoubleTapDown: (d) => _tapDown = d.localPosition,
        onDoubleTap: () => _onDoubleTap(box.maxWidth),
      ),
    );
  }

  Widget _feedback() {
    final zone = _feedbackZone!;
    final IconData icon = switch (zone) {
      TapZone.left => Icons.fast_rewind_rounded,
      TapZone.right => Icons.fast_forward_rounded,
      TapZone.center => (_c?.playing ?? false) ? Icons.play_arrow_rounded : Icons.pause_rounded,
    };
    final String text = switch (zone) {
      TapZone.center => "",
      _ => "$_feedbackSeconds s",
    };
    return IgnorePointer(
      child: Align(
        alignment: switch (zone) {
          TapZone.left => const Alignment(-0.7, 0),
          TapZone.right => const Alignment(0.7, 0),
          TapZone.center => Alignment.center,
        },
        child: Container(
          key: Key("feedback_${zone.name}"),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(40)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 40),
              if (text.isNotEmpty) Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toastView() {
    return Positioned(
      left: 24,
      right: 24,
      top: 90,
      child: IgnorePointer(
        child: Center(
          child: Container(
            key: const Key("playerToast"),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(22)),
            child: Text(_toast!, style: const TextStyle(color: Colors.white), textAlign: TextAlign.center),
          ),
        ),
      ),
    );
  }

  Widget _errorView(PlayerController c) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(24)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.white, size: 48),
            const SizedBox(height: 10),
            Text(c.error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 16)),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              children: [
                FilledButton(onPressed: () => c.jumpTo(c.queue.index), child: const Text("Qayta urinish")),
                if (c.queue.length > 1) OutlinedButton(onPressed: c.next, child: const Text("Keyingisi")),
                if (isDesktopApp) OutlinedButton(onPressed: _openInSystemPlayer, child: const Text("Tizim pleyerida ochish")),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---------- boshqaruv paneli ----------

  Widget _controls(PlayerController c) {
    final bool show = _controlsVisible || c.isAudio || !c.playing || c.error != null;
    return AnimatedOpacity(
      key: const Key("controls"),
      opacity: show ? 1 : 0,
      duration: const Duration(milliseconds: 200),
      child: IgnorePointer(
        ignoring: !show,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Align(alignment: Alignment.topCenter, child: _topBar(c)),
            Center(child: _transport(c)),
            Align(alignment: Alignment.bottomCenter, child: _bottomPanel(c)),
          ],
        ),
      ),
    );
  }

  Widget _topBar(PlayerController c) {
    final q = c.queue;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black87, Colors.transparent]),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            IconButton(
              tooltip: "Orqaga",
              color: Colors.white,
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    q.current.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  if (q.length > 1)
                    Text("${q.index + 1} / ${q.length}", style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
            if (!c.isAudio)
              IconButton(
                key: const Key("screenshotButton"),
                tooltip: "Skrinshot",
                color: Colors.white,
                icon: const Icon(Icons.photo_camera_rounded),
                onPressed: _screenshot,
              ),
            if (!c.isAudio && _isMobile)
              IconButton(
                key: const Key("rotateButton"),
                tooltip: "Ekranni burish",
                color: Colors.white,
                icon: const Icon(Icons.screen_rotation_rounded),
                onPressed: _rotate,
              ),
            if (c.pipSupported && !c.isAudio)
              IconButton(
                key: const Key("pipButton"),
                tooltip: "Qalqib chiquvchi oyna",
                color: Colors.white,
                icon: const Icon(Icons.picture_in_picture_alt_rounded),
                onPressed: _pip,
              ),
          ],
        ),
      ),
    );
  }

  Widget _transport(PlayerController c) {
    Widget button(IconData icon, VoidCallback? onTap, {double size = 38, Key? key, String? tip}) => IconButton(
          key: key,
          tooltip: tip,
          iconSize: size,
          color: Colors.white,
          style: IconButton.styleFrom(backgroundColor: Colors.black38),
          icon: Icon(icon),
          onPressed: onTap == null
              ? null
              : () {
                  onTap();
                  _keepControls();
                },
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        button(Icons.skip_previous_rounded, c.previous, key: const Key("prevButton"), tip: "Oldingi"),
        const SizedBox(width: 20),
        button(
          c.ended ? Icons.replay_rounded : (c.playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
          c.togglePlay,
          size: 54,
          key: const Key("playPauseButton"),
          tip: c.playing ? "Pauza" : "Ijro",
        ),
        const SizedBox(width: 20),
        button(Icons.skip_next_rounded, c.next, key: const Key("nextButton"), tip: "Keyingi"),
      ],
    );
  }

  Widget _bottomPanel(PlayerController c) {
    final q = c.queue;
    final video = !c.isAudio;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black87, Colors.transparent]),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 18, 12, 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder<Duration>(
                valueListenable: c.position,
                builder: (context, pos, _) {
                  final total = c.duration.inMilliseconds;
                  final double max = total <= 0 ? 1 : total.toDouble();
                  final double value = (_dragMs ?? pos.inMilliseconds.toDouble()).clamp(0, max).toDouble();
                  return Row(
                    children: [
                      Text(_format(Duration(milliseconds: value.round())), style: const TextStyle(color: Colors.white, fontSize: 12)),
                      Expanded(
                        child: Slider(
                          key: const Key("seekBar"),
                          min: 0,
                          max: max,
                          value: value,
                          onChanged: total <= 0
                              ? null
                              : (v) {
                                  setState(() => _dragMs = v);
                                  _hideTimer?.cancel();
                                },
                          onChangeEnd: (v) {
                            setState(() => _dragMs = null);
                            c.seekTo(Duration(milliseconds: v.round()));
                            _keepControls();
                          },
                        ),
                      ),
                      Text(_format(c.duration), style: const TextStyle(color: Colors.white, fontSize: 12)),
                    ],
                  );
                },
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _Tool(
                      key: const Key("repeatButton"),
                      icon: switch (q.repeat) {
                        QueueRepeat.off => Icons.repeat_rounded,
                        QueueRepeat.all => Icons.repeat_on_rounded,
                        QueueRepeat.one => Icons.repeat_one_on_rounded,
                      },
                      label: switch (q.repeat) {
                        QueueRepeat.off => "To'xtash",
                        QueueRepeat.all => "Ro'yxat",
                        QueueRepeat.one => "Bitta",
                      },
                      active: q.repeat != QueueRepeat.off,
                      onTap: _repeat,
                    ),
                    _Tool(
                      key: const Key("shuffleButton"),
                      icon: q.shuffle ? Icons.shuffle_on_rounded : Icons.shuffle_rounded,
                      label: "Aralash",
                      active: q.shuffle,
                      onTap: _shuffle,
                    ),
                    _Tool(
                      key: const Key("speedButton"),
                      icon: Icons.speed_rounded,
                      label: speedLabel(c.speed),
                      active: (c.speed - 1).abs() > 0.001,
                      onTap: () => _sheet((c) => SpeedSheet(controller: c)),
                    ),
                    if (video)
                      _Tool(
                        key: const Key("aspectButton"),
                        icon: Icons.aspect_ratio_rounded,
                        label: c.aspect.shortLabel,
                        active: c.aspect.name != "original",
                        onTap: () => _sheet((c) => AspectSheet(controller: c)),
                      ),
                    if (video)
                      _Tool(
                        key: const Key("decoderButton"),
                        icon: Icons.memory_rounded,
                        label: "Dekoder",
                        onTap: () => _sheet((c) => DecoderSheet(controller: c)),
                      ),
                    _Tool(
                      key: const Key("queueButton"),
                      icon: Icons.queue_music_rounded,
                      label: "Navbat",
                      onTap: () => _sheet((c) => QueueSheet(controller: c)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tool extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _Tool({super.key, required this.icon, required this.label, required this.onTap, this.active = false});

  @override
  Widget build(BuildContext context) {
    final color = active ? Theme.of(context).colorScheme.primary : Colors.white;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(color: color, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
