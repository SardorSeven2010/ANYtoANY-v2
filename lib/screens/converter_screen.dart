import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../config.dart';
import '../platform.dart';
import '../services/media_tools.dart';
import '../services/profile_service.dart';
import 'subscription_screen.dart';
import 'viewers.dart';

/// Konvertor turlari. Har biri alohida ishga javob beradi, ular bir-birini takrorlamaydi.
enum ConverterMode {
  /// Video -> boshqa video format yoki GIF (kodek tanlash bilan)
  video,

  /// Video -> audio (ovozni ajratib olish)
  videoToAudio,

  /// Audio -> boshqa audio format
  audio,

  /// Rasm -> PNG / JPG / PDF, PDF -> rasm
  pdfImage,
}

// ================= KONVERTOR (INTERNETSIZ) =================
class ConverterScreen extends StatefulWidget {
  final ConverterMode mode;
  const ConverterScreen({super.key, required this.mode});

  @override
  State<ConverterScreen> createState() => _ConverterScreenState();
}

class _ConverterScreenState extends State<ConverterScreen> {
  List<PlatformFile> _selectedFiles = [];
  final List<String> _results = [];
  late String _targetFormat = _formats.first;
  String _videoCodec = "libx264";
  AudioQuality _quality = audioQualities.first;
  bool _isConverting = false;
  int _completedCount = 0;
  int _failedCount = 0;
  // Foydalanuvchi formatni o'zi tanlaganmi (tanlamagan bo'lsa, fayl turiga qarab qo'yiladi)
  bool _formatChosen = false;

  List<String> get _formats => switch (widget.mode) {
        ConverterMode.video => [...videoFormats, "gif"],
        ConverterMode.videoToAudio || ConverterMode.audio => audioFormats,
        ConverterMode.pdfImage => ["pdf", ...imageFormats],
      };

  String get _title => switch (widget.mode) {
        ConverterMode.video => "Video konvertor",
        ConverterMode.videoToAudio => "Videodan audio",
        ConverterMode.audio => "Audio konvertor",
        ConverterMode.pdfImage => "Rasm va PDF",
      };

  String get _hint => switch (widget.mode) {
        ConverterMode.video =>
          "Videolarni tanlang - ular tanlangan video formatga\nva kodekka aylantiriladi.",
        ConverterMode.videoToAudio =>
          "Videolarni tanlang - ulardan ovoz ajratib olinadi\nva tanlangan audio formatda saqlanadi.",
        ConverterMode.audio =>
          "Audio fayllarni tanlang - ular tanlangan\naudio formatga aylantiriladi.",
        ConverterMode.pdfImage =>
          "Rasm tanlasangiz - PNG, JPG yoki PDF ga aylanadi.\nPDF tanlasangiz - har bir sahifasi rasm bo'ladi.",
      };

  String get _pickLabel => switch (widget.mode) {
        ConverterMode.video || ConverterMode.videoToAudio => "Video tanlash",
        ConverterMode.audio => "Audio tanlash",
        ConverterMode.pdfImage => "Fayl tanlash",
      };

