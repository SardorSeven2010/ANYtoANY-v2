import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../app_theme.dart';
import '../services/media_tools.dart';

// ================= PLEYER: FAYL TANLASH =================
class PlayerPickScreen extends StatelessWidget {
  const PlayerPickScreen({super.key});

  Future<void> _pick(BuildContext context, FileType type) async {
    PlatformFile? file;
    try {
      file = await FilePicker.pickFile(type: type);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Faylni tanlab bo'lmadi: $e")),
        );
      }
      return;
    }
    final path = file?.path;
    if (file == null || path == null || !context.mounted) return;
    final String name = file.name;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PlayerScreen(path: path, title: name)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppScaffold(
      appBar: AppBar(title: const Text("Pleyer")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Icon(Icons.play_circle_fill_rounded, size: 72, color: scheme.primary),
                  const SizedBox(height: 8),
                  const Text(
                    "Video va audio pleyer",
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Telefoningizdagi video yoki audio faylni tanlang",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => _pick(context, FileType.video),
            icon: const Icon(Icons.movie_rounded),
            label: const Text("Video tanlash"),
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: () => _pick(context, FileType.audio),
            icon: const Icon(Icons.audiotrack_rounded),
            label: const Text("Audio tanlash"),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _pick(context, FileType.any),
            icon: const Icon(Icons.folder_open_rounded),
            label: const Text("Fayllardan tanlash"),
          ),
        ],
      ),
    );
  }
}

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
