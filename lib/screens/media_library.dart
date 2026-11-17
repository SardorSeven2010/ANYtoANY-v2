import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../platform.dart';
import '../services/gallery.dart';
import '../services/media_tools.dart';
import '../player/play_queue.dart';
import 'player_screen.dart';
import '../widgets/glass.dart';

enum MediaKind { video, audio }

/// Kompyuterda video / audio fayllar qidiriladigan papkalar
List<Directory> desktopMediaRoots(MediaKind kind) {
  final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
  if (home == null || home.isEmpty) return [];
  final names = kind == MediaKind.video ? ["Videos", "Downloads", "Desktop"] : ["Music", "Downloads", "Desktop"];
  return [for (final name in names) Directory(joinPath(home, name))];
}

/// Berilgan papkalardan (ichki papkalari bilan) video yoki audio fayllarni topadi.
/// Eng yangi fayllar birinchi keladi.
Future<List<File>> scanMediaFiles(
  List<Directory> roots,
  MediaKind kind, {
  int limit = 500,
  int maxDepth = 4,
}) async {
  final found = <File>[];
  final seen = <String>{};

  Future<void> walk(Directory dir, int depth) async {
    if (found.length >= limit) return;
    try {
      await for (final entity in dir.list(followLinks: false)) {
        if (found.length >= limit) break;
        final name = lastSegment(entity.path);
        if (entity is File) {
          final bool matches = kind == MediaKind.video ? isVideoFile(name) : isAudioFile(name);
          if (matches && seen.add(entity.path)) found.add(entity);
        } else if (entity is Directory && depth < maxDepth && !name.startsWith('.')) {
          await walk(entity, depth + 1);
        }
      }
    } catch (_) {
      // Ochishga ruxsat bo'lmagan papkalar o'tkazib yuboriladi
    }
  }

  for (final root in roots) {
    if (await root.exists()) await walk(root, 0);
  }

  final modified = <String, DateTime>{};
  for (final file in found) {
    try {
      modified[file.path] = (await file.stat()).modified;
    } catch (_) {
      modified[file.path] = DateTime.fromMillisecondsSinceEpoch(0);
    }
  }
  found.sort((a, b) => modified[b.path]!.compareTo(modified[a.path]!));
  return found;
}

/// Ro'yxatdagi bitta fayl: telefonda media kutubxonasidan, kompyuterda papkadan olinadi
class _Entry {
  final String title;
  final String subtitle;
  final AssetEntity? asset;
  final String? path;
  const _Entry({required this.title, required this.subtitle, this.asset, this.path});
}

// ================= VIDEO / AUDIO FAYLLAR BO'LIMI =================
// Qurilmadagi video yoki audio fayllar ro'yxati. Faylni bossangiz pleyerda ochiladi.
class MediaLibraryTab extends StatefulWidget {
  final MediaKind kind;

  /// Kompyuterda qidiriladigan papkalar (ko'rsatilmasa Videos / Music / Downloads / Desktop)
  final List<Directory>? desktopRoots;
  const MediaLibraryTab({super.key, required this.kind, this.desktopRoots});

  @override
  State<MediaLibraryTab> createState() => _MediaLibraryTabState();
}

class _MediaLibraryTabState extends State<MediaLibraryTab> {
  static const int _pageSize = 80;

  final List<_Entry> _items = [];
  final Map<String, Future<Uint8List?>> _thumbnails = {};
  AssetPathEntity? _album;
  bool _loading = true;
  bool _loadingMore = false;
  bool _granted = false;
  bool _hasMore = false;
  int _page = 0;

  bool get _isVideo => widget.kind == MediaKind.video;

  /// iPhone'da "Rasmlar" kutubxonasida audio yo'q, musiqa esa ilovalarga yopiq:
  /// audio faqat Fayllar ilovasidan tanlanadi
  bool get _filesOnly => isIOSApp && !_isVideo;
  RequestType get _type => _isVideo ? RequestType.video : RequestType.audio;

  PermissionRequestOption get _permission => PermissionRequestOption(
        androidPermission: AndroidPermission(type: _type, mediaLocation: false),
      );

  @override
  void initState() {
    super.initState();
    libraryRevision.addListener(_onLibraryChanged);
    _init();
  }

  @override
  void dispose() {
    libraryRevision.removeListener(_onLibraryChanged);
    super.dispose();
  }

  /// Yangi video yuklanganda yoki aylantirilganda ro'yxat o'zi yangilanadi
  void _onLibraryChanged() {
    if (mounted && _granted && !_loading) _reload();
  }

