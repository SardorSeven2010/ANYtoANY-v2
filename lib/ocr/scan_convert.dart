import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'docx_writer.dart';
import 'ocr_types.dart';
import 'prepare.dart';
import 'scan_page.dart';
import 'xlsx_writer.dart';

/// Skan rejimida bir hujjatdagi sahifalar soni chegarasi (har bir sahifa bir necha soniya oladi)
const int maxScanPages = 40;

/// PDF sahifalarini rasm fayllarga aylantiradi (tartib bo'yicha). Aniq o'lcham vositaga bog'liq.
typedef PageRenderer = Future<List<String>> Function(String pdfPath, Directory workDir);

class ScanConvertException implements Exception {
  final String message;
  const ScanConvertException(this.message);

  @override
  String toString() => message;
}

/// Bitta sahifaning tayyorlangan ma'lumoti (alohida oqimda hisoblanadi)
class _Prepared {
  final int width, height;
  final Uint8List gray;
  final PageGeometry geometry;
  const _Prepared(this.width, this.height, this.gray, this.geometry);
}

/// Sahifa rasmini o'qiydi, OCR uchun tozalaydi ([cleanPath] ga yozadi) va geometriyasini topadi.
/// Og'ir ish: alohida oqimda bajariladi. Yopilma faqat ikkita satrni oladi, shuning uchun oqimga yuborish xavfsiz.
Future<_Prepared> _prepareInIsolate(String pagePath, String cleanPath) => Isolate.run(() {
      final raw = img.decodeImage(File(pagePath).readAsBytesSync());
      if (raw == null) throw const ScanConvertException("Sahifa rasmini o'qib bo'lmadi");
      final prepared = prepareForOcr(raw);
      File(cleanPath).writeAsBytesSync(img.encodePng(prepared.image, level: 1));
      return _Prepared(prepared.image.width, prepared.image.height, Uint8List.fromList(prepared.image.getBytes()), prepared.geometry);
    });

/// Skanerlangan PDF ni tahrirlanadigan Word (`docx`) yoki Excel (`xlsx`) ga aylantiradi: matn qurilmaning o'zida
/// tanib olinadi, jadval chiziqlari bo'yicha qayta quriladi. Internet kerak emas.
Future<void> convertScannedPdf({
  required String pdfPath,
  required String outPath,
  required String format,
  required OcrEngine engine,
  required PageRenderer renderPages,
  required Directory workDir,
  void Function(String stage)? onStage,
}) async {
  if (format != 'docx' && format != 'xlsx') {
    throw const ScanConvertException("Skan rejimi faqat Word va Excel uchun");
  }
  if (!await engine.isAvailable()) {
    throw const ScanConvertException("Bu qurilmada matn tanish mumkin emas");
  }

  onStage?.call("Sahifalar tayyorlanmoqda...");
  final pageFiles = await renderPages(pdfPath, workDir);
  if (pageFiles.isEmpty) throw const ScanConvertException("PDF sahifalarini o'qib bo'lmadi");
  if (pageFiles.length > maxScanPages) {
    throw ScanConvertException(
      "Skan rejimida eng ko'pi bilan $maxScanPages sahifa. Bu hujjatda ${pageFiles.length} ta: avval bo'laklarga bo'ling.",
    );
  }

  final pages = <ScanPage>[];
  int cropCounter = 0;
  for (int i = 0; i < pageFiles.length; i++) {
    final label = pageFiles.length > 1 ? "${i + 1}/${pageFiles.length}-sahifa" : "Sahifa";
    onStage?.call("$label: tayyorlanmoqda...");
    final cleanPath = '${workDir.path}/clean_$i.png';
    final prepared = await _prepareInIsolate(pageFiles[i], cleanPath);
    final image = img.Image.fromBytes(
      width: prepared.width,
      height: prepared.height,
      bytes: prepared.gray.buffer,
      bytesOffset: prepared.gray.offsetInBytes,
      numChannels: 1,
    );

    onStage?.call("$label: matn tanilmoqda...");
    final words = await engine.recognize(cleanPath);

    onStage?.call("$label: jadval tuzilmoqda...");
    final page = await buildScanPage(
      image: image,
      geometry: prepared.geometry,
      words: words,
      fontFactor: engine.fontFactor,
      recognizeCrop: (crop, {bool lineMode = false}) async {
        final file = File('${workDir.path}/crop_${cropCounter++}.png');
        await file.writeAsBytes(img.encodePng(crop, level: 1));
        try {
          return await engine.recognize(file.path, lineMode: lineMode);
        } finally {
          try {
            await file.delete();
          } catch (_) {}
        }
      },
    );
    pages.add(page);
    try {
      await File(pageFiles[i]).delete();
      await File(cleanPath).delete();
    } catch (_) {}
  }

  if (pages.every((p) => p.isEmpty)) {
    throw const ScanConvertException("Hujjatda matn topilmadi. Rasm aniq va to'g'ri joylashganini tekshiring.");
  }
  onStage?.call("Fayl yozilmoqda...");
  final bytes = format == 'docx' ? buildDocx(pages) : buildXlsx(pages);
  await File(outPath).writeAsBytes(bytes, flush: true);
}
