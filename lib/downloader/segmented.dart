import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'common.dart';

/// Havolani tekshirish natijasi
class ProbeResult {
  final Uri url; // yo'naltirishlardan keyingi manzil
  final int? length;
  final bool acceptsRanges;
  final String? contentType;
  final String? fileName;
  final String? etag;
  const ProbeResult({
    required this.url,
    required this.length,
    required this.acceptsRanges,
    this.contentType,
    this.fileName,
    this.etag,
  });
}

/// Yuklash holati
class DownloadProgress {
  final int received;
  final int? total;
  final int segments; // hozir ishlayotgan bo'laklar soni
  const DownloadProgress(this.received, this.total, this.segments);

  double? get fraction => (total == null || total == 0) ? null : (received / total!).clamp(0.0, 1.0);
}

/// Havola haqida ma'lumot: hajm, Range qo'llab-quvvatlanishi, tur va nom.
/// `Range: bytes=0-0` so'raladi: fayl yuklanmaydi, faqat sarlavha o'qiladi.
Future<ProbeResult> probeUrl(Uri url, {Map<String, String> headers = const {}, CancelToken? cancel}) async {
  final client = newHttpClient();
  final unhook = cancel?.onCancel(() => client.close(force: true));
  try {
    final request = await client.getUrl(url).timeout(const Duration(seconds: 25));
    request.followRedirects = true;
    request.maxRedirects = 8;
    headers.forEach(request.headers.set);
    request.headers.set(HttpHeaders.rangeHeader, "bytes=0-0");
    final response = await request.close().timeout(const Duration(seconds: 25));
    cancel?.throwIfCancelled();
    final status = response.statusCode;
    if (status != 200 && status != 206 && status != 416) checkStatus(response);
    int? length;
    bool ranges = false;
    final contentRange = response.headers.value(HttpHeaders.contentRangeHeader);
    if (status == 206 && contentRange != null) {
      final m = RegExp(r'/(\d+)\s*$').firstMatch(contentRange);
      if (m != null) length = int.parse(m.group(1)!);
      ranges = length != null;
    } else if (status == 416 && contentRange != null) {
      final m = RegExp(r'/(\d+)\s*$').firstMatch(contentRange);
      if (m != null) length = int.parse(m.group(1)!);
    } else if (response.contentLength >= 0) {
      length = response.contentLength;
    }
    final finalUrl = response.redirects.isNotEmpty ? response.redirects.last.location : url;
    final resolved = finalUrl.hasScheme ? finalUrl : url.resolveUri(finalUrl);
    final result = ProbeResult(
      url: resolved,
      length: length,
      acceptsRanges: ranges,
      contentType: response.headers.contentType?.mimeType,
      fileName: fileNameFromDisposition(response.headers.value('content-disposition')),
      etag: response.headers.value(HttpHeaders.etagHeader) ?? response.headers.value(HttpHeaders.lastModifiedHeader),
    );
    // javob tanasini o'qimay yopamiz
    await response.listen((_) {}).cancel();
    return result;
  } on DownloadCancelled {
    rethrow;
  } catch (e) {
    if (cancel?.isCancelled ?? false) throw const DownloadCancelled();
    if (e is DownloadException) rethrow;
    if (e is TimeoutException) throw const DownloadException("Sayt javob bermadi. Internetni tekshiring.");
    if (e is SocketException) throw const DownloadException("Saytga ulanib bo'lmadi. Internetni tekshiring.");
    rethrow;
  } finally {
    unhook?.call();
    client.close(force: true);
  }
}

/// Faylni N ta bo'lakka bo'lib, parallel ulanishlar bilan yuklaydi (6 dan 18 gacha).
/// Hamma narsa qurilmaning o'zida: bo'laklar diskka yoziladi va oxirida ketma-ket birlashtiriladi.
/// Uzilgan yuklash qolgan joyidan davom etadi (bo'lak fayllari saqlanadi).
class SegmentedDownloader {
  SegmentedDownloader({
    required this.url,
    required this.outFile,
    this.headers = const {},
    int segments = 6,
    this.minSegmentBytes = 256 * 1024,
    this.maxRetries = 4,
    this.retryDelay = const Duration(milliseconds: 400),
    this.stallTimeout = const Duration(seconds: 30),
  }) : segments = segments < 1 ? 1 : segments;

