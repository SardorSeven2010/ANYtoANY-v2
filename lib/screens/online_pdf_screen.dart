import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../services/media_tools.dart';
import '../services/online_pdf.dart';
import '../services/profile_service.dart';
import 'subscription_screen.dart';

// ================= PDF -> WORD / POWERPOINT / EXCEL (INTERNET ORQALI) =================
// Faqat PRO obunachilar uchun. Bir nechta PDF ni birdaniga tanlash mumkin.
class OnlinePdfScreen extends StatefulWidget {
  const OnlinePdfScreen({super.key});

  @override
  State<OnlinePdfScreen> createState() => _OnlinePdfScreenState();
}

class _OnlinePdfScreenState extends State<OnlinePdfScreen> {
  List<PlatformFile> _files = [];
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
      final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ["pdf"]);
      final pdfs = picked.where((f) => f.path != null && isPdfFile(f.name)).toList();
      if (pdfs.isNotEmpty && mounted) setState(() => _files = pdfs);
    } catch (e) {
      _show("Fayllarni tanlab bo'lmadi: $e");
    }
  }

  Future<void> _convert() async {
    if (_files.isEmpty || _busy) return;
    final files = List<PlatformFile>.of(_files);
    setState(() {
      _busy = true;
      _stage = "Tayyorlanmoqda...";
    });

    int done = 0;
    String? error;
    String savedTo = "";
    try {
      final outDir = await resolveOutputDir();
      savedTo = outputDirLabel(outDir);
      final usedPaths = <String>{};
      for (int i = 0; i < files.length; i++) {
        final file = files[i];
        final outPath = uniquePath(outDir, "${baseNameOf(file.name)}_ANYtoANY", _format, usedPaths);
        final String prefix = files.length > 1 ? "${i + 1}/${files.length}: " : "";
        try {
          await convertPdfOnline(
            pdfPath: file.path!,
            targetFormat: _format,
            outPath: outPath,
            onStage: (stage) {
              if (mounted) setState(() => _stage = "$prefix$stage");
            },
          );
        } catch (_) {
          await deleteQuietly(outPath);
          rethrow;
        }
        done++;
        if (mounted) {
          setState(() {
            _results.insert(0, outPath);
            _files.remove(file);
          });
        }
      }
    } on OnlinePdfException catch (e) {
      error = e.message;
    } catch (_) {
      error = "Internet bilan bog'lanib bo'lmadi. Qayta urinib ko'ring.";
    }
    if (mounted) setState(() => _busy = false);

    if (error == null) {
      _show("Tayyor! $done ta fayl $savedTo saqlandi.");
    } else if (done > 0) {
      _show("$done ta fayl $savedTo saqlandi, keyin to'xtadi: $error");
    } else {
      _show(error);
    }
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
                "PDF fayllarni tahrirlanadigan Word, PowerPoint va Excel hujjatiga aylantirish PRO obunada ochiladi.",
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
                label: Text(_files.isEmpty ? "PDF fayllarni tanlash" : "Boshqa fayllarni tanlash"),
              ),
              for (final file in _files)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.picture_as_pdf_rounded),
                  title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: IconButton(
                    icon: const Icon(Icons.close_rounded),
                    tooltip: "Olib tashlash",
                    onPressed: _busy ? null : () => setState(() => _files.remove(file)),
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
                onPressed: (_files.isEmpty || _busy) ? null : _convert,
                icon: const Icon(Icons.bolt_rounded),
                label: Text(_busy ? _stage : "Aylantirish (${_files.length} ta)"),
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
