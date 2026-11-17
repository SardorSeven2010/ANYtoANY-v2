import 'dart:io';

import 'package:pdfx/pdfx.dart' as pdfx;

import '../platform.dart';
import '../services/media_tools.dart';
import '../services/native_bridge.dart';
import '../services/online_pdf.dart';
import 'ocr_types.dart';
import 'pdf_probe.dart';
import 'scan_convert.dart';

/// Android'da ML Kit (qurilmaning o'zida, internetsiz). Boshqa tizimlarda mavjud emas.
class NativeOcrEngine implements OcrEngine {
  @override
  Future<bool> isAvailable() async => isAndroidApp && nativeBridge.supported;

  /// ML Kit so'z qutisi harflardan biroz kattaroq bo'ladi
  @override
  double get fontFactor => 0.9;

  @override
  Future<List<OcrWord>> recognize(String imagePath, {bool lineMode = false}) async {
    final raw = await nativeBridge.ocrImage(imagePath);
    if (raw == null) throw const OcrException("Matnni tanib bo'lmadi");
    final words = <OcrWord>[];
    for (final m in raw) {
      final text = (m['text'] ?? '').toString();
      final l = (m['left'] as num?)?.toDouble(), t = (m['top'] as num?)?.toDouble();
      final r = (m['right'] as num?)?.toDouble(), b = (m['bottom'] as num?)?.toDouble();
      if (text.trim().isEmpty || l == null || t == null || r == null || b == null) continue;
      words.add(OcrWord(text, l, t, r, b, confidence: (m['confidence'] as num?)?.toDouble() ?? 1));
    }
    return words;
  }
}

OcrEngine? _engineOverride;

/// Shu qurilmada ishlatiladigan matn tanish dvigateli: Android'da ML Kit, Linux'da Tesseract (o'rnatilgan bo'lsa)
OcrEngine get ocrEngine => _engineOverride ??= isLinuxApp ? TesseractOcrEngine() : NativeOcrEngine();

/// Testlar uchun almashtirish (null: standart holatga)
void setOcrEngine(OcrEngine? engine) => _engineOverride = engine;

/// Skanerlangan PDF ni qurilmaning o'zida o'qish imkoni bormi
Future<bool> scanModeAvailable() async {
  try {
    return await ocrEngine.isAvailable();
  } catch (_) {
    return false;
  }
}

/// PDF skanerlangan (matnsiz, faqat rasm) ko'rinishidami
Future<bool> isScannedPdf(String path) async => !await pdfHasText(path);

/// PDF sahifalarini OCR uchun yetarlicha aniq rasmlarga aylantiradi (eni ~2200 piksel)
Future<List<String>> renderPagesForOcr(String pdfPath, Directory workDir) async {
  if (isLinuxApp) return renderPdfPagesWithPdfium(pdfPath, workDir);
  final document = await pdfx.PdfDocument.openFile(pdfPath);
  try {
    final out = <String>[];
    for (int n = 1; n <= document.pagesCount; n++) {
      final page = await document.getPage(n);
      try {
        final scale = (2200 / page.width).clamp(2.0, 6.0);
        final image = await page.render(
          width: page.width * scale,
          height: page.height * scale,
          format: pdfx.PdfPageImageFormat.png,
          backgroundColor: '#FFFFFF',
        );
        if (image == null) throw ScanConvertException("$n-sahifani chizib bo'lmadi");
        final file = File(joinPath(workDir.path, 'page_$n.png'));
        await file.writeAsBytes(image.bytes, flush: true);
        out.add(file.path);
      } finally {
        await page.close();
      }
    }
    return out;
  } finally {
    await document.close();
  }
}

/// Skanerlangan PDF ni Word / Excel ga aylantiradi (internetsiz). Xatolar [OnlinePdfException] bo'lib chiqadi,
/// shunda ekran ularni onlayn konvertatsiyadagi xatolar bilan bir xil ko'rsatadi.
Future<void> convertScanLocally({
  required String sourcePath,
  required String outPath,
  required String format,
  void Function(String stage)? onStage,
}) async {
  final workDir = await createWorkDir('scan');
  try {
    await convertScannedPdf(
      pdfPath: sourcePath,
      outPath: outPath,
      format: format,
      engine: ocrEngine,
      renderPages: renderPagesForOcr,
      workDir: workDir,
      onStage: onStage,
    );
  } on ScanConvertException catch (e) {
    throw OnlinePdfException(e.message);
  } on OcrException catch (e) {
    throw OnlinePdfException(e.message);
  } finally {
    await deleteDirQuietly(workDir);
  }
}
