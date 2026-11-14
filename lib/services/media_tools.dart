import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart' as pdf;
import 'package:pdf_combiner/models/image_from_pdf_config.dart';
import 'package:pdf_combiner/models/image_scale.dart';
import 'package:pdf_combiner/models/merge_input.dart';
import 'package:pdf_combiner/pdf_combiner.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfx/pdfx.dart' as pdfx;

import '../platform.dart';

const String publicDownloadDir = '/storage/emulated/0/Download';

const List<String> audioFormats = ["mp3", "wav", "aac", "m4a", "flac", "ogg"];
const List<String> videoFormats = ["mp4", "mkv", "avi", "mov", "webm"];
const List<String> imageFormats = ["png", "jpg"];

// PDF ga aylantirish mumkin bo'lgan rasm turlari
const List<String> imageInputs = ["png", "jpg", "jpeg", "webp", "bmp", "gif", "tif", "tiff"];
const List<String> videoInputs = ["mp4", "mkv", "avi", "mov", "webm", "3gp", "m4v", "flv", "wmv", "ts", "mpg", "mpeg"];
const List<String> audioInputs = ["mp3", "wav", "aac", "m4a", "flac", "ogg", "opus", "wma", "amr"];

class VideoCodec {
  final String name;
  final String value;
  const VideoCodec(this.name, this.value);
}

const List<VideoCodec> videoCodecs = [
  VideoCodec("H.264 (Barcha telefonlar uchun)", "libx264"),
  VideoCodec("H.265 / HEVC (Kichik hajm, yuqori sifat)", "libx265"),
  VideoCodec("VP9 (WebM / YouTube kodeki)", "libvpx-vp9"),
  VideoCodec("MPEG-4 (Eski qurilmalar uchun)", "mpeg4"),
  VideoCodec("Kodekni o'zgartirmasdan tez ko'chirish", "copy"),
];

// Bepul tarifda faqat shu kodek ochiq, qolganlari PRO obunada
const List<String> freeCodecs = ["libx264"];

bool codecAllowed(String codec, {required bool pro}) => pro || freeCodecs.contains(codec);

/// Bu formatga aylantirish uchun PRO kerakmi (bepul kodeklarning birortasi mos kelmasa)
bool formatNeedsPro(String format) =>
    videoFormats.contains(format) && !codecsFor(format).any((c) => freeCodecs.contains(c.value));

/// Har bir konteyner hamma kodekni ham qabul qilmaydi (masalan WebM faqat VP9)
List<VideoCodec> codecsFor(String format) {
  const Map<String, List<String>> allowed = {
    "webm": ["libvpx-vp9", "copy"],
    "mov": ["libx264", "libx265", "mpeg4", "copy"],
    "avi": ["libx264", "mpeg4", "copy"],
  };
  final list = allowed[format];
  if (list == null) return videoCodecs;
  return videoCodecs.where((c) => list.contains(c.value)).toList();
}

class AudioQuality {
  final String name;
  final String? bitrate;
  const AudioQuality(this.name, this.bitrate);
}

const List<AudioQuality> audioQualities = [
  AudioQuality("Avto sifat", null),
  AudioQuality("128 kbit/s (kichik hajm)", "128k"),
  AudioQuality("192 kbit/s (yaxshi)", "192k"),
  AudioQuality("256 kbit/s (yuqori)", "256k"),
  AudioQuality("320 kbit/s (eng yuqori)", "320k"),
];

// Bitreyt tanlash faqat siqiladigan formatlar uchun ma'noga ega
const List<String> bitrateFormats = ["mp3", "aac", "m4a", "ogg"];

String extensionOf(String name) {
  final int dot = name.lastIndexOf('.');
  return dot <= 0 ? "" : name.substring(dot + 1).toLowerCase();
}

String baseNameOf(String name) => name.replaceAll(RegExp(r'\.[^\.]+$'), '');

String fileNameOf(String path) => lastSegment(path);

bool isVideoFile(String name) => videoInputs.contains(extensionOf(name));
bool isAudioFile(String name) => audioInputs.contains(extensionOf(name));
bool isImageFile(String name) => imageInputs.contains(extensionOf(name));
bool isPdfFile(String name) => extensionOf(name) == "pdf";
bool isPlayableFile(String name) => isVideoFile(name) || isAudioFile(name);

