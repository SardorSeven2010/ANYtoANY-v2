import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../downloader/detected.dart';
import '../downloader/manager.dart';
import '../platform.dart';
import '../services/profile_service.dart';
import '../widgets/glass.dart';
import 'browser_screen.dart';
import 'download_sheets.dart';
import 'subscription_screen.dart';
import '../player/play_queue.dart';
import 'player_screen.dart';
import 'viewers.dart';

/// Saqlangan joy: "Download/CORE" yoki papka nomi (foydalanuvchi faylni qayerdan topishini bilsin)
String savedWhere(String path) {
  final parts = path.split(RegExp(r'[/\\]')).where((p) => p.isNotEmpty).toList();
  if (parts.length < 3) return path;
  final dir = parts.sublist(0, parts.length - 1);
  final tail = dir.length >= 2 ? "${dir[dir.length - 2]}/${dir.last}" : dir.last;
  return tail;
}

/// Brauzer (WebView) faqat telefonda ishlaydi
bool get browserAvailable => isAndroidApp || isIOSApp;

// ================= 4-BO'LIM: VIDEO YUKLASH =================
class DownloaderTab extends StatefulWidget {
  final DownloadManager? manager;
  final MediaDetector? detector;
  const DownloaderTab({super.key, this.manager, this.detector});

  @override
  State<DownloaderTab> createState() => _DownloaderTabState();
}

class _DownloaderTabState extends State<DownloaderTab> {
  late final DownloadManager _manager = widget.manager ?? downloads;
  late final MediaDetector _detector = widget.detector ?? MediaDetector();
  final TextEditingController _link = TextEditingController();
  bool _busy = false;
  String? _message;
  int? _remaining;

  @override
  void initState() {
    super.initState();
    _manager.load();
    _manager.addListener(_refreshQuota);
    _refreshQuota();
  }

  @override
  void dispose() {
    _manager.removeListener(_refreshQuota);
    _link.dispose();
    super.dispose();
  }