  /// Kompyuterda papkalar darhol o'qiladi. Telefonda ruxsat avval berilgan bo'lsa
  /// ro'yxat yuklanadi, aks holda ruxsat so'rash tugmasi ko'rsatiladi.
  Future<void> _init() async {
    if (_filesOnly) {
      setState(() => _loading = false);
      return;
    }
    if (isDesktopApp) {
      await _reload();
      return;
    }
    bool granted = false;
    try {
      granted = (await PhotoManager.getPermissionState(requestOption: _permission)).hasAccess;
    } catch (_) {}
    if (!mounted) return;
    if (granted) {
      await _reload();
    } else {
      setState(() => _loading = false);
    }
  }

  Future<void> _requestPermission() async {
    setState(() => _loading = true);
    bool granted = false;
    try {
      granted = (await PhotoManager.requestPermissionExtend(requestOption: _permission)).hasAccess;
    } catch (_) {}
    if (!mounted) return;
    if (granted) {
      await _reload();
    } else {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Ruxsat berilmadi. Sozlamalardan ruxsat berishingiz mumkin."),
          action: SnackBarAction(label: "Sozlamalar", onPressed: PhotoManager.openSetting),
        ),
      );
    }
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _granted = true;
    });
    try {
      _items.clear();
      _thumbnails.clear();
      _page = 0;
      _hasMore = false;
      if (isDesktopApp) {
        await _loadFromFolders();
      } else {
        final albums = await PhotoManager.getAssetPathList(
          type: _type,
          onlyAll: true,
          filterOption: FilterOptionGroup(
            videoOption: const FilterOption(needTitle: true),
            audioOption: const FilterOption(needTitle: true),
            orders: const [OrderOption(type: OrderOptionType.createDate, asc: false)],
          ),
        );
        _album = albums.isEmpty ? null : albums.first;
        await _loadPage();
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadFromFolders() async {
    final files = await scanMediaFiles(widget.desktopRoots ?? desktopMediaRoots(widget.kind), widget.kind);
    for (final file in files) {
      String size = "";
      try {
        size = "${((await file.length()) / 1024 / 1024).toStringAsFixed(1)} MB • ";
      } catch (_) {}
      _items.add(_Entry(
        title: lastSegment(file.path),
        subtitle: "$size${lastSegment(file.parent.path)}",
        path: file.path,
      ));
    }
  }

  Future<void> _loadPage() async {
    final album = _album;
    if (album == null) return;
    final batch = await album.getAssetListPaged(page: _page, size: _pageSize);
    for (final asset in batch) {
      final title = asset.title;
      _items.add(_Entry(
        title: (title == null || title.isEmpty) ? (_isVideo ? "Video" : "Audio") : title,
        subtitle: _isVideo
            ? "${_duration(asset.duration)} • ${asset.width}×${asset.height}"
            : _duration(asset.duration),
        asset: asset,
      ));
    }
    _hasMore = batch.length == _pageSize;
    _page++;
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      await _loadPage();
    } catch (_) {
      _hasMore = false;
    }
    if (mounted) setState(() => _loadingMore = false);
  }

  void _play(List<QueueItem> items, int start) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PlayerScreen.queue(items: items, startIndex: start)),
    );
  }

  /// Ro'yxatdagi fayllar navbat bo'ladi: tanlangani birinchi, qolganlari ketma-ket (yoki aralash) o'ynaydi.
  /// Galereya fayllarining yo'li faqat o'ynaydigan paytda aniqlanadi.
  Future<void> _open(_Entry entry) async {
    try {
      final index = _items.indexOf(entry);
      final queue = [
        for (final e in _items)
          QueueItem(
            title: e.title,
            path: e.path,
            resolve: e.asset == null ? null : () async => (await e.asset!.file)?.path,
          ),
      ];
      if (index < 0) throw Exception("fayl topilmadi");
      if (!mounted) return;
      _play(queue, index);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Bu faylni ochib bo'lmadi")),
      );
    }
  }

  /// Ruxsatsiz ham ishlaydi: tizimning fayl tanlash oynasi orqali
  Future<void> _pickFromFiles() async {
    try {
      final file = _filesOnly
          ? await FilePicker.pickFile(type: FileType.custom, allowedExtensions: audioInputs)
          : await FilePicker.pickFile(type: _isVideo ? FileType.video : FileType.audio);
      final path = file?.path;
      if (file == null || path == null || !mounted) return;
      _play([QueueItem(title: file.name, path: path)], 0);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Faylni tanlab bo'lmadi: $e")),
      );
    }
  }

  String _duration(int seconds) {
    String two(int v) => v.toString().padLeft(2, '0');
    final int h = seconds ~/ 3600;
    final String ms = "${two((seconds % 3600) ~/ 60)}:${two(seconds % 60)}";
    return h > 0 ? "$h:$ms" : ms;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_filesOnly) return _filesOnlyCard();
    if (!_granted) return _permissionCard();
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        itemCount: _items.length + 2,
        itemBuilder: (context, i) {
          if (i == 0) return _header();
          if (i == _items.length + 1) return _footer();
          return _tile(_items[i - 1]);
        },
      ),
    );
  }

  Widget _filesOnlyCard() {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        AppCard(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Icon(Icons.library_music_rounded, size: 64, color: scheme.primary),
                const SizedBox(height: 10),
                const Text("Audio fayllar", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(
                  "iPhone'da audio fayllarni Fayllar ilovasidan tanlab tinglaysiz.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _pickFromFiles,
                  icon: const Icon(Icons.folder_open_rounded),
                  label: const Text("Fayllardan tanlash"),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _permissionCard() {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        AppCard(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Icon(_isVideo ? Icons.video_library_rounded : Icons.library_music_rounded,
                    size: 64, color: scheme.primary),
                const SizedBox(height: 10),
                Text(
                  _isVideo ? "Video fayllar" : "Audio fayllar",
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  _isVideo
                      ? "Telefoningizdagi videolar ro'yxatini ko'rsatish uchun ruxsat kerak."
                      : "Telefoningizdagi audio fayllar ro'yxatini ko'rsatish uchun ruxsat kerak.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _requestPermission,
                  icon: const Icon(Icons.lock_open_rounded),
                  label: const Text("Ruxsat berish"),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _pickFromFiles,
                  icon: const Icon(Icons.folder_open_rounded),
                  label: const Text("Fayllardan tanlash"),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _header() {
    final scheme = Theme.of(context).colorScheme;
    final String owner = isDesktopApp ? "Kompyuteringizdagi" : "Telefoningizdagi";
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _items.isEmpty
                  ? (_isVideo ? "Video fayllar topilmadi" : "Audio fayllar topilmadi")
                  : (_isVideo ? "$owner videolar" : "$owner audio fayllar"),
              style: TextStyle(fontWeight: FontWeight.bold, color: scheme.onSurface),
            ),
          ),
          TextButton.icon(
            onPressed: _pickFromFiles,
            icon: const Icon(Icons.folder_open_rounded, size: 18),
            label: const Text("Fayllardan"),
          ),
        ],
      ),
    );
  }

  Widget _footer() {
    if (_hasMore) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: _loadingMore
            ? const Center(child: CircularProgressIndicator())
            : OutlinedButton(onPressed: _loadMore, child: const Text("Yana ko'rsatish")),
      );
    }
    return const SizedBox(height: 8);
  }

  Widget _tile(_Entry entry) {
    final scheme = Theme.of(context).colorScheme;
    final asset = entry.asset;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          leading: (_isVideo && asset != null) ? _thumbnail(asset) : _badge(scheme),
          title: Text(entry.title, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text(entry.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: Icon(Icons.play_circle_fill_rounded, size: 34, color: scheme.primary),
          onTap: () => _open(entry),
        ),
      ),
    );
  }

  Widget _badge(ColorScheme scheme) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primary, scheme.tertiary],
        ),
      ),
      child: Icon(_isVideo ? Icons.movie_rounded : Icons.music_note_rounded, color: scheme.onPrimary),
    );
  }

  Widget _thumbnail(AssetEntity asset) {
    final scheme = Theme.of(context).colorScheme;
    final future = _thumbnails.putIfAbsent(
      asset.id,
      () => asset.thumbnailDataWithSize(const ThumbnailSize(240, 160)).catchError((Object _) => null),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 84,
        height: 56,
        child: FutureBuilder<Uint8List?>(
          future: future,
          builder: (context, snapshot) {
            final data = snapshot.data;
            if (data == null) {
              return ColoredBox(
                color: scheme.surfaceContainerHighest,
                child: Icon(Icons.movie_rounded, color: scheme.onSurfaceVariant),
              );
            }
            return Image.memory(data, fit: BoxFit.cover, gaplessPlayback: true);
          },
        ),
      ),
    );
  }
}
