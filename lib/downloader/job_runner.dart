import 'dart:async';
import 'dart:io';

import '../platform.dart';
import '../services/gallery.dart';
import '../services/media_tools.dart';
import 'common.dart';
import 'hls.dart';
import 'segmented.dart';

/// Havola turi
enum MediaKind {
  direct("Oddiy fayl"),
  hls("HLS (.m3u8)"),
  dash("DASH (.mpd)");

  final String label;
  const MediaKind(this.label);
}

/// Yuklangan videoni qaysi kodekda saqlash (PRO: H.264 yoki H.265 tanlash)
enum OutputCodec {
  original("Asl holida (tez)"),
  h264("H.264 (hamma qurilmada ishlaydi)"),
  h265("H.265 / HEVC (kichik hajm)");

  final String label;
  const OutputCodec(this.label);
}

/// Yuklash so'rovi
class DownloadRequest {
  final Uri url;
  final Map<String, String> headers;
  final String title;
  final MediaKind kind;
  final int segments;
  final OutputCodec codec;
  final String? pageUrl;

  /// HLS bosh ro'yxatida tanlangan sifat (null bo'lsa eng yaxshisi)
  final Uri? variantUrl;

  const DownloadRequest({
    required this.url,
    required this.title,
    this.headers = const {},
    this.kind = MediaKind.direct,
    this.segments = 6,
    this.codec = OutputCodec.original,
    this.pageUrl,
    this.variantUrl,
  });
}

/// Yuklash bosqichi
enum JobStage { probing, downloading, merging, converting, saving }

class JobCallbacks {
  final void Function(int received, int? total, int activeSegments)? onProgress;
  final void Function(JobStage stage)? onStage;
  final CancelToken cancel;
  const JobCallbacks({this.onProgress, this.onStage, required this.cancel});
}

/// URL va Content-Type bo'yicha turini aniqlaydi
MediaKind guessKind(Uri url, {String? contentType}) {
  final path = url.path.toLowerCase();
  final ct = (contentType ?? '').toLowerCase();
  if (path.endsWith('.m3u8') || path.endsWith('.m3u') || ct.contains('mpegurl'))
    return MediaKind.hls;
  if (path.endsWith('.mpd') || ct.contains('dash+xml')) return MediaKind.dash;
  return MediaKind.direct;
}

/// Tanlangan kodek uchun ffmpeg argumentlari
List<String> codecArgs(OutputCodec codec) => switch (codec) {
  OutputCodec.original => ['-c', 'copy'],
  OutputCodec.h264 => [
    '-c:v',
    'libx264',
    '-preset',
    'veryfast',
    '-crf',
    '23',
    '-pix_fmt',
    'yuv420p',
    '-vf',
    'scale=trunc(iw/2)*2:trunc(ih/2)*2',
    '-c:a',
    'aac',
    '-b:a',
    '160k',
  ],
  OutputCodec.h265 => [
    '-c:v',
    'libx265',
    '-preset',
    'veryfast',
    '-crf',
    '28',
    '-tag:v',
    'hvc1',
    '-pix_fmt',
    'yuv420p',
    '-vf',
    'scale=trunc(iw/2)*2:trunc(ih/2)*2',
    '-c:a',
    'aac',
    '-b:a',
    '160k',
  ],
};

/// Ishchi papka: havolaga bog'langan, shuning uchun uzilgan yuklash shu yerdan davom etadi
Future<Directory> workDirFor(Uri url, {String prefix = 'core_dl'}) async {
  final root = await createWorkDirRoot(prefix);
  final dir = Directory(
    joinPath(
      root.path,
      url.toString().hashCode.toUnsigned(32).toRadixString(16),
    ),
  );
  await dir.create(recursive: true);
  return dir;
}

Future<Directory> createWorkDirRoot(String prefix) async {
  final temp = await workRoot();
  final dir = Directory(joinPath(temp.path, prefix));
  await dir.create(recursive: true);
  return dir;
}

/// Vaqtinchalik fayllar uchun asosiy papka (testlarda almashtiriladi)
Future<Directory> Function() workRoot = () async =>
    (await createWorkDir('core')).parent;