  final Uri url;
  final File outFile;
  final Map<String, String> headers;
  final int segments;
  final int minSegmentBytes;
  final int maxRetries;
  final Duration retryDelay;
  final Duration stallTimeout;

  File _part(int i) => File("${outFile.path}.part$i");
  File get _meta => File("${outFile.path}.cdl");

  /// Haqiqatda ishlatilgan bo'laklar soni (run tugagach)
  int usedSegments = 0;

  Future<void> run({
    ProbeResult? probe,
    void Function(DownloadProgress)? onProgress,
    CancelToken? cancel,
  }) async {
    cancel ??= CancelToken();
    final info = probe ?? await probeUrl(url, headers: headers, cancel: cancel);
    final total = info.length;
    await outFile.parent.create(recursive: true);

    final canSplit = info.acceptsRanges && total != null && total >= minSegmentBytes * 2 && segments > 1;
    if (!canSplit) {
      usedSegments = 1;
      await _single(info, onProgress, cancel);
      return;
    }

    final n = (total ~/ minSegmentBytes).clamp(2, segments);
    usedSegments = n;
    final ranges = <(int, int)>[];
    final base = total ~/ n;
    for (var i = 0; i < n; i++) {
      final start = i * base;
      final end = i == n - 1 ? total - 1 : start + base - 1;
      ranges.add((start, end));
    }
    await _prepareParts(info, n, ranges);

    final received = List<int>.filled(n, 0);
    for (var i = 0; i < n; i++) {
      final f = _part(i);
      received[i] = f.existsSync() ? f.lengthSync().clamp(0, ranges[i].$2 - ranges[i].$1 + 1) : 0;
    }
    var active = 0;
    void report() => onProgress?.call(DownloadProgress(received.fold(0, (a, b) => a + b), total, active));
    report();

    final failure = Completer<void>();
    final workers = <Future<void>>[];
    for (var i = 0; i < n; i++) {
      final len = ranges[i].$2 - ranges[i].$1 + 1;
      if (received[i] >= len) continue;
      workers.add(() async {
        active++;
        try {
          await _downloadPart(i, ranges[i], received, report, cancel!, info);
        } catch (e) {
          if (!failure.isCompleted) failure.completeError(e);
        } finally {
          active--;
        }
      }());
    }
    // Bitta bo'lak muvaffaqiyatsiz bo'lsa, qolganlarini to'xtatamiz
    final done = Future.wait(workers);
    try {
      await Future.any([done, failure.future]);
      if (failure.isCompleted) await failure.future;
    } catch (e) {
      cancel.cancel();
      await done.catchError((_) => <void>[]);
      if (e is DownloadCancelled) rethrow;
      rethrow;
    }
    cancel.throwIfCancelled();
    await _merge(n, ranges);
  }

  Future<void> _prepareParts(ProbeResult info, int n, List<(int, int)> ranges) async {
    final stamp = jsonEncode({'url': url.toString(), 'total': info.length, 'etag': info.etag, 'n': n});
    if (_meta.existsSync()) {
      if (_meta.readAsStringSync() == stamp) return; // davom ettiriladi
      await _cleanup(n + 40);
    } else {
      await _cleanup(n + 40); // eski, begona bo'laklar
    }
    await _meta.writeAsString(stamp, flush: true);
  }

  Future<void> _cleanup(int maxParts) async {
    for (var i = 0; i < maxParts; i++) {
      final f = _part(i);
      if (f.existsSync()) await f.delete();
    }
  }

