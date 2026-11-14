import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../app_theme.dart';
import '../platform.dart';
import '../services/media_tools.dart';

// ================= VIDEO VA AUDIO PLEYER =================
class PlayerScreen extends StatefulWidget {
  final String path;
  final String title;
  const PlayerScreen({super.key, required this.path, required this.title});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  static const List<double> _speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  late final VideoPlayerController _controller;
  bool _ready = false;
  String? _error;
  double _speed = 1.0;
  bool _loop = false;
  double? _dragMs;
  bool _awake = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.path));
    _controller.addListener(_onTick);
    _controller.initialize().then((_) {
      if (!mounted) return;
      setState(() => _ready = true);
      _controller.play();
    }).catchError((Object e) {
      if (mounted) setState(() => _error = "Bu faylni ijro etib bo'lmadi");
    });
  }

  void _onTick() {
    if (!mounted) return;
    final value = _controller.value;
    if (value.hasError && _error == null) _error = "Bu faylni ijro etib bo'lmadi";
    _keepAwake(value.isPlaying);
    setState(() {});
  }

  // Ijro paytida ekran o'chib qolmasligi uchun
  void _keepAwake(bool on) {
    if (on == _awake) return;
    _awake = on;
    WakelockPlus.toggle(enable: on).catchError((Object _) {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onTick);
    _controller.dispose();
    if (_awake) WakelockPlus.disable().catchError((Object _) {});
    super.dispose();
  }

  Future<void> _togglePlay() async {
    final value = _controller.value;
    if (value.isPlaying) {
      await _controller.pause();
    } else {
      if (value.isCompleted || value.position >= value.duration) {
        await _controller.seekTo(Duration.zero);
      }
      await _controller.play();
    }
  }

  Future<void> _skip(int seconds) async {
    final value = _controller.value;
    Duration target = value.position + Duration(seconds: seconds);
    if (target < Duration.zero) target = Duration.zero;
    if (target > value.duration) target = value.duration;
    await _controller.seekTo(target);
  }

  String _format(Duration d) {
    String two(int v) => v.toString().padLeft(2, '0');
    final int h = d.inHours;
    final String ms = "${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}";
    return h > 0 ? "$h:$ms" : ms;
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      appBar: AppBar(title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: _error != null
          ? _message(Icons.error_outline_rounded, _error!)
          : !_ready
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    Expanded(child: _stage()),
                    _controls(),
                  ],
                ),
    );
  }

  /// Kompyuterda: faylni tizimdagi odatiy pleyerda ochadi
  Future<void> _openInSystemPlayer() async {
    bool opened = false;
    try {
      opened = await launchUrl(Uri.file(widget.path));
    } catch (_) {}
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Tizim pleyerini ochib bo'lmadi")),
      );
    }
  }

  Widget _message(IconData icon, String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
            // Windows faqat o'zida o'rnatilgan kodeklarni ijro eta oladi (masalan MKV ba'zan ochilmaydi)
            if (isDesktopApp) ...[
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: _openInSystemPlayer,
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text("Tizim pleyerida ochish"),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _stage() {
    final size = _controller.value.size;
    final bool hasVideo = size.width > 0 && size.height > 0;
    if (hasVideo) {
      return GestureDetector(
        onTap: _togglePlay,
        child: Container(
          color: Colors.black,
          alignment: Alignment.center,
          child: AspectRatio(
            aspectRatio: size.width / size.height,
            child: VideoPlayer(_controller),
          ),
        ),
      );
    }

    // Audio fayl uchun rasm o'rniga belgi ko'rsatiladi
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [scheme.primary, scheme.tertiary],
              ),
              boxShadow: [
                BoxShadow(color: scheme.primary.withValues(alpha: 0.45), blurRadius: 36, spreadRadius: 4),
              ],
            ),
            child: Icon(
              isVideoFile(widget.title) ? Icons.movie_rounded : Icons.music_note_rounded,
              size: 96,
              color: scheme.onPrimary,
            ),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              widget.title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _controls() {
    final value = _controller.value;
    final double totalMs = value.duration.inMilliseconds.toDouble();
    final double positionMs = (_dragMs ?? value.position.inMilliseconds.toDouble()).clamp(0.0, totalMs);
    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Slider(
              value: positionMs,
              max: totalMs <= 0 ? 1 : totalMs,
              onChangeStart: (v) => setState(() => _dragMs = v),
              onChanged: (v) => setState(() => _dragMs = v),
              onChangeEnd: (v) async {
                await _controller.seekTo(Duration(milliseconds: v.round()));
                if (mounted) setState(() => _dragMs = null);
              },
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_format(Duration(milliseconds: positionMs.round()))),
                  Text(_format(value.duration)),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                PopupMenuButton<double>(
                  tooltip: "Tezlik",
                  initialValue: _speed,
                  onSelected: (v) {
                    setState(() => _speed = v);
                    _controller.setPlaybackSpeed(v);
                  },
                  itemBuilder: (_) => [
                    for (final s in _speeds) PopupMenuItem(value: s, child: Text("${s}x")),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text("${_speed}x", style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                IconButton(
                  iconSize: 34,
                  tooltip: "10 soniya orqaga",
                  onPressed: () => _skip(-10),
                  icon: const Icon(Icons.replay_10_rounded),
                ),
                IconButton.filled(
                  iconSize: 44,
                  tooltip: value.isPlaying ? "To'xtatish" : "Ijro etish",
                  onPressed: _togglePlay,
                  icon: Icon(value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
                ),
                IconButton(
                  iconSize: 34,
                  tooltip: "10 soniya oldinga",
                  onPressed: () => _skip(10),
                  icon: const Icon(Icons.forward_10_rounded),
                ),
                IconButton(
                  tooltip: "Takrorlash",
                  color: _loop ? scheme.primary : null,
                  onPressed: () {
                    setState(() => _loop = !_loop);
                    _controller.setLooping(_loop);
                  },
                  icon: Icon(_loop ? Icons.repeat_one_rounded : Icons.repeat_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