  Future<void> _refreshQuota() async {
    final r = await _manager.remainingThisWeek(profile.proActive);
    if (mounted && r != _remaining) setState(() => _remaining = r);
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text != null && text.isNotEmpty) setState(() => _link.text = text);
  }

  /// Havola to'g'ridan-to'g'ri video bo'lsa - yuklash oynasi; aks holda (sayt sahifasi) - brauzer
  Future<void> _submit() async {
    final text = _link.text.trim();
    if (text.isEmpty) {
      setState(() => _message = "Avval video yoki sayt havolasini joylang");
      return;
    }
    final uri = addressFromInput(text);
    setState(() {
      _busy = true;
      _message = null;
    });
    final media = await _detector.inspect(uri.toString());
    if (!mounted) return;
    setState(() => _busy = false);
    if (media != null) {
      if (!media.downloadable) {
        setState(() => _message = media.error ?? "Bu havolani yuklab bo'lmaydi");
        return;
      }
      await showDownloadSheet(context, media: media, title: _detector.suggestedTitle(media), headers: const {}, manager: _manager);
      return;
    }
    if (browserAvailable) {
      await _openBrowser(uri);
    } else {
      setState(() => _message =
          "Bu sahifa havolasi, to'g'ridan-to'g'ri video emas. Kompyuterda faqat video fayl yoki .m3u8 / .mpd havolasi yuklanadi. Sayt sahifalaridan yuklash uchun telefon ilovasidagi brauzerdan foydalaning.");
    }
  }

  Future<void> _openBrowser([Uri? initial]) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => BrowserScreen(initial: initial, manager: _manager)));
    _refreshQuota();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: Listenable.merge([_manager, profile]),
      builder: (context, _) {
        final jobs = _manager.jobs;
        final pro = profile.proActive;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _inputCard(scheme),
            const SizedBox(height: 10),
            _quotaRow(scheme, pro),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text("Yuklashlar", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                if (jobs.any((j) => j.isFinished))
                  TextButton(key: const Key("clearFinished"), onPressed: _manager.clearFinished, child: const Text("Tozalash")),
              ],
            ),
            if (jobs.isEmpty)
              AppCard(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    browserAvailable
                        ? "Hali yuklash yo'q. Yuqorida havolani joylang yoki brauzerda videoni oching: \"Yuklash\" tugmasi o'zi paydo bo'ladi."
                        : "Hali yuklash yo'q. Video fayl yoki .m3u8 havolasini joylang.",
                    key: const Key("noDownloads"),
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ),
              ),
            for (final job in jobs) ...[
              _JobCard(job: job, manager: _manager),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 6),
            Text(
              "Faqat o'zingizga tegishli yoki yuklashga ruxsat berilgan videolarni yuklang. DRM bilan himoyalangan videolar (Netflix va shu kabi) yuklanmaydi.",
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ],
        );
      },
    );
  }

  Widget _inputCard(ColorScheme scheme) {
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text("Video yuklash", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
              "Havolani joylang yoki brauzerda saytni oching. Video 6 dan 18 gacha bo'lakka bo'lib, tez yuklanadi.",
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key("linkField"),
              controller: _link,
              keyboardType: TextInputType.url,
              autocorrect: false,
              textInputAction: TextInputAction.go,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                hintText: "https://... (video, .m3u8 yoki sayt havolasi)",
                prefixIcon: const Icon(Icons.link_rounded),
                suffixIcon: IconButton(key: const Key("pasteLink"), tooltip: "Joylash", icon: const Icon(Icons.content_paste_rounded), onPressed: _paste),
              ),
            ),
            if (_message != null) ...[
              const SizedBox(height: 8),
              Text(_message!, key: const Key("downloaderMessage"), style: TextStyle(color: scheme.error, fontSize: 13)),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    key: const Key("submitLink"),
                    onPressed: _busy ? null : _submit,
                    icon: _busy
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.download_rounded),
                    label: Text(_busy ? "Tekshirilmoqda..." : "Yuklash"),
                  ),
                ),
                if (browserAvailable) ...[
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    key: const Key("openBrowser"),
                    onPressed: () => _openBrowser(),
                    icon: const Icon(Icons.public_rounded),
                    label: const Text("Brauzer"),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _quotaRow(ColorScheme scheme, bool pro) {
    return Row(
      children: [
        Icon(pro ? Icons.workspace_premium_rounded : Icons.timelapse_rounded, size: 18, color: pro ? Colors.amber.shade600 : scheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Expanded(
          child: Text(quotaLabel(pro, _remaining), key: const Key("weeklyQuota"), style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
        ),
        if (!pro)
          TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SubscriptionScreen())),
            child: const Text("PRO: cheksiz"),
          ),
      ],
    );
  }
}

class _JobCard extends StatelessWidget {
  final DownloadJob job;
  final DownloadManager manager;
  const _JobCard({required this.job, required this.manager});

  String _speed(double v) => v >= 1024 * 1024 ? "${(v / (1024 * 1024)).toStringAsFixed(1)} MB/s" : "${(v / 1024).round()} KB/s";

  String _eta(Duration? d) {
    if (d == null) return "";
    if (d.inHours > 0) return "${d.inHours} soat ${d.inMinutes % 60} daq";
    if (d.inMinutes > 0) return "${d.inMinutes} daq ${d.inSeconds % 60} s";
    return "${d.inSeconds} s";
  }