/// Yuklab bo'lingan natija
class JobResult {
  final String path;
  final int bytes;
  final int segmentsUsed;

  /// Galereyada ko'rinadimi
  final bool inGallery;

  /// Galereyaga qo'shishdagi izoh (xato bo'lsa)
  final String? note;
  const JobResult(
    this.path,
    this.bytes,
    this.segmentsUsed, {
    this.inGallery = false,
    this.note,
  });
}

/// Bitta yuklashni boshidan oxirigacha bajaradi: tekshirish -> yuklash -> birlashtirish/kodlash -> .mp4
Future<JobResult> runDownloadJob(
  DownloadRequest request,
  Directory outDir,
  Set<String> usedPaths,
  JobCallbacks cb,
) async {
  final work = await workDirFor(request.url);
  cb.cancel.throwIfCancelled();
  await outDir.create(recursive: true);
  final outPath = uniquePath(
    outDir,
    safeFileName(request.title),
    'mp4',
    usedPaths,
  );
  var segmentsUsed = 1;
  String? warning;
  try {
    switch (request.kind) {
      case MediaKind.direct:
        (segmentsUsed, warning) = await _runDirect(request, work, outPath, cb);
      case MediaKind.hls:
        (segmentsUsed, warning) = await _runHls(request, work, outPath, cb);
      case MediaKind.dash:
        warning = await _runDash(request, outPath, cb);
    }
  } on DownloadCancelled {
    await deleteDirQuietly(work);
    await deleteQuietly(outPath);
    rethrow;
  } catch (_) {
    await deleteQuietly(outPath);
    rethrow;
  }
  await deleteDirQuietly(work);
  final bytes = File(outPath).lengthSync();
  // tayyor video galereyada ko'rinishi uchun (Android: Movies/CORE, iPhone: Rasmlar)
  cb.onStage?.call(JobStage.saving);
  final published = await galleryPublisher(
    outPath,
    GalleryKind.video,
    name: lastSegment(outPath),
  );
  final note = [warning, published.note].whereType<String>().join("\n");
  return JobResult(
    published.path,
    bytes,
    segmentsUsed,
    inGallery: published.inGallery,
    note: note.isEmpty ? null : note,
  );
}

Future<(int, String?)> _runDirect(
  DownloadRequest r,
  Directory work,
  String outPath,
  JobCallbacks cb,
) async {
  cb.onStage?.call(JobStage.probing);
  final probe = await probeUrl(r.url, headers: r.headers, cancel: cb.cancel);
  final ext = _extensionFor(probe, r.url);
  final raw = File(joinPath(work.path, "source.$ext"));
  cb.onStage?.call(JobStage.downloading);
  final d = SegmentedDownloader(
    url: r.url,
    outFile: raw,
    headers: r.headers,
    segments: r.segments,
  );
  await d.run(
    probe: probe,
    cancel: cb.cancel,
    onProgress: (p) => cb.onProgress?.call(p.received, p.total, p.segments),
  );
  cb.cancel.throwIfCancelled();
  final warning = await _finalize(raw.path, ext, outPath, r.codec, cb);
  return (d.usedSegments, warning);
}

String _extensionFor(ProbeResult probe, Uri url) {
  final fromName = extensionOf(probe.fileName ?? '');
  if (fromName.isNotEmpty && fromName.length <= 5) return fromName;
  final fromUrl = extensionOf(url.path);
  if (fromUrl.isNotEmpty && fromUrl.length <= 5) return fromUrl;
  final ct = probe.contentType ?? '';
  if (ct.contains('webm')) return 'webm';
  if (ct.contains('matroska')) return 'mkv';
  if (ct.contains('quicktime')) return 'mov';
  if (ct.contains('mp2t')) return 'ts';
  return 'mp4';
}

