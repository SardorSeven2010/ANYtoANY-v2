import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import 'player_screen.dart';

enum MediaKind { video, audio }

// ================= VIDEO / AUDIO FAYLLAR BO'LIMI =================
// Telefondagi video yoki audio fayllar ro'yxati. Faylni bossangiz pleyerda ochiladi.
class MediaLibraryTab extends StatefulWidget {
  final MediaKind kind;
  const MediaLibraryTab({super.key, required this.kind});

  @override
  State<MediaLibraryTab> createState() => _MediaLibraryTabState();
}

class _MediaLibraryTabState extends State<MediaLibraryTab> {
  static const int _pageSize = 80;

  final List<AssetEntity> _items = [];
  final Map<String, Future<Uint8List?>> _thumbnails = {};
  AssetPathEntity? _album;
  bool _loading = true;
  bool _loadingMore = false;
  bool _granted = false;
  bool _hasMore = false;
  int _page = 0;

  bool get _isVideo => widget.kind == MediaKind.video;
  RequestType get _type => _isVideo ? RequestType.video : RequestType.audio;

  PermissionRequestOption get _permission => PermissionRequestOption(
        androidPermission: AndroidPermission(type: _type, mediaLocation: false),
      );

  @override
  void initState() {
    super.initState();
    _init();
  }

  /// Ruxsat avval berilgan bo'lsa ro'yxatni darhol yuklaydi, aks holda so'rash tugmasini ko'rsatadi
  Future<void> _init() async {
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
      _items.clear();
      _thumbnails.clear();
      _page = 0;
      _hasMore = false;
      await _loadPage();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadPage() async {
    final album = _album;
    if (album == null) return;
    final batch = await album.getAssetListPaged(page: _page, size: _pageSize);
    _items.addAll(batch);
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

  void _play(String path, String title) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PlayerScreen(path: path, title: title)),
    );
  }

  Future<void> _openAsset(AssetEntity asset) async {
    try {
      final file = await asset.file;
      if (!mounted) return;
      if (file == null) throw Exception("fayl topilmadi");
      _play(file.path, _titleOf(asset));
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
      final file = await FilePicker.pickFile(type: _isVideo ? FileType.video : FileType.audio);
      final path = file?.path;
      if (file == null || path == null || !mounted) return;
      _play(path, file.name);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Faylni tanlab bo'lmadi: $e")),
      );
    }
  }

  String _titleOf(AssetEntity asset) {
    final title = asset.title;
    return (title == null || title.isEmpty) ? (_isVideo ? "Video" : "Audio") : title;
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

  Widget _permissionCard() {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _items.isEmpty
                  ? (_isVideo ? "Video fayllar topilmadi" : "Audio fayllar topilmadi")
                  : (_isVideo ? "Telefoningizdagi videolar" : "Telefoningizdagi audio fayllar"),
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

  Widget _tile(AssetEntity asset) {
    final scheme = Theme.of(context).colorScheme;
    final String subtitle = _isVideo
        ? "${_duration(asset.duration)} • ${asset.width}×${asset.height}"
        : _duration(asset.duration);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          leading: _isVideo ? _thumbnail(asset) : _audioBadge(scheme),
          title: Text(_titleOf(asset), maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text(subtitle),
          trailing: Icon(Icons.play_circle_fill_rounded, size: 34, color: scheme.primary),
          onTap: () => _openAsset(asset),
        ),
      ),
    );
  }

  Widget _audioBadge(ColorScheme scheme) {
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
      child: Icon(Icons.music_note_rounded, color: scheme.onPrimary),
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