  void _show(String message, {int seconds = 4}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(duration: Duration(seconds: seconds), content: Text(message)),
    );
  }

  void _onFormatChanged(String format) {
    if (!profile.proActive && formatNeedsPro(format)) {
      _showProRequired("${format.toUpperCase()} formati faqat PRO obunada ochiladi.");
      return;
    }
    setState(() {
      _formatChosen = true;
      _applyFormat(format);
    });
  }

  /// Formatni o'rnatadi va unga mos kodekni tanlaydi (setState ichida chaqiriladi)
  void _applyFormat(String format) {
    final bool pro = profile.proActive;
    _targetFormat = format;
    final available =
        codecsFor(format).map((c) => c.value).where((c) => codecAllowed(c, pro: pro)).toList();
    if (available.isNotEmpty && !available.contains(_videoCodec)) _videoCodec = available.first;
  }

  /// "Rasm va PDF" da format hali tanlanmagan bo'lsa, fayl turiga mos qo'yiladi:
  /// PDF tanlansa -> PNG (PDF ni PDF ga aylantirib bo'lmaydi), rasm tanlansa -> PDF
  String? _suggestedFormat(List<PlatformFile> files) {
    if (widget.mode != ConverterMode.pdfImage || _formatChosen || files.isEmpty) return null;
    if (files.every((f) => isPdfFile(f.name))) return "png";
    if (files.every((f) => isImageFile(f.name))) return "pdf";
    return null;
  }

  String _formatKind(String format) {
    if (videoFormats.contains(format)) return "video";
    if (audioFormats.contains(format)) return "audio";
    if (format == "gif") return "animatsiya";
    if (format == "pdf") return "hujjat";
    return "rasm";
  }

  void _openSubscription() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const SubscriptionScreen()));
  }

  void _showProRequired(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 5),
        content: Text(message),
        action: SnackBarAction(label: "PRO olish", onPressed: _openSubscription),
      ),
    );
  }

  Future<void> _pickFiles() async {
    List<PlatformFile> files;
    try {
      files = switch (widget.mode) {
        ConverterMode.video ||
        ConverterMode.videoToAudio =>
          await FilePicker.pickFiles(type: FileType.video),
        // iPhone'da musiqa kutubxonasi ilovalarga yopiq: audio Fayllar ilovasidan tanlanadi
        ConverterMode.audio => isIOSApp
            ? await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: audioInputs)
            : await FilePicker.pickFiles(type: FileType.audio),
        ConverterMode.pdfImage => await FilePicker.pickFiles(
            type: FileType.custom,
            allowedExtensions: ["pdf", ...imageInputs],
          ),
      };
    } catch (e) {
      _show("Fayllarni tanlab bo'lmadi: $e");
      return;
    }
    if (files.isEmpty || !mounted) return;

    if (!profile.proActive && files.length > freeFileLimit) {
      _show("Bepul tarifda $freeFileLimit tagacha fayl! Ko'proq fayl uchun PRO obunani yoqing.");
      files = files.take(freeFileLimit).toList();
    }
    final String? suggested = _suggestedFormat(files);
    setState(() {
      _selectedFiles = files.toList();
      if (suggested != null) _applyFormat(suggested);
    });
  }

  Future<void> _convert() async {
    if (_selectedFiles.isEmpty || _isConverting) return;
    // Obuna tugab qolgan bo'lsa, PRO kodek bilan aylantirib bo'lmaydi
    if (videoFormats.contains(_targetFormat) && !codecAllowed(_videoCodec, pro: profile.proActive)) {
      _showProRequired("Tanlangan kodek faqat PRO obunada ishlaydi.");
      return;
    }
    final files = List<PlatformFile>.of(_selectedFiles);
    setState(() {
      _isConverting = true;
      _completedCount = 0;
      _failedCount = 0;
    });

    final errors = <String>[];
    final outputs = <String>[];
    int done = 0;
    String savedTo = "";
    try {
      final outDir = await resolveOutputDir();
      savedTo = outputDirLabel(outDir);
      final usedPaths = <String>{};

      // PDF sahifalarini parallel chizib bo'lmaydi, qolgan fayllar 4 tadan aylantiriladi
      final bool hasPdf = _targetFormat == "pdf" || files.any((f) => isPdfFile(f.name));
      final int batchSize = hasPdf ? 1 : 4;

      for (int i = 0; i < files.length; i += batchSize) {
        final batch = files.skip(i).take(batchSize);
        await Future.wait(batch.map((file) async {
          String? error;
          try {
            final path = file.path;
            if (path == null) {
              error = "fayl manzili topilmadi";
            } else {
              final outcome = await convertFile(
                inPath: path,
                fileName: file.name,
                format: _targetFormat,
                outDir: outDir,
                usedPaths: usedPaths,
                videoCodec: _videoCodec,
                audioBitrate: _quality.bitrate,
              );
              error = outcome.error;
              outputs.addAll(outcome.outputs);
            }
          } catch (e) {
            error = "$e";
          }
          if (error == null) {
            done++;
          } else {
            errors.add("${file.name}: $error");
          }
          if (mounted) {
            setState(() {
              _completedCount = done;
              _failedCount = errors.length;
            });
          }
        }));
      }
    } catch (e) {
      errors.add("$e");
    } finally {
      if (mounted) {
        setState(() {
          _isConverting = false;
          _results.insertAll(0, outputs);
          if (errors.isEmpty) _selectedFiles = [];
        });
      }
    }

    String message = done > 0 ? "Tayyor! $done ta fayl $savedTo saqlandi." : "Hech bir fayl aylantirilmadi.";
    if (errors.isNotEmpty) {
      final String firstError =
          errors.first.length > 160 ? "${errors.first.substring(0, 160)}..." : errors.first;
      message += "\n${errors.length} ta xatolik. $firstError";
    }
    _show(message, seconds: 6);
  }

  @override
  Widget build(BuildContext context) {
    // PRO holati o'zgarsa (masalan obuna yoqilsa), kodeklar ro'yxati yangilanadi
    return ListenableBuilder(listenable: profile, builder: (context, _) => _content(context));
  }

  Widget _content(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bool pro = profile.proActive;
    final bool isVideoTarget = videoFormats.contains(_targetFormat);
    final bool hasBitrate = bitrateFormats.contains(_targetFormat);

    return AppScaffold(
      appBar: AppBar(title: Text(_title)),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(
          children: [
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: _isConverting ? null : _pickFiles,
                icon: const Icon(Icons.file_present_rounded),
                label: Text(_pickLabel),
              ),
            ),
            const SizedBox(height: 12),
            InputDecorator(
              decoration: const InputDecoration(
                labelText: "Qaysi formatga aylantirilsin",
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _targetFormat,
                  isExpanded: true,
                  isDense: true,
                  items: _formats.map((f) {
                    return DropdownMenuItem<String>(
                      value: f,
                      child: Row(
                        children: [
                          Text(f.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(width: 8),
                          Text(
                            _formatKind(f),
                            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                          ),
                          if (!pro && formatNeedsPro(f)) const _ProBadge(),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: _isConverting
                      ? null
                      : (v) {
                          if (v != null) _onFormatChanged(v);
                        },
                ),
              ),
            ),
            if (isVideoTarget) ...[
              const SizedBox(height: 10),
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: "Video kodekni tanlang",
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _videoCodec,
                    isExpanded: true,
                    isDense: true,
                    items: codecsFor(_targetFormat).map((c) {
                      final bool allowed = codecAllowed(c.value, pro: pro);
                      return DropdownMenuItem<String>(
                        value: c.value,
                        enabled: allowed,
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                c.name,
                                overflow: TextOverflow.ellipsis,
                                style: allowed
                                    ? null
                                    : TextStyle(color: scheme.onSurface.withValues(alpha: 0.45)),
                              ),
                            ),
                            if (!allowed) const _ProBadge(),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: _isConverting
                        ? null
                        : (v) {
                            if (v != null) setState(() => _videoCodec = v);
                          },
                  ),
                ),
              ),
            ],
            if (isVideoTarget && !pro)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      "Bepul tarifda faqat H.264. Qolgan kodeklar PRO obunada.",
                      style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                    ),
                  ),
                  TextButton(onPressed: _openSubscription, child: const Text("PRO olish")),
                ],
              ),
            if (hasBitrate) ...[
              const SizedBox(height: 10),
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: "Ovoz sifati",
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<AudioQuality>(
                    value: _quality,
                    isExpanded: true,
                    isDense: true,
                    items: audioQualities
                        .map((q) => DropdownMenuItem<AudioQuality>(value: q, child: Text(q.name)))
                        .toList(),
                    onChanged: _isConverting
                        ? null
                        : (v) {
                            if (v != null) setState(() => _quality = v);
                          },
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            if (_isConverting) ...[
              LinearProgressIndicator(
                value: _selectedFiles.isEmpty
                    ? 0
                    : (_completedCount + _failedCount) / _selectedFiles.length,
              ),
              const SizedBox(height: 4),
              Text("Aylantirilmoqda: $_completedCount / ${_selectedFiles.length}"),
              const SizedBox(height: 6),
            ],
            Expanded(
              child: (_selectedFiles.isEmpty && _results.isEmpty)
                  ? Center(
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.upload_file_rounded, size: 44, color: scheme.primary),
                              const SizedBox(height: 10),
                              Text(
                                _hint,
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
                      child: ListView(
                        children: [
                          if (_selectedFiles.isNotEmpty) _sectionTitle("Tanlangan fayllar"),
                          for (int i = 0; i < _selectedFiles.length; i++) _selectedTile(i),
                          if (_results.isNotEmpty) _sectionTitle("Tayyor fayllar"),
                          for (final path in _results) _resultTile(path),
                        ],
                      ),
                    ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: (_selectedFiles.isEmpty || _isConverting) ? null : _convert,
                icon: const Icon(Icons.bolt_rounded),
                label: Text(
                  _isConverting
                      ? "Jarayon ketmoqda..."
                      : "${_targetFormat.toUpperCase()} ga aylantirish (${_selectedFiles.length} ta)",
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _selectedTile(int index) {
    final file = _selectedFiles[index];
    final path = file.path;
    final double sizeMb = (file.lengthSync() ?? 0) / 1024 / 1024;
    return ListTile(
      leading: Icon(fileIcon(file.name)),
      title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text("${sizeMb.toStringAsFixed(2)} MB -> .$_targetFormat"),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (path != null && canOpenFile(file.name))
            IconButton(
              icon: Icon(openIcon(file.name)),
              tooltip: "Ochish",
              onPressed: () => openFile(context, path),
            ),
          IconButton(
            icon: const Icon(Icons.close_rounded),
            tooltip: "Olib tashlash",
            onPressed: _isConverting ? null : () => setState(() => _selectedFiles.removeAt(index)),
          ),
        ],
      ),
    );
  }

  Widget _resultTile(String path) {
    final name = fileNameOf(path);
    return ListTile(
      leading: Icon(Icons.check_circle_rounded, color: Theme.of(context).colorScheme.primary),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(path, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: canOpenFile(name)
          ? IconButton(
              icon: Icon(openIcon(name)),
              tooltip: "Ochish",
              onPressed: () => openFile(context, path),
            )
          : null,
    );
  }
}

class _ProBadge extends StatelessWidget {
  const _ProBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.amber.shade600,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text(
        "PRO",
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.black),
      ),
    );
  }
}