/// Yuklangan faylni .mp4 ga aylantiradi: mp4 bo'lsa va kodek o'zgarmasa - shunchaki ko'chiradi
Future<String?> _finalize(
  String inPath,
  String ext,
  String outPath,
  OutputCodec codec,
  JobCallbacks cb,
) async {
  if (codec == OutputCodec.original &&
      const {'mp4', 'm4v', 'mov'}.contains(ext)) {
    await File(inPath).rename(outPath).catchError((Object _) async {
      // boshqa diskka o'tgan bo'lsa, nusxalab o'chiramiz
      await File(inPath).copy(outPath);
      await deleteQuietly(inPath);
      return File(outPath);
    });
    return null;
  }
  cb.onStage?.call(
    codec == OutputCodec.original ? JobStage.merging : JobStage.converting,
  );
  final args = [
    '-y',
    '-i',
    inPath,
    ...codecArgs(codec),
    '-movflags',
    '+faststart',
    outPath,
  ];
  var ok = await runFfmpeg(args);
  if (!ok && codec == OutputCodec.original) {
    // qutiga (mp4) ko'chirib bo'lmadigan kodek: H.264 ga o'tkazamiz
    cb.onStage?.call(JobStage.converting);
    await deleteQuietly(outPath);
    ok = await runFfmpeg([
      '-y',
      '-i',
      inPath,
      ...codecArgs(OutputCodec.h264),
      '-movflags',
      '+faststart',
      outPath,
    ]);
  }
  if (!ok) {
    await deleteQuietly(outPath);
    throw const DownloadException("Videoni .mp4 ga aylantirib bo'lmadi");
  }
  // Qayta kodlangan video haqiqatan ochilishini tekshiramiz (masalan H.265 rasmsiz chiqmasin)
  return verifyOrRetryH264(outPath, codec, cb, () async {
    return runFfmpeg([
      '-y',
      '-i',
      inPath,
      ...codecArgs(OutputCodec.h264),
      '-movflags',
      '+faststart',
      outPath,
    ]);
  });
}

Future<(int, String?)> _runHls(
  DownloadRequest r,
  Directory work,
  String outPath,
  JobCallbacks cb,
) async {
  cb.onStage?.call(JobStage.probing);
  final (text, url) = await fetchText(
    r.url,
    headers: r.headers,
    cancel: cb.cancel,
  );
  final first = parseHls(text, url);
  Uri? audioUrl;
  final HlsMedia video;
  if (first is HlsMaster) {
    final variant = r.variantUrl != null
        ? first.variants.firstWhere(
            (v) => v.url == r.variantUrl,
            orElse: () => first.byQuality.first,
          )
        : first.byQuality.first;
    audioUrl = first.audioFor(variant);
    final (vt, vu) = await fetchText(
      variant.url,
      headers: r.headers,
      cancel: cb.cancel,
    );
    final second = parseHls(vt, vu);
    if (second is! HlsMedia)
      throw const DownloadException("HLS ro'yxati noto'g'ri tuzilgan");
    video = second;
  } else {
    video = first as HlsMedia;
  }
  HlsMedia? audio;
  if (audioUrl != null) {
    final (at, au) = await fetchText(
      audioUrl,
      headers: r.headers,
      cancel: cb.cancel,
    );
    final p = parseHls(at, au);
    if (p is HlsMedia) audio = p;
  }
  cb.onStage?.call(JobStage.downloading);

  final totalSegs = video.segments.length + (audio?.segments.length ?? 0);
  var done = 0;
  var bytes = 0;
  void report() => cb.onProgress?.call(bytes, null, r.segments);
  void segmentDone(int _, int __) {
    done++;
    // bo'laklar soni bo'yicha taxminiy foiz: umumiy hajm noma'lum, shuning uchun total = null, fraction alohida
    cb.onProgress?.call(
      bytes,
      totalSegs == 0 ? null : (bytes * totalSegs ~/ (done == 0 ? 1 : done)),
      r.segments,
    );
  }

  final videoList = await downloadHlsMedia(
    video,
    work,
    name: 'video',
    headers: r.headers,
    parallel: r.segments,
    cancel: cb.cancel,
    onBytes: (b) {
      bytes += b;
      report();
    },
    onSegment: segmentDone,
  );
  File? audioList;
  if (audio != null) {
    audioList = await downloadHlsMedia(
      audio,
      work,
      name: 'audio',
      headers: r.headers,
      parallel: r.segments,
      cancel: cb.cancel,
      onBytes: (b) {
        bytes += b;
        report();
      },
      onSegment: segmentDone,
    );
  }
  cb.cancel.throwIfCancelled();
  cb.onStage?.call(
    r.codec == OutputCodec.original ? JobStage.merging : JobStage.converting,
  );
  final args = hlsMuxArgs(
    videoPlaylist: videoList.path,
    audioPlaylist: audioList?.path,
    outPath: outPath,
    codec: r.codec,
  );
  if (!await runFfmpeg(args)) {
    await deleteQuietly(outPath);
    throw const DownloadException("Bo'laklarni birlashtirib bo'lmadi");
  }
  final warning = await verifyOrRetryH264(outPath, r.codec, cb, () async {
    return runFfmpeg(
      hlsMuxArgs(
        videoPlaylist: videoList.path,
        audioPlaylist: audioList?.path,
        outPath: outPath,
        codec: OutputCodec.h264,
      ),
    );
  });
  return (r.segments, warning);
}

