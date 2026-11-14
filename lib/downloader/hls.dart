import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'common.dart';
import 'job_runner.dart' show OutputCodec, codecArgs;

// ================= HLS (.m3u8) =================
// Ro'yxat o'qiladi, hamma bo'laklar parallel yuklanadi, so'ng ffmpeg ularni bitta .mp4 ga birlashtiradi.
// AES-128 bilan shifrlangan oqimlar ham ishlaydi (kalit ochiq havoladan olinadi).
// DRM (SAMPLE-AES, Widevine, FairPlay, PlayReady) va jonli efir qo'llab-quvvatlanmaydi.

/// "KEY=value,KEY2="qiymat, vergul bilan"" ko'rinishidagi atributlar
Map<String, String> parseAttributes(String input) {
  final result = <String, String>{};
  final re = RegExp(r'([A-Z0-9-]+)=("([^"]*)"|[^,]*)');
  for (final m in re.allMatches(input)) {
    result[m.group(1)!] = m.group(3) ?? m.group(2)!;
  }
  return result;
}

class HlsKey {
  final String method;
  final Uri? uri;
  final String? iv;
  const HlsKey(this.method, this.uri, this.iv);
}

class HlsSegment {
  final Uri url;
  final double duration;
  final HlsKey? key;
  final int? byteLength;
  final int? byteOffset;
  final bool discontinuity;
  final int sequence;
  const HlsSegment({
    required this.url,
    required this.duration,
    required this.sequence,
    this.key,
    this.byteLength,
    this.byteOffset,
    this.discontinuity = false,
  });
}

class HlsMedia {
  final List<HlsSegment> segments;
  final Uri? initUrl;
  final int? initLength;
  final int? initOffset;
  final bool endList;
  final String? drmReason;
  final int mediaSequence;
  const HlsMedia({
    required this.segments,
    required this.endList,
    required this.mediaSequence,
    this.initUrl,
    this.initLength,
    this.initOffset,
    this.drmReason,
  });

  double get totalSeconds => segments.fold(0.0, (a, s) => a + s.duration);
}

class HlsVariant {
  final Uri url;
  final int bandwidth;
  final int? width;
  final int? height;
  final String? codecs;
  final String? audioGroup;
  const HlsVariant({required this.url, required this.bandwidth, this.width, this.height, this.codecs, this.audioGroup});

  String get label {
    final res = height != null ? "${height}p" : (bandwidth > 0 ? "${(bandwidth / 1000).round()} kbit/s" : "Asl");
    return res;
  }
}

class HlsRendition {
  final String type;
  final String groupId;
  final Uri? uri;
  final bool isDefault;
  final String? name;
  const HlsRendition({required this.type, required this.groupId, required this.uri, required this.isDefault, this.name});
}

class HlsMaster {
  final List<HlsVariant> variants;
  final List<HlsRendition> renditions;
  const HlsMaster(this.variants, this.renditions);

  /// Variantga tegishli alohida audio oqimi (bo'lsa)
  Uri? audioFor(HlsVariant v) {
    final g = v.audioGroup;
    if (g == null) return null;
    final list = renditions.where((r) => r.type == 'AUDIO' && r.groupId == g && r.uri != null).toList();
    if (list.isEmpty) return null;
    return (list.firstWhere((r) => r.isDefault, orElse: () => list.first)).uri;
  }

  /// Sifat bo'yicha tartiblangan (yuqoridan pastga)
  List<HlsVariant> get byQuality => [...variants]..sort((a, b) {
      final h = (b.height ?? 0).compareTo(a.height ?? 0);
      return h != 0 ? h : b.bandwidth.compareTo(a.bandwidth);
    });
}

/// Ro'yxat matni: bosh (master) yoki media ro'yxati
Object parseHls(String text, Uri base) {
  final lines = const LineSplitter().convert(text).map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  if (lines.isEmpty || !lines.first.startsWith('#EXTM3U')) {
    throw const DownloadException("Bu to'g'ri HLS (.m3u8) ro'yxati emas");
  }
  if (lines.any((l) => l.startsWith('#EXT-X-STREAM-INF'))) return _parseMaster(lines, base);
  return _parseMedia(lines, base);
}

