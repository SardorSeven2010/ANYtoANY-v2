import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart' as pdfx;

import '../app_theme.dart';
import '../services/media_tools.dart';
import 'player_screen.dart';

/// Faylni turiga qarab ochadi: video/audio - pleyerda, PDF va rasm - ko'rish oynasida.
void openFile(BuildContext context, String path) {
  final name = fileNameOf(path);
  Widget? screen;
  if (isPlayableFile(name)) {
    screen = PlayerScreen(path: path, title: name);
  } else if (isPdfFile(name)) {
    screen = PdfViewerScreen(pdfPath: path, fileName: name);
  } else if (isImageFile(name)) {
    screen = ImageViewerScreen(path: path, fileName: name);
  }
  if (screen == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Fayl saqlangan: $path")),
    );
    return;
  }
  final Widget target = screen;
  Navigator.push(context, MaterialPageRoute(builder: (_) => target));
}

bool canOpenFile(String name) => isPlayableFile(name) || isPdfFile(name) || isImageFile(name);

IconData fileIcon(String name) {
  if (isVideoFile(name)) return Icons.movie_rounded;
  if (isAudioFile(name)) return Icons.audiotrack_rounded;
  if (isPdfFile(name)) return Icons.picture_as_pdf_rounded;
  if (isImageFile(name)) return Icons.image_rounded;
  return Icons.insert_drive_file_rounded;
}

IconData openIcon(String name) => isPlayableFile(name) ? Icons.play_circle_fill_rounded : Icons.visibility_rounded;

// ================= PDF O'QUVCHI OYNA =================
class PdfViewerScreen extends StatefulWidget {
  final String pdfPath;
  final String fileName;
  const PdfViewerScreen({super.key, required this.pdfPath, required this.fileName});

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  late pdfx.PdfController _pdfController;

  @override
  void initState() {
    super.initState();
    _pdfController = pdfx.PdfController(
      document: pdfx.PdfDocument.openFile(widget.pdfPath),
    );
  }

  @override
  void dispose() {
    _pdfController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      appBar: AppBar(title: Text(widget.fileName, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: pdfx.PdfView(controller: _pdfController),
    );
  }
}

// ================= RASM KO'RISH OYNASI =================
class ImageViewerScreen extends StatelessWidget {
  final String path;
  final String fileName;
  const ImageViewerScreen({super.key, required this.path, required this.fileName});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      appBar: AppBar(title: Text(fileName, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: InteractiveViewer(
        maxScale: 6,
        child: Center(
          child: Image.file(
            File(path),
            errorBuilder: (_, _, _) => const Text("Rasmni ochib bo'lmadi"),
          ),
        ),
      ),
    );
  }
}