  Future<void> _downloadPart(
    int i,
    (int, int) range,
    List<int> received,
    void Function() report,
    CancelToken cancel,
    ProbeResult info,
  ) async {
    final len = range.$2 - range.$1 + 1;
    var attempt = 0;
    while (received[i] < len) {
      cancel.throwIfCancelled();
      final client = newHttpClient();
      final unhook = cancel.onCancel(() => client.close(force: true));
      IOSink? sink;
      try {
        final from = range.$1 + received[i];
        final request = await client.getUrl(info.url).timeout(const Duration(seconds: 25));
        request.followRedirects = true;
        headers.forEach(request.headers.set);
        request.headers.set(HttpHeaders.rangeHeader, "bytes=$from-${range.$2}");
        final response = await request.close().timeout(const Duration(seconds: 25));
        checkStatus(response, ok: const {206});
        // Server Range'ni e'tiborsiz qoldirsa (200), bo'lakli yuklash mumkin emas
        sink = _part(i).openWrite(mode: FileMode.append);
        await for (final chunk in response.timeout(stallTimeout)) {
          cancel.throwIfCancelled();
          final remaining = len - received[i];
          final data = chunk.length > remaining ? chunk.sublist(0, remaining) : chunk;
          sink.add(data);
          received[i] += data.length;
          report();
          if (received[i] >= len) break;
        }
        await sink.flush();
        await sink.close();
        sink = null;
        if (received[i] < len) throw const SocketException("Ulanish uzildi");
      } catch (e) {
        try {
          await sink?.close();
        } catch (_) {}
        if (cancel.isCancelled) throw const DownloadCancelled();
        // uzilgan joydan davom etish uchun haqiqiy fayl hajmini qayta o'qiymiz
        final f = _part(i);
        received[i] = f.existsSync() ? f.lengthSync().clamp(0, len) : 0;
        report();
        if (!isRetryable(e) || ++attempt > maxRetries) {
          if (e is DownloadException) rethrow;
          throw DownloadException("Yuklash uzildi: ${_short(e)}");
        }
        await Future<void>.delayed(retryDelay * attempt);
      } finally {
        unhook();
        client.close(force: true);
      }
    }
  }

  /// Bo'laklarni ketma-ket asosiy faylga ko'chiradi; ko'chirilgani darhol o'chadi (disk kam band bo'ladi)
  Future<void> _merge(int n, List<(int, int)> ranges) async {
    final tmp = File("${outFile.path}.tmp");
    if (tmp.existsSync()) await tmp.delete();
    final sink = tmp.openWrite();
    try {
      for (var i = 0; i < n; i++) {
        final f = _part(i);
        final len = ranges[i].$2 - ranges[i].$1 + 1;
        if (!f.existsSync() || f.lengthSync() != len) {
          throw DownloadException("Bo'lak ${i + 1} to'liq emas");
        }
        await sink.addStream(f.openRead());
        await f.delete();
      }
      await sink.flush();
      await sink.close();
    } catch (_) {
      try {
        await sink.close();
      } catch (_) {}
      rethrow;
    }
    if (outFile.existsSync()) await outFile.delete();
    await tmp.rename(outFile.path);
    if (_meta.existsSync()) await _meta.delete();
  }

  /// Bo'lakka bo'lib bo'lmaydigan holat: bitta ulanish bilan oqim
  Future<void> _single(ProbeResult info, void Function(DownloadProgress)? onProgress, CancelToken cancel) async {
    var attempt = 0;
    while (true) {
      cancel.throwIfCancelled();
      final client = newHttpClient();
      final unhook = cancel.onCancel(() => client.close(force: true));
      IOSink? sink;
      var got = 0;
      try {
        final request = await client.getUrl(info.url).timeout(const Duration(seconds: 25));
        request.followRedirects = true;
        headers.forEach(request.headers.set);
        final response = await request.close().timeout(const Duration(seconds: 25));
        checkStatus(response, ok: const {200});
        final total = response.contentLength >= 0 ? response.contentLength : info.length;
        final tmp = File("${outFile.path}.tmp");
        sink = tmp.openWrite();
        await for (final chunk in response.timeout(stallTimeout)) {
          cancel.throwIfCancelled();
          sink.add(chunk);
          got += chunk.length;
          onProgress?.call(DownloadProgress(got, total, 1));
        }
        await sink.flush();
        await sink.close();
        sink = null;
        if (total != null && total > 0 && got < total) throw const SocketException("Ulanish uzildi");
        if (outFile.existsSync()) await outFile.delete();
        await tmp.rename(outFile.path);
        return;
      } catch (e) {
        try {
          await sink?.close();
        } catch (_) {}
        if (cancel.isCancelled) throw const DownloadCancelled();
        if (!isRetryable(e) || ++attempt > maxRetries) {
          if (e is DownloadException) rethrow;
          throw DownloadException("Yuklash uzildi: ${_short(e)}");
        }
        await Future<void>.delayed(retryDelay * attempt);
      } finally {
        unhook();
        client.close(force: true);
      }
    }
  }

  String _short(Object e) => e is SocketException ? "ulanish uzildi" : (e is TimeoutException ? "javob kelmadi" : e.toString());
}