/// Natijalar saqlanadigan papka.
/// Kompyuterda: foydalanuvchining Downloads papkasi.
/// Androidda: Download papkasi; unga yozib bo'lmasa (Android 10 va undan eski), ilovaning o'z papkasi.
Future<Directory> resolveOutputDir() async {
  if (!isAndroidApp) {
    try {
      final downloads = await getDownloadsDirectory();
      if (downloads != null) {
        if (!await downloads.exists()) await downloads.create(recursive: true);
        return downloads;
      }
    } catch (_) {}
    return getApplicationDocumentsDirectory();
  }

  final download = Directory(publicDownloadDir);
  try {
    if (await download.exists()) {
      final probe = File(joinPath(download.path, "anytoany_${DateTime.now().microsecondsSinceEpoch}.tmp"));
      await probe.writeAsString("ok", flush: true);
      await probe.delete();
      return download;
    }
  } catch (_) {}
  return await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
}

String outputDirLabel(Directory dir) => isIOSApp
    ? "Fayllar ilovasidagi CORE papkasiga"
    : _outputDirLabel(dir);

String _outputDirLabel(Directory dir) =>
    dir.path == publicDownloadDir ? "Download papkasiga" : "${dir.path} papkasiga";

/// Mavjud faylni ustidan yozmaslik uchun takrorlanmas nom tanlaydi
String uniquePath(Directory dir, String baseName, String ext, Set<String> usedPaths) {
  String path = joinPath(dir.path, "$baseName.$ext");
  for (int n = 1; usedPaths.contains(path) || File(path).existsSync(); n++) {
    path = joinPath(dir.path, "${baseName}_$n.$ext");
  }
  usedPaths.add(path);
  return path;
}

List<String> buildFfmpegArgs({
  required String inPath,
  required String outPath,
  required String format,
  String videoCodec = "libx264",
  String? audioBitrate,
}) {
  final args = <String>["-y", "-i", inPath];
  if (videoFormats.contains(format)) {
    args.addAll(["-c:v", videoCodec]);
    if (videoCodec != "copy") {
      // Ko'p pleyerlar faqat yuv420p va juft o'lchamli videoni o'qiy oladi
      args.addAll(["-pix_fmt", "yuv420p", "-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2"]);
    }
    final String audioCodec = switch (format) {
      "webm" => "libvorbis",
      "avi" => "libmp3lame",
      _ => "aac",
    };
    args.addAll(["-c:a", audioCodec]);
  } else if (audioFormats.contains(format)) {
    // Videodan faqat ovoz olinadi
    args.add("-vn");
    if (audioBitrate != null && bitrateFormats.contains(format)) {
      args.addAll(["-b:a", audioBitrate]);
    }
  } else if (imageFormats.contains(format)) {
    args.addAll(["-an", "-frames:v", "1", "-update", "1"]);
  }
  args.add(outPath);
  return args;
}

/// Linux'da kompyuterga FFmpeg o'rnatilmagan bo'lsa
class FfmpegMissingException implements Exception {
  const FfmpegMissingException();

  @override
  String toString() => "Kompyuterda FFmpeg o'rnatilmagan. Terminalda bajaring: sudo apt install ffmpeg";
}

Future<bool> runFfmpeg(List<String> args) async {
  // Linux uchun FFmpegKit kutubxonalari faqat eski distributivlarga mos keladi,
  // shuning uchun Linux'da tizimning o'z ffmpeg dasturi ishlatiladi (.deb uni o'zi o'rnatadi)
  if (isLinuxApp) return _runSystemFfmpeg(args);
  final session = await FFmpegKit.executeWithArguments(args);
  return ReturnCode.isSuccess(await session.getReturnCode());
}

/// Oxirgi muvaffaqiyatsiz ffmpeg chaqiruvining xabari (xatoni aniqlash va testlar uchun)
String lastFfmpegError = "";

Future<bool> _runSystemFfmpeg(List<String> args) async {
  try {
    final result = await Process.run("ffmpeg", ["-hide_banner", "-loglevel", "error", "-nostdin", ...args]);
    lastFfmpegError = result.exitCode == 0 ? "" : "${result.stderr}".trim();
    return result.exitCode == 0;
  } on ProcessException {
    throw const FfmpegMissingException();
  }
}

Future<void> deleteQuietly(String path) async {
  try {
    final file = File(path);
    if (await file.exists()) await file.delete();
  } catch (_) {}
}

