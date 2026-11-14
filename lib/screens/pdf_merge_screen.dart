import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf_combiner/exception/pdf_combiner_exception.dart';
import 'package:pdf_combiner/models/merge_input.dart';
import 'package:pdf_combiner/pdf_combiner.dart';

import '../app_theme.dart';
import '../config.dart';
import '../platform.dart';
import '../services/media_tools.dart';
import '../services/profile_service.dart';
import 'viewers.dart';

// ================= PDF FAYLLARNI BIRLASHTIRISH (INTERNETSIZ) =================
class PdfMergeScreen extends StatefulWidget {
  const PdfMergeScreen({super.key});

  @override
  State<PdfMergeScreen> createState() => _PdfMergeScreenState();
}

class _PdfMergeScreenState extends State<PdfMergeScreen> {
  final List<PlatformFile> _files = [];
  final List<String> _results = [];
  bool _busy = false;

  void _show(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(duration: const Duration(seconds: 5), content: Text(message)),
    );
  }

  Future<void> _addFiles() async {
    List<PlatformFile> picked;
    try {
      picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ["pdf"]);
    } catch (e) {
      _show("Fayllarni tanlab bo'lmadi: $e");
      return;
    }
    picked = picked.where((f) => f.path != null && isPdfFile(f.name)).toList();
    if (picked.isEmpty || !mounted) return;

    final combined = [..._files, ...picked];
    if (!profile.proActive && combined.length > freeFileLimit) {
      _show("Bepul tarifda $freeFileLimit tagacha fayl! Ko'proq fayl uchun PRO obunani yoqing.");
    }
    setState(() {
      _files
        ..clear()
        ..addAll(profile.proActive ? combined : combined.take(freeFileLimit));
    });
  }

  Future<void> _merge() async {
    if (_files.length < 2 || _busy) return;
    setState(() => _busy = true);
    String? tempPath;
    try {
      // Avval ilovaning vaqtinchalik papkasida birlashtiriladi, keyin Download ga ko'chiriladi
      final tempDir = await getTemporaryDirectory();
      tempPath = joinPath(tempDir.path, "anytoany_merge_${DateTime.now().microsecondsSinceEpoch}.pdf");
      await PdfCombiner.mergeMultiplePDFs(
        inputs: [for (final f in _files) MergeInput.path(f.path!)],
        outputPath: tempPath,
      );

      final outDir = await resolveOutputDir();
      final outPath = uniquePath(outDir, "Birlashtirilgan_CORE", "pdf", <String>{});
      await File(tempPath).copy(outPath);
      if (mounted) {
        setState(() {
          _results.insert(0, outPath);
          _files.clear();
        });
      }
      _show("Tayyor! Fayl ${outputDirLabel(outDir)} saqlandi.");
    } on PdfCombinerException catch (e) {
      _show("Birlashtirib bo'lmadi: ${e.message}");
    } catch (e) {
      _show("Birlashtirib bo'lmadi: $e");
    } finally {
      if (tempPath != null) await deleteQuietly(tempPath);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppScaffold(
      appBar: AppBar(title: const Text("PDF birlashtirish")),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(
          children: [
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: _busy ? null : _addFiles,
                icon: const Icon(Icons.add_rounded),
                label: const Text("PDF fayl qo'shish"),
              ),
            ),
            const SizedBox(height: 10),
            if (_busy) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 10),
            ],
            Expanded(
              child: (_files.isEmpty && _results.isEmpty)
                  ? Center(
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.merge_rounded, size: 44, color: scheme.primary),
                              const SizedBox(height: 10),
                              Text(
                                "Ikki yoki undan ko'p PDF fayl tanlang.\n"
                                "Ular ro'yxatdagi tartibda bitta PDF ga birlashtiriladi.",
                                textAlign: TextAlign.center,
                                style: TextStyle(color: scheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  : Card(
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          if (_files.isNotEmpty) ...[
                            _sectionTitle("Birlashtirish tartibi (surib o'zgartiring)"),
                            Flexible(
                              child: ReorderableListView.builder(
                                shrinkWrap: true,
                                buildDefaultDragHandles: !_busy,
                                itemCount: _files.length,
                                onReorderItem: (oldIndex, newIndex) {
                                  setState(() => _files.insert(newIndex, _files.removeAt(oldIndex)));
                                },
                                itemBuilder: (context, i) => _fileTile(i),
                              ),
                            ),
                          ],
                          if (_results.isNotEmpty) ...[
                            _sectionTitle("Tayyor fayllar"),
                            for (final path in _results.take(5)) _resultTile(path),
                          ],
                        ],
                      ),
                    ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: (_files.length < 2 || _busy) ? null : _merge,
                icon: const Icon(Icons.merge_rounded),
                label: Text(_busy ? "Birlashtirilmoqda..." : "Birlashtirish (${_files.length} ta)"),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(
          text,
          style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary),
        ),
      ),
    );
  }

  Widget _fileTile(int index) {
    final file = _files[index];
    final path = file.path;
    final double sizeMb = (file.lengthSync() ?? 0) / 1024 / 1024;
    return ListTile(
      key: ValueKey("${file.path}#$index"),
      leading: CircleAvatar(radius: 14, child: Text("${index + 1}", style: const TextStyle(fontSize: 13))),
      title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text("${sizeMb.toStringAsFixed(2)} MB"),
      trailing: Padding(
        // o'ng chetdagi surish belgisiga joy qoldiriladi
        padding: const EdgeInsets.only(right: 28),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (path != null)
              IconButton(
                icon: const Icon(Icons.visibility_rounded),
                tooltip: "Ochish",
                onPressed: () => openFile(context, path),
              ),
            IconButton(
              icon: const Icon(Icons.close_rounded),
              tooltip: "Olib tashlash",
              onPressed: _busy ? null : () => setState(() => _files.removeAt(index)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resultTile(String path) {
    return ListTile(
      leading: Icon(Icons.check_circle_rounded, color: Theme.of(context).colorScheme.primary),
      title: Text(fileNameOf(path), maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(path, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: IconButton(
        icon: const Icon(Icons.visibility_rounded),
        tooltip: "Ochish",
        onPressed: () => openFile(context, path),
      ),
    );
  }
}