HlsMaster _parseMaster(List<String> lines, Uri base) {
  final variants = <HlsVariant>[];
  final renditions = <HlsRendition>[];
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.startsWith('#EXT-X-MEDIA:')) {
      final a = parseAttributes(line.substring('#EXT-X-MEDIA:'.length));
      renditions.add(HlsRendition(
        type: a['TYPE'] ?? '',
        groupId: a['GROUP-ID'] ?? '',
        uri: a['URI'] == null ? null : base.resolve(a['URI']!),
        isDefault: a['DEFAULT'] == 'YES',
        name: a['NAME'],
      ));
    } else if (line.startsWith('#EXT-X-STREAM-INF:')) {
      final a = parseAttributes(line.substring('#EXT-X-STREAM-INF:'.length));
      // keyingi bo'sh bo'lmagan, # bilan boshlanmaydigan qator - havola
      String? uri;
      for (var j = i + 1; j < lines.length; j++) {
        if (!lines[j].startsWith('#')) {
          uri = lines[j];
          break;
        }
      }
      if (uri == null) continue;
      final res = a['RESOLUTION']?.split('x');
      variants.add(HlsVariant(
        url: base.resolve(uri),
        bandwidth: int.tryParse(a['BANDWIDTH'] ?? a['AVERAGE-BANDWIDTH'] ?? '') ?? 0,
        width: res != null && res.length == 2 ? int.tryParse(res[0]) : null,
        height: res != null && res.length == 2 ? int.tryParse(res[1]) : null,
        codecs: a['CODECS'],
        audioGroup: a['AUDIO'],
      ));
    }
  }
  if (variants.isEmpty) throw const DownloadException("HLS ro'yxatida video oqimi topilmadi");
  return HlsMaster(variants, renditions);
}

HlsMedia _parseMedia(List<String> lines, Uri base) {
  final segments = <HlsSegment>[];
  HlsKey? key;
  Uri? initUrl;
  int? initLength;
  int? initOffset;
  double duration = 0;
  int? byteLength;
  int? byteOffset;
  int? lastEnd;
  var discontinuity = false;
  var endList = false;
  var mediaSequence = 0;
  String? drm;

  for (final line in lines) {
    if (line.startsWith('#EXT-X-MEDIA-SEQUENCE:')) {
      mediaSequence = int.tryParse(line.split(':')[1]) ?? 0;
    } else if (line.startsWith('#EXT-X-KEY:')) {
      final a = parseAttributes(line.substring('#EXT-X-KEY:'.length));
      final method = a['METHOD'] ?? 'NONE';
      final format = a['KEYFORMAT'] ?? 'identity';
      if (method == 'NONE') {
        key = null;
      } else if (method == 'AES-128' && format == 'identity') {
        key = HlsKey(method, a['URI'] == null ? null : base.resolve(a['URI']!), a['IV']);
      } else {
        drm = "Bu video DRM bilan himoyalangan ($method${format == 'identity' ? '' : ', $format'}). Uni yuklab bo'lmaydi.";
      }
    } else if (line.startsWith('#EXT-X-MAP:')) {
      final a = parseAttributes(line.substring('#EXT-X-MAP:'.length));
      if (a['URI'] != null) initUrl = base.resolve(a['URI']!);
      final br = a['BYTERANGE']?.split('@');
      if (br != null) {
        initLength = int.tryParse(br[0]);
        initOffset = br.length > 1 ? int.tryParse(br[1]) : 0;
      }
    } else if (line.startsWith('#EXTINF:')) {
      duration = double.tryParse(line.substring(8).split(',').first) ?? 0;
    } else if (line.startsWith('#EXT-X-BYTERANGE:')) {
      final parts = line.substring('#EXT-X-BYTERANGE:'.length).split('@');
      byteLength = int.tryParse(parts[0]);
      byteOffset = parts.length > 1 ? int.tryParse(parts[1]) : lastEnd;
      if (byteLength != null && byteOffset != null) lastEnd = byteOffset + byteLength;
    } else if (line.startsWith('#EXT-X-DISCONTINUITY')) {
      discontinuity = true;
    } else if (line.startsWith('#EXT-X-ENDLIST')) {
      endList = true;
    } else if (!line.startsWith('#')) {
      segments.add(HlsSegment(
        url: base.resolve(line),
        duration: duration,
        sequence: mediaSequence + segments.length,
        key: key,
        byteLength: byteLength,
        byteOffset: byteOffset,
        discontinuity: discontinuity,
      ));
      byteLength = null;
      byteOffset = null;
      discontinuity = false;
    }
  }
  return HlsMedia(
    segments: segments,
    endList: endList,
    mediaSequence: mediaSequence,
    initUrl: initUrl,
    initLength: initLength,
    initOffset: initOffset,
    drmReason: drm,
  );
}