/// PNG faylning o'lchami (eni, bo'yi) - fayl sarlavhasidan o'qiladi
(int, int)? pngSize(List<int> bytes) {
  if (bytes.length < 24) return null;
  int read(int offset) =>
      (bytes[offset] << 24) | (bytes[offset + 1] << 16) | (bytes[offset + 2] << 8) | bytes[offset + 3];
  return (read(16), read(20));
}

/// Linux'da PDF sahifalarini PNG qilib chizadi (pdfx Linux'da ishlamaydi, PDFium ishlatiladi).
/// Hamma sahifalar bir xil o'lchamda bo'lsa, aniqroq bo'lishi uchun 2 barobar kattaroq chiziladi.
/// Rasmlar [workDir] ichida yaratiladi va sahifa tartibida qaytariladi.
Future<List<String>> renderPdfPagesWithPdfium(String pdfPath, Directory workDir) async {
  final normal = Directory(joinPath(workDir.path, "x1"));
  await normal.create(recursive: true);
  List<String> pages = await PdfCombiner.createImageFromPDF(
    input: MergeInput.path(pdfPath),
    outputDirPath: normal.path,
    config: const ImageFromPdfConfig(createOneImage: false),
  );

  final sizes = [for (final page in pages) pngSize(await File(page).openRead(0, 24).expand((b) => b).toList())];
  final first = sizes.isEmpty ? null : sizes.first;
  if (first != null && sizes.every((size) => size == first)) {
    final sharp = Directory(joinPath(workDir.path, "x2"));
    await sharp.create(recursive: true);
    try {
      pages = await PdfCombiner.createImageFromPDF(
        input: MergeInput.path(pdfPath),
        outputDirPath: sharp.path,
        config: ImageFromPdfConfig(
          rescale: ImageScale(width: first.$1 * 2, height: first.$2 * 2),
          createOneImage: false,
        ),
      );
    } catch (_) {
      // aniqroq chizib bo'lmasa, oddiy o'lchamdagisi qoladi
    }
  }
  return pages;
}

/// Vaqtinchalik ishchi papka yaratadi
Future<Directory> createWorkDir(String prefix) async {
  final temp = await getTemporaryDirectory();
  final dir = Directory(joinPath(temp.path, "${prefix}_${DateTime.now().microsecondsSinceEpoch}"));
  await dir.create(recursive: true);
  return dir;
}

Future<void> deleteDirQuietly(Directory dir) async {
  try {
    if (await dir.exists()) await dir.delete(recursive: true);
  } catch (_) {}
}

/// PDF ning har bir sahifasini alohida rasm qilib saqlaydi
Future<List<String>> pdfToImages({
  required String pdfPath,
  required String format,
  required Directory outDir,
  required String baseName,
  required Set<String> usedPaths,
}) async {
  if (isLinuxApp) {
    return _pdfToImagesWithPdfium(
      pdfPath: pdfPath,
      format: format,
      outDir: outDir,
      baseName: baseName,
      usedPaths: usedPaths,
    );
  }
  final outputs = <String>[];
  final document = await pdfx.PdfDocument.openFile(pdfPath);
  try {
    for (int n = 1; n <= document.pagesCount; n++) {
      final page = await document.getPage(n);
      try {
        final image = await page.render(
          width: page.width * 2,
          height: page.height * 2,
          format: format == "png" ? pdfx.PdfPageImageFormat.png : pdfx.PdfPageImageFormat.jpeg,
          backgroundColor: '#FFFFFF',
        );
        if (image == null) throw Exception("$n-sahifani chizib bo'lmadi");
        final pageName = document.pagesCount > 1 ? "${baseName}_$n-bet" : baseName;
        final outPath = uniquePath(outDir, pageName, format, usedPaths);
        await File(outPath).writeAsBytes(image.bytes, flush: true);
        outputs.add(outPath);
      } finally {
        await page.close();
      }
    }
  } finally {
    await document.close();
  }
  return outputs;
}

