import 'package:flutter/material.dart';

import '../config.dart';
import '../downloader/detected.dart';
import '../downloader/job_runner.dart';
import '../downloader/manager.dart';
import '../services/profile_service.dart';
import 'subscription_screen.dart';

/// Video yuklash oynasi: nom, sifat, bo'laklar soni, kodek (PRO) va boshlash tugmasi.
Future<void> showDownloadSheet(
  BuildContext context, {
  required DetectedMedia media,
  required String title,
  required Map<String, String> headers,
  DownloadManager? manager,
  bool? pro,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => DownloadOptions(
      media: media,
      title: title,
      headers: headers,
      manager: manager ?? downloads,
      pro: pro ?? profile.proActive,
    ),
  );
}

String formatBytes(int? bytes) {
  if (bytes == null) return "";
  if (bytes >= 1024 * 1024 * 1024) return "${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB";
  if (bytes >= 1024 * 1024) return "${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB";
  return "${(bytes / 1024).round()} KB";
}

String formatSeconds(double? seconds) {
  if (seconds == null) return "";
  final d = Duration(seconds: seconds.round());
  String two(int v) => v.toString().padLeft(2, '0');
  return d.inHours > 0 ? "${d.inHours}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}" : "${two(d.inMinutes)}:${two(d.inSeconds % 60)}";
}

class DownloadOptions extends StatefulWidget {
  final DetectedMedia media;
  final String title;
  final Map<String, String> headers;
  final DownloadManager manager;
  final bool pro;
  const DownloadOptions({
    super.key,
    required this.media,
    required this.title,
    required this.headers,
    required this.manager,
    required this.pro,
  });

  @override
  State<DownloadOptions> createState() => _DownloadOptionsState();
}

class _DownloadOptionsState extends State<DownloadOptions> {
  late final TextEditingController _title = TextEditingController(text: widget.title);
  late int _segments = widget.pro ? proDefaultSegments : freeDefaultSegments;
  OutputCodec _codec = OutputCodec.original;
  int _variant = 0;
  bool _starting = false;
  String? _blocked;
  int? _remaining;
  bool _quotaLoaded = false;

  @override
  void initState() {
    super.initState();
    widget.manager.remainingThisWeek(widget.pro).then((v) {
      if (mounted) setState(() {
        _remaining = v;
        _quotaLoaded = true;
      });
    });
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final m = widget.media;
    final name = _title.text.trim();
    if (name.isEmpty) {
      setState(() => _blocked = "Fayl nomini yozing");
      return;
    }
    setState(() {
      _starting = true;
      _blocked = null;
    });
    final variant = m.qualities.isEmpty ? null : m.qualities[_variant.clamp(0, m.qualities.length - 1)];
    final outcome = await widget.manager.start(
      DownloadRequest(
        url: m.url,
        title: name,
        headers: widget.headers,
        kind: m.mediaKind,
        segments: _segments,
        codec: _codec,
        pageUrl: m.page.toString(),
        variantUrl: variant?.url,
      ),
      pro: widget.pro,
    );
    if (!mounted) return;
    if (outcome.ok) {
      final messenger = ScaffoldMessenger.maybeOf(context);
      Navigator.of(context).pop();
      messenger?.showSnackBar(const SnackBar(content: Text("Yuklash boshlandi. Jarayonni \"Yuklash\" bo'limida ko'rasiz.")));
    } else {
      setState(() {
        _starting = false;
        _blocked = outcome.blocked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.media;
    final pro = widget.pro;
    final scheme = Theme.of(context).colorScheme;
    final info = [
      m.typeLabel,
      if (m.bytes != null) formatBytes(m.bytes),
      if (m.seconds != null) formatSeconds(m.seconds),
    ].join(" • ");
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Videoni yuklash", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(info, style: TextStyle(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 14),
          TextField(
            key: const Key("dlTitle"),
            controller: _title,
            decoration: const InputDecoration(labelText: "Fayl nomi", suffixText: ".mp4", prefixIcon: Icon(Icons.edit_outlined)),
          ),
          if (m.qualities.length > 1) ...[
            const SizedBox(height: 14),
            const Text("Sifat", style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                for (var i = 0; i < m.qualities.length; i++)
                  ChoiceChip(
                    key: Key("quality_$i"),
                    label: Text(m.qualities[i].label),
                    selected: _variant == i,
                    onSelected: (_) => setState(() => _variant = i),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              const Text("Bo'laklar soni", style: TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              Text("$_segments ta", key: const Key("segmentsLabel"), style: const TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
          if (pro)
            Slider(
              key: const Key("segmentsSlider"),
              min: freeDefaultSegments.toDouble(),
              max: proMaxSegments.toDouble(),
              divisions: proMaxSegments - freeDefaultSegments,
              value: _segments.toDouble(),
              label: "$_segments",
              onChanged: (v) => setState(() => _segments = v.round()),
            )
          else
            _lockedRow(context, "Bepul tarifda $freeMaxSegments ta bo'lak. PRO'da $proMaxSegments tagacha: tezroq yuklanadi."),
          const SizedBox(height: 8),
          const Text("Saqlash formati", style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          if (pro)
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final c in OutputCodec.values)
                  ChoiceChip(
                    key: Key("codec_${c.name}"),
                    label: Text(c.label),
                    selected: _codec == c,
                    onSelected: (_) => setState(() => _codec = c),
                  ),
              ],
            )
          else
            _lockedRow(context, "MP4. H.264 yoki H.265 tanlash faqat PRO obunada."),
          if (pro && _codec != OutputCodec.original)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text("Qayta kodlash telefonda biroz vaqt oladi.", style: TextStyle(fontSize: 12)),
            ),
          const SizedBox(height: 14),
          Text(
            quotaLabel(pro, _quotaLoaded ? _remaining : null),
            key: const Key("quotaLabel"),
            style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600),
          ),
          if (_blocked != null) ...[
            const SizedBox(height: 10),
            Container(
              key: const Key("dlBlocked"),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(14)),
              child: Text(_blocked!, style: TextStyle(color: scheme.onErrorContainer)),
            ),
            if (!pro)
              TextButton.icon(
                key: const Key("dlGetPro"),
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SubscriptionScreen()));
                },
                icon: const Icon(Icons.workspace_premium_rounded),
                label: const Text("PRO olish"),
              ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const Key("dlStart"),
              onPressed: _starting ? null : _start,
              icon: const Icon(Icons.download_rounded),
              label: Text(_starting ? "Boshlanmoqda..." : "Yuklashni boshlash"),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            "Faqat o'zingizga tegishli yoki yuklashga ruxsat berilgan videolarni yuklang. DRM bilan himoyalangan videolar yuklanmaydi.",
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _lockedRow(BuildContext context, String text) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(Icons.lock_outline_rounded, size: 18, color: scheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13))),
      ],
    );
  }
}