/// Matnli fayl (ro'yxat) yuklab oladi
Future<(String, Uri)> fetchText(Uri url, {Map<String, String> headers = const {}, CancelToken? cancel, int maxBytes = 8 * 1024 * 1024}) async {
  var attempt = 0;
  while (true) {
    cancel?.throwIfCancelled();
    final client = newHttpClient();
    final unhook = cancel?.onCancel(() => client.close(force: true));
    try {
      final request = await client.getUrl(url).timeout(const Duration(seconds: 25));
      request.followRedirects = true;
      request.maxRedirects = 8;
      headers.forEach(request.headers.set);
      final response = await request.close().timeout(const Duration(seconds: 25));
      checkStatus(response, ok: const {200});
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 25))) {
        bytes.addAll(chunk);
        if (bytes.length > maxBytes) throw const DownloadException("Ro'yxat juda katta");
      }
      final finalUrl = response.redirects.isNotEmpty ? url.resolveUri(response.redirects.last.location) : url;
      return (utf8.decode(bytes, allowMalformed: true), finalUrl);
    } catch (e) {
      if (cancel?.isCancelled ?? false) throw const DownloadCancelled();
      if (!isRetryable(e) || ++attempt > 3) {
        if (e is DownloadException) rethrow;
        throw DownloadException("Ro'yxatni olib bo'lmadi: ${e is SocketException ? "ulanish uzildi" : e}");
      }
      await Future<void>.delayed(Duration(milliseconds: 300 * attempt));
    } finally {
      unhook?.call();
      client.close(force: true);
    }
  }
}

/// Bitta faylni (yoki uning bir qismini) diskka yuklaydi, uzilsa qayta urinadi
Future<int> fetchToFile(
  Uri url,
  File target, {
  Map<String, String> headers = const {},
  int? byteOffset,
  int? byteLength,
  CancelToken? cancel,
  int maxRetries = 4,
  Duration retryDelay = const Duration(milliseconds: 300),
}) async {
  var attempt = 0;
  while (true) {
    cancel?.throwIfCancelled();
    final client = newHttpClient();
    final unhook = cancel?.onCancel(() => client.close(force: true));
    IOSink? sink;
    try {
      final request = await client.getUrl(url).timeout(const Duration(seconds: 25));
      request.followRedirects = true;
      request.maxRedirects = 8;
      headers.forEach(request.headers.set);
      final ranged = byteLength != null;
      if (ranged) {
        final from = byteOffset ?? 0;
        request.headers.set(HttpHeaders.rangeHeader, "bytes=$from-${from + byteLength - 1}");
      }
      final response = await request.close().timeout(const Duration(seconds: 25));
      checkStatus(response, ok: ranged ? const {206, 200} : const {200});
      sink = target.openWrite();
      var got = 0;
      await for (final chunk in response.timeout(const Duration(seconds: 30))) {
        cancel?.throwIfCancelled();
        sink.add(chunk);
        got += chunk.length;
      }
      await sink.flush();
      await sink.close();
      sink = null;
      final expected = ranged ? byteLength : (response.contentLength >= 0 ? response.contentLength : null);
      if (expected != null && got < expected) throw const SocketException("Ulanish uzildi");
      return got;
    } catch (e) {
      try {
        await sink?.close();
      } catch (_) {}
      if (cancel?.isCancelled ?? false) throw const DownloadCancelled();
      if (!isRetryable(e) || ++attempt > maxRetries) {
        if (e is DownloadException) rethrow;
        throw DownloadException("Yuklash uzildi: ${e is SocketException ? "ulanish uzildi" : e}");
      }
      await Future<void>.delayed(retryDelay * attempt);
    } finally {
      unhook?.call();
      client.close(force: true);
    }
  }
}

