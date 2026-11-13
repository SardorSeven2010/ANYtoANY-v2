import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../services/media_tools.dart';
import '../services/online_pdf.dart';
import '../services/profile_service.dart';
import 'subscription_screen.dart';

// ================= PDF -> WORD / POWERPOINT / EXCEL (INTERNET ORQALI) =================
class OnlinePdfScreen extends StatefulWidget {
  const OnlinePdfScreen({super.key});

  @override
  State<OnlinePdfScreen> createState() => _OnlinePdfScreenState();
}

class _OnlinePdfScreenState extends State<OnlinePdfScreen> {
  PlatformFile? _file;
  String _format = onlineTargets.first.format;
  bool _busy = false;
  String _stage = "";
  final List<String> _results = [];

  void _show(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(duration: const Duration(seconds: 6), content: Text(message)),
    );
  }

  Future<void> _pick() async {
    try {
      final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ["pdf"]);
      if (file != null && mounted) setState(() => _file = file);
    } catch (e) {
      _show("Faylni tanlab bo'lmadi: $e");
    }
  }

  Future<void> _convert() async {
    final file = _file;
    final path = file?.path;
    if (file == null || path == null || _busy) return;
    if (!isPdfFile(file.name)) {
      _show("Faqat PDF fayl tanlang.");
      return;
    }

    setState(() {
      _busy = true;
      _stage = "Tayyorlanmoqda...";
    });
    String? outPath;
    try {
      final outDir = await resolveOutputDir();
      outPath = uniquePath(outDir, "${baseNameOf(file.name)}_ANYtoANY", _format, <String>{});
      await convertPdfOnline(
        pdfPath: path,
        targetFormat: _format,
        outPath: outPath,
        onStage: (stage) {
          if (mounted) setState(() => _stage = stage);
        },
      );
      final String saved = outPath;
      if (mounted) setState(() => _results.insert(0, saved));
      _show("Tayyor! Fayl ${outputDirLabel(outDir)} saqlandi.");
    } on OnlinePdfException catch (e) {
      if (outPath != null) await deleteQuietly(outPath);
      _show(e.message);
    } catch (_) {
      if (outPath != null) await deleteQuietly(outPath);
      _show("Internet bilan bog'lanib bo'lmadi. Qayta urinib ko'ring.");
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      appBar: AppBar(title: const Text("PDF dan Word / PowerPoint")),
      body: ListenableBuilder(
        listenable: profile,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: profile.proActive ? _converter(context) : _locked(context),
        ),
      ),
    );
  }

  List<Widget> _locked(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(Icons.workspace_premium_rounded, size: 64, color: Colors.amber.shade600),
              const SizedBox(height: 10),
              const Text(
                "Faqat PRO obunachilar uchun",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                "PDF faylni tahrirlanadigan Word, PowerPoint va Excel hujjatiga aylantirish PRO obunada ochiladi.",
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
                ),
                icon: const Icon(Icons.workspace_premium_rounded),
                label: const Text("PRO obuna olish"),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  List<Widget> _converter(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final file = _file;
    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.cloud_sync_rounded, color: scheme.primary),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      "PDF internet orqali tahrirlanadigan hujjatga aylantiriladi. Internet kerak bo'ladi.",
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: _busy ? null : _pick,
                icon: const Icon(Icons.picture_as_pdf_rounded),
                label: Text(
                  file == null ? "PDF fayl tanlash" : file.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 14),
              const Text("Qaysi formatga:", style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [
                  for (final t in onlineTargets) ButtonSegment<String>(value: t.format, label: Text(t.title)),
                ],
                selected: {_format},
                onSelectionChanged: _busy ? null : (s) => setState(() => _format = s.first),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: (file == null || _busy) ? null : _convert,
                icon: const Icon(Icons.bolt_rounded),
                label: Text(_busy ? _stage : "Aylantirish"),
              ),
              if (_busy) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
              ],
            ],
          ),
        ),
      ),
      if (_results.isNotEmpty) ...[
        const SizedBox(height: 16),
        Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  "Tayyor fayllar",
                  style: TextStyle(fontWeight: FontWeight.bold, color: scheme.primary),
                ),
              ),
              for (final path in _results)
                ListTile(
                  leading: Icon(Icons.check_circle_rounded, color: scheme.primary),
                  title: Text(fileNameOf(path), maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(path, maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
            ],
          ),
        ),
      ],
    ];
  }
}
