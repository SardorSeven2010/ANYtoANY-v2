import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart' as pdf;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfx/pdfx.dart' as pdfx;

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

String fileNameOf(String path) => path.split('/').last;

bool isVideoFile(String name) => videoInputs.contains(extensionOf(name));
bool isAudioFile(String name) => audioInputs.contains(extensionOf(name));
bool isImageFile(String name) => imageInputs.contains(extensionOf(name));
bool isPdfFile(String name) => extensionOf(name) == "pdf";
bool isPlayableFile(String name) => isVideoFile(name) || isAudioFile(name);

/// Download papkasiga yozib bo'lmasa (Android 10 va undan eski), ilovaning o'z papkasi ishlatiladi
Future<Directory> resolveOutputDir() async {
  final download = Directory(publicDownloadDir);
  try {
    if (await download.exists()) {
      final probe = File("${download.path}/anytoany_${DateTime.now().microsecondsSinceEpoch}.tmp");
      await probe.writeAsString("ok", flush: true);
      await probe.delete();
      return download;
    }
  } catch (_) {}
  return await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
}

String outputDirLabel(Directory dir) =>
    dir.path == publicDownloadDir ? "Download papkasiga" : "${dir.path} papkasiga";

/// Mavjud faylni ustidan yozmaslik uchun takrorlanmas nom tanlaydi
String uniquePath(Directory dir, String baseName, String ext, Set<String> usedPaths) {
  String path = "${dir.path}/$baseName.$ext";
  for (int n = 1; usedPaths.contains(path) || File(path).existsSync(); n++) {
    path = "${dir.path}/${baseName}_$n.$ext";
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

Future<bool> runFfmpeg(List<String> args) async {
  final session = await FFmpegKit.executeWithArguments(args);
  return ReturnCode.isSuccess(await session.getReturnCode());
}

Future<void> deleteQuietly(String path) async {
  try {
    final file = File(path);
    if (await file.exists()) await file.delete();
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

/// Rasmni bir sahifali PDF ga joylaydi. Xato bo'lsa sababini qaytaradi
Future<String?> imageToPdf(String imagePath, String ext, String outPath) async {
  String jpgPath = imagePath;
  String? tempPath;
  if (ext != "jpg" && ext != "jpeg") {
    // JPEG PDF ichiga qayta siqilmasdan joylanadi, boshqa rasmlar avval JPEG ga o'tkaziladi
    final tempDir = await getTemporaryDirectory();
    tempPath = "${tempDir.path}/anytoany_${DateTime.now().microsecondsSinceEpoch}.jpg";
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
  final baseName = "${baseNameOf(fileName)}_ANYtoANY";

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