  String _stageLabel() => switch (job.stage?.name) {
        "probing" => "Tekshirilmoqda...",
        "merging" => "Birlashtirilmoqda...",
        "converting" => "Kodlanmoqda...",
        "saving" => "Galereyaga saqlanmoqda...",
        _ => "",
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: job,
      builder: (context, _) {
        final running = job.status == JobStatus.running;
        final queued = job.status == JobStatus.queued;
        final done = job.status == JobStatus.done;
        final stage = _stageLabel();
        String detail;
        if (queued) {
          detail = "Navbatda";
        } else if (running) {
          final parts = job.activeSegments > 0 ? "${job.activeSegments} bo'lak" : "";
          detail = stage.isNotEmpty
              ? stage
              : [
                  if (job.fraction != null) "${(job.fraction! * 100).round()}%",
                  if (job.received > 0) formatBytes(job.received),
                  if (job.speed > 0) _speed(job.speed),
                  if (_eta(job.eta).isNotEmpty) _eta(job.eta),
                  parts,
                ].where((s) => s.isNotEmpty).join(" • ");
        } else if (done) {
          detail = [
            "Tayyor",
            if (job.outputBytes != null) formatBytes(job.outputBytes),
            job.inGallery ? "Galereyada" : (job.outputPath != null ? savedWhere(job.outputPath!) : ""),
          ].where((e) => e.isNotEmpty).join(" • ");
          if (job.note != null) detail = "$detail\n${job.note}";
        } else if (job.status == JobStatus.failed) {
          detail = job.error ?? "Xato";
        } else {
          detail = "Bekor qilindi";
        }
        return AppCard(
          key: Key("job_${job.id}"),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      done ? Icons.check_circle_rounded : (job.status == JobStatus.failed ? Icons.error_rounded : Icons.downloading_rounded),
                      color: done ? Colors.green : (job.status == JobStatus.failed ? scheme.error : scheme.primary),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(job.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
                    if (running || queued) IconButton(key: Key("cancel_${job.id}"), tooltip: "To'xtatish", icon: const Icon(Icons.close_rounded), onPressed: () => manager.cancel(job.id)),
                    if (done)
                      IconButton(
                        key: Key("play_${job.id}"),
                        tooltip: "Ijro etish",
                        icon: const Icon(Icons.play_circle_rounded),
                        onPressed: job.outputPath == null ? null : () => _play(context),
                      ),
                    if (job.status == JobStatus.failed || job.status == JobStatus.canceled)
                      IconButton(key: Key("retry_${job.id}"), tooltip: "Qayta urinish", icon: const Icon(Icons.refresh_rounded), onPressed: () => manager.retry(job.id)),
                    if (job.isFinished)
                      IconButton(
                        key: Key("remove_${job.id}"),
                        tooltip: "O'chirish",
                        icon: const Icon(Icons.delete_outline_rounded),
                        onPressed: () => _confirmRemove(context),
                      ),
                  ],
                ),
                if (running)
                  Padding(
                    padding: const EdgeInsets.only(right: 8, top: 4, bottom: 4),
                    child: LinearProgressIndicator(value: stage.isEmpty ? job.fraction : null, minHeight: 6, borderRadius: BorderRadius.circular(3)),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 2, right: 8),
                  child: Text(detail, key: Key("detail_${job.id}"), style: TextStyle(fontSize: 12, color: job.status == JobStatus.failed ? scheme.error : scheme.onSurfaceVariant)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Tayyor yuklashlar navbat bo'ladi: bitta tugagach keyingisi o'zi boshlanadi
  void _play(BuildContext context) {
    final done = manager.jobs.where((j) => j.status == JobStatus.done && j.outputPath != null).toList();
    final index = done.indexWhere((j) => j.id == job.id);
    if (index < 0) {
      openFile(context, job.outputPath!);
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlayerScreen.queue(
        items: [for (final j in done) QueueItem(title: j.title, path: j.outputPath)],
        startIndex: index,
      ),
    ));
  }

  Future<void> _confirmRemove(BuildContext context) async {
    if (!job.isFinished) return;
    if (job.status != JobStatus.done || job.outputPath == null) {
      await manager.remove(job.id);
      return;
    }
    final choice = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Ro'yxatdan olib tashlash"),
        content: Text("\"${job.title}\" ro'yxatdan olib tashlansinmi? Faylni ham o'chirishingiz mumkin."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Bekor qilish")),
          TextButton(key: const Key("removeKeep"), onPressed: () => Navigator.pop(context, "keep"), child: const Text("Faqat ro'yxatdan")),
          FilledButton(key: const Key("removeDelete"), onPressed: () => Navigator.pop(context, "delete"), child: const Text("Faylni ham")),
        ],
      ),
    );
    if (choice == null) return;
    await manager.remove(job.id, deleteFile: choice == "delete");
  }
}