Future<List<String>> _pdfToImagesWithPdfium({
  required String pdfPath,
  required String format,
  required Directory outDir,
  required String baseName,
  required Set<String> usedPaths,
}) async {
  final outputs = <String>[];
  final work = await createWorkDir("anytoany_pdf");
  try {
    final pages = await renderPdfPagesWithPdfium(pdfPath, work);
    for (int i = 0; i < pages.length; i++) {
      final pageName = pages.length > 1 ? "${baseName}_${i + 1}-bet" : baseName;
      final outPath = uniquePath(outDir, pageName, format, usedPaths);
      if (format == "png") {
        await File(pages[i]).copy(outPath);
      } else {
        final ok = await runFfmpeg(["-y", "-i", pages[i], "-q:v", "2", outPath]);
        if (!ok) throw Exception("${i + 1}-sahifani JPG ga aylantirib bo'lmadi");
      }
      outputs.add(outPath);
    }
  } finally {
    await deleteDirQuietly(work);
  }
  return outputs;
}

/// Rasmni bir sahifali PDF ga joylaydi. Xato bo'lsa sababini qaytaradi
Future<String?> imageToPdf(String imagePath, String ext, String outPath) async {
  String jpgPath = imagePath;
  String? tempPath;
  if (ext != "jpg" && ext != "jpeg") {
    // JPEG PDF ichiga qayta siqilmasdan joylanadi, boshqa rasmlar avval JPEG ga o'tkaziladi
    final tempDir = await getTemporaryDirectory();
    tempPath = joinPath(tempDir.path, "anytoany_${DateTime.now().microsecondsSinceEpoch}.jpg");
    final ok = await runFfmpeg(
      ["-y", "-i", imagePath, "-frames:v", "1", "-update", "1", "-q:v", "2", tempPath],
    );
    if (!ok) {
      await deleteQuietly(tempPath);
      return "rasmni o'qib bo'lmadi";
    }
    jpgPath = tempPath;
  }

  try {
    final image = pw.MemoryImage(await File(jpgPath).readAsBytes());
    final double ratio = (image.height ?? 1) / (image.width ?? 1);
    final pageFormat = pdf.PdfPageFormat(pdf.PdfPageFormat.a4.width, pdf.PdfPageFormat.a4.width * ratio);
    final document = pw.Document();
    document.addPage(
      pw.Page(
        pageFormat: pageFormat,
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Center(child: pw.Image(image)),
      ),
    );
    await File(outPath).writeAsBytes(await document.save(), flush: true);
    return null;
  } finally {
    if (tempPath != null) await deleteQuietly(tempPath);
  }
}

class ConvertOutcome {
  final List<String> outputs;
  final String? error;
  const ConvertOutcome.ok(this.outputs) : error = null;
  const ConvertOutcome.failed(this.error) : outputs = const [];
}

/// Bitta faylni aylantiradi
Future<ConvertOutcome> convertFile({
  required String inPath,
  required String fileName,
  required String format,
  required Directory outDir,
  required Set<String> usedPaths,
  String videoCodec = "libx264",
  String? audioBitrate,
}) async {
  final ext = extensionOf(fileName);
  final baseName = "${baseNameOf(fileName)}_CORE";

  // FFmpeg PDF bilan ishlamaydi, shuning uchun PDF alohida aylantiriladi
  if (ext == "pdf") {
    if (!imageFormats.contains(format)) {
      return const ConvertOutcome.failed("PDF faylni bu yerda faqat PNG yoki JPG ga aylantirish mumkin");
    }
    return ConvertOutcome.ok(await pdfToImages(
      pdfPath: inPath,
      format: format,
      outDir: outDir,
      baseName: baseName,
      usedPaths: usedPaths,
    ));
  }
  if (format == "pdf") {
    if (!imageInputs.contains(ext)) {
      return const ConvertOutcome.failed("PDF ga faqat rasm fayllarni aylantirish mumkin");
    }
    final outPath = uniquePath(outDir, baseName, "pdf", usedPaths);
    final error = await imageToPdf(inPath, ext, outPath);
    if (error != null) {
      await deleteQuietly(outPath);
      return ConvertOutcome.failed(error);
    }
    return ConvertOutcome.ok([outPath]);
  }

  final outPath = uniquePath(outDir, baseName, format, usedPaths);
  final ok = await runFfmpeg(buildFfmpegArgs(
    inPath: inPath,
    outPath: outPath,
    format: format,
    videoCodec: videoCodec,
    audioBitrate: audioBitrate,
  ));
  if (ok) return ConvertOutcome.ok([outPath]);
  await deleteQuietly(outPath);
  return ConvertOutcome.failed("bu faylni .$format ga aylantirib bo'lmadi");
}