/// Qayta kodlangan natija haqiqatan ochilishini tekshiradi (testlar uchun ochiq). H.265 ochilmasa, H.264 bilan qayta kodlanadi.
Future<String?> verifyOrRetryH264(
  String outPath,
  OutputCodec codec,
  JobCallbacks cb,
  Future<bool> Function() retryH264,
) async {
  if (codec == OutputCodec.original || await isPlayableVideo(outPath))
    return null;
  await deleteQuietly(outPath);
  if (codec == OutputCodec.h264)
    throw const DownloadException("Kodlangan video ochilmadi");
  cb.onStage?.call(JobStage.converting);
  if (!await retryH264() || !await isPlayableVideo(outPath)) {
    await deleteQuietly(outPath);
    throw const DownloadException("Videoni kodlab bo'lmadi");
  }
  return "H.265 kodlash muvaffaqiyatsiz bo'ldi: video H.264 formatida saqlandi";
}

/// DASH: ffmpeg manifestni o'zi o'qib, tarmoqdan oladi va .mp4 ga yozadi (DRM bo'lmasa)
Future<String?> _runDash(
  DownloadRequest r,
  String outPath,
  JobCallbacks cb,
) async {
  cb.onStage?.call(JobStage.probing);
  final (text, _) = await fetchText(
    r.url,
    headers: r.headers,
    cancel: cb.cancel,
  );
  checkDashManifest(text);
  cb.onStage?.call(JobStage.downloading);
  final headerLines = StringBuffer();
  r.headers.forEach((k, v) => headerLines.write("$k: $v\r\n"));
  final args = [
    '-y',
    if (headerLines.isNotEmpty) ...['-headers', headerLines.toString()],
    '-i',
    r.url.toString(),
    ...codecArgs(r.codec),
    '-movflags',
    '+faststart',
    outPath,
  ];
  if (!await runFfmpeg(args)) {
    await deleteQuietly(outPath);
    throw const DownloadException("DASH videoni yuklab bo'lmadi");
  }
  return verifyOrRetryH264(outPath, r.codec, cb, () async {
    return runFfmpeg([
      '-y',
      if (headerLines.isNotEmpty) ...['-headers', headerLines.toString()],
      '-i',
      r.url.toString(),
      ...codecArgs(OutputCodec.h264),
      '-movflags',
      '+faststart',
      outPath,
    ]);
  });
}

/// DRM yoki jonli efir bo'lsa xato beradi
void checkDashManifest(String xml) {
  if (xml.contains('<ContentProtection') ||
      xml.contains('<cenc:pssh') ||
      xml.toLowerCase().contains('widevine')) {
    throw const DownloadException(
      "Bu video DRM bilan himoyalangan. Uni yuklab bo'lmaydi.",
    );
  }
  if (RegExp(r'<MPD[^>]*type\s*=\s*"dynamic"').hasMatch(xml)) {
    throw const DownloadException(
      "Bu jonli efir (tugamaydigan oqim). Jonli efirni yuklab bo'lmaydi.",
    );
  }
}

/// Platformaga mos "Yuklanmalar/CORE" papkasi
Future<Directory> downloadsDir() async {
  final base = await resolveOutputDir();
  final dir = Directory(joinPath(base.path, "CORE"));
  try {
    await dir.create(recursive: true);
    return dir;
  } catch (_) {
    return base;
  }
}

bool get downloadsNeedPermissionHint => isAndroidApp;