class HlsProgress {
  final int doneSegments;
  final int totalSegments;
  final int bytes;
  const HlsProgress(this.doneSegments, this.totalSegments, this.bytes);
  double get fraction => totalSegments == 0 ? 0 : doneSegments / totalSegments;
}

/// ffmpeg HLS demuxer ruxsat beradigan bo'lak kengaytmalari (allowed_segment_extensions)
const Set<String> _segmentExtensions = {
  '3gp', 'aac', 'avi', 'ac3', 'eac3', 'flac', 'mkv', 'm4a', 'm4s', 'm4v', 'mpg', 'mov', 'mp2', 'mp3', 'mp4',
  'mpeg', 'mpegts', 'ogg', 'ogv', 'oga', 'ts', 'vob', 'vtt', 'wav', 'webvtt',
};

/// Media ro'yxatining hamma bo'laklarini [dir] ga yuklaydi va ffmpeg o'qiy oladigan mahalliy ro'yxat yozadi.
/// Qaytaradi: mahalliy ro'yxat fayli.
Future<File> downloadHlsMedia(
  HlsMedia media,
  Directory dir, {
  String name = 'index',
  Map<String, String> headers = const {},
  int parallel = 6,
  void Function(int bytes)? onBytes,
  void Function(int done, int total)? onSegment,
  CancelToken? cancel,
  Duration retryDelay = const Duration(milliseconds: 300),
}) async {
  if (media.drmReason != null) throw DownloadException(media.drmReason!);
  if (!media.endList) {
    throw const DownloadException("Bu jonli efir (tugamaydigan oqim). Jonli efirni yuklab bo'lmaydi.");
  }
  if (media.segments.isEmpty) throw const DownloadException("Videoda bo'laklar topilmadi");
  await dir.create(recursive: true);

  // kalitlar: har bir noyob manzil bir marta yuklanadi
  final keyFiles = <String, String>{};
  for (final seg in media.segments) {
    final k = seg.key;
    if (k?.uri != null && !keyFiles.containsKey(k!.uri.toString())) {
      final fileName = "${name}_key${keyFiles.length}.bin";
      await fetchToFile(k.uri!, File("${dir.path}/$fileName"), headers: headers, cancel: cancel, retryDelay: retryDelay);
      keyFiles[k.uri.toString()] = fileName;
    }
  }
  String? initName;
  if (media.initUrl != null) {
    initName = "${name}_init.mp4";
    await fetchToFile(
      media.initUrl!,
      File("${dir.path}/$initName"),
      headers: headers,
      byteOffset: media.initOffset,
      byteLength: media.initLength,
      cancel: cancel,
      retryDelay: retryDelay,
    );
  }

  final total = media.segments.length;
  // Yangi ffmpeg (7.1+) bo'lak fayllarining kengaytmasini tekshiradi: faqat ma'lum kengaytmalar ruxsat etiladi.
  // Shuning uchun asl kengaytma (ma'lum bo'lsa) saqlanadi, aks holda .ts (yoki fMP4 uchun .m4s).
  String segName(int i) {
    final path = media.segments[i].url.path;
    final dot = path.lastIndexOf('.');
    final original = dot >= 0 ? path.substring(dot + 1).toLowerCase() : '';
    final ext = _segmentExtensions.contains(original) ? original : (initName != null ? 'm4s' : 'ts');
    return "${name}_${i.toString().padLeft(5, '0')}.$ext";
  }
  var next = 0;
  var done = 0;
  Object? failure;
  final workers = <Future<void>>[];
  final count = parallel.clamp(1, total);
  for (var w = 0; w < count; w++) {
    workers.add(() async {
      while (failure == null) {
        cancel?.throwIfCancelled();
        final i = next++;
        if (i >= total) return;
        final seg = media.segments[i];
        try {
          final bytes = await fetchToFile(
            seg.url,
            File("${dir.path}/${segName(i)}"),
            headers: headers,
            byteOffset: seg.byteOffset,
            byteLength: seg.byteLength,
            cancel: cancel,
            retryDelay: retryDelay,
          );
          onBytes?.call(bytes);
          done++;
          onSegment?.call(done, total);
        } catch (e) {
          failure ??= e;
          cancel?.cancel();
          return;
        }
      }
    }());
  }
  await Future.wait(workers);
  if (failure != null) {
    if (failure is DownloadCancelled && !(cancel?.isCancelled ?? false)) throw const DownloadCancelled();
    throw failure!;
  }

  // mahalliy ro'yxat
  final target = media.segments.map((s) => s.duration).fold(0.0, (a, b) => a > b ? a : b).ceil();
  final out = StringBuffer()
    ..writeln('#EXTM3U')
    ..writeln('#EXT-X-VERSION:${initName != null ? 7 : 3}')
    ..writeln('#EXT-X-TARGETDURATION:${target < 1 ? 1 : target}')
    ..writeln('#EXT-X-MEDIA-SEQUENCE:0')
    ..writeln('#EXT-X-PLAYLIST-TYPE:VOD');
  if (initName != null) out.writeln('#EXT-X-MAP:URI="$initName"');
  String? currentKey;
  for (var i = 0; i < total; i++) {
    final seg = media.segments[i];
    final k = seg.key;
    final keyId = k == null ? 'none' : "${k.uri}|${k.iv}";
    if (keyId != currentKey) {
      currentKey = keyId;
      if (k == null) {
        out.writeln('#EXT-X-KEY:METHOD=NONE');
      } else {
        // IV berilmagan bo'lsa, standart bo'yicha bo'lak tartib raqamidan olinadi: aniq yozamiz
        final iv = k.iv ?? '';
        out.writeln('#EXT-X-KEY:METHOD=AES-128,URI="${keyFiles[k.uri.toString()]}"${iv.isEmpty ? '' : ',IV=$iv'}');
      }
    }
    if (k != null && (k.iv == null || k.iv!.isEmpty)) {
      // IV bo'lak ketma-ketligiga bog'liq: har bir bo'lak uchun alohida kalit yozuvi
      final hex = seg.sequence.toRadixString(16).padLeft(32, '0');
      out.writeln('#EXT-X-KEY:METHOD=AES-128,URI="${keyFiles[k.uri.toString()]}",IV=0x$hex');
    }
    if (seg.discontinuity) out.writeln('#EXT-X-DISCONTINUITY');
    out.writeln('#EXTINF:${seg.duration.toStringAsFixed(6)},');
    out.writeln(segName(i));
  }
  out.writeln('#EXT-X-ENDLIST');
  final playlist = File("${dir.path}/$name.m3u8");
  await playlist.writeAsString(out.toString(), flush: true);
  return playlist;
}

/// ffmpeg uchun argumentlar: mahalliy HLS ro'yxat(lar)ini bitta .mp4 ga birlashtirish
List<String> hlsMuxArgs({
  required String videoPlaylist,
  String? audioPlaylist,
  required String outPath,
  OutputCodec codec = OutputCodec.original,
}) =>
    [
      '-y',
      '-allowed_extensions', 'ALL',
      '-protocol_whitelist', 'file,crypto,data',
      '-i', videoPlaylist,
      if (audioPlaylist != null) ...[
        '-allowed_extensions', 'ALL',
        '-protocol_whitelist', 'file,crypto,data',
        '-i', audioPlaylist,
        '-map', '0:v:0?',
        '-map', '1:a:0?',
      ],
      ...codecArgs(codec),
      '-movflags', '+faststart',
      outPath,
    ];
