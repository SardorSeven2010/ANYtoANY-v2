import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// Yuklash testlari uchun mahalliy HTTP server: Range, uzilish, xato va yo'naltirishlarni taqlid qiladi.
class TestServer {
  late final HttpServer _server;
  final Map<String, Uint8List> files = {};
  final Map<String, String> contentTypes = {};
  final Map<String, String> texts = {};

  bool supportRanges = true;
  bool chunkedNoLength = false; // Content-Length yubormaydi
  int dropFirstRangeResponses = 0; // birinchi N ta javobni yarim yo'lda uzadi
  int failFirstRequests = 0; // birinchi N ta so'rovga 503
  int forceStatus = 0; // hamma so'rovga shu holat (masalan 403)
  Duration chunkDelay = Duration.zero;
  String? etag = '"v1"';
  String? disposition;

  int concurrent = 0;
  int peakConcurrent = 0;
  final List<String> log = [];
  final List<int> rangeStarts = [];
  final Map<String, int> hits = {};
  final Map<String, Map<String, String>> seenHeaders = {};

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_handle);
  }

  Uri url(String path) => Uri.parse('http://127.0.0.1:${_server.port}$path');
  String get base => 'http://127.0.0.1:${_server.port}';

  Future<void> close() => _server.close(force: true);

  static Uint8List random(int n, {int seed = 1}) {
    final r = Random(seed);
    return Uint8List.fromList(List<int>.generate(n, (_) => r.nextInt(256)));
  }

  Future<void> _handle(HttpRequest req) async {
    final path = req.uri.path;
    hits[path] = (hits[path] ?? 0) + 1;
    log.add('${req.method} $path ${req.headers.value('range') ?? ''}');
    seenHeaders[path] = {for (final n in ['referer', 'user-agent', 'cookie']) n: req.headers.value(n) ?? ''};
    concurrent++;
    if (concurrent > peakConcurrent) peakConcurrent = concurrent;
    try {
      await _respond(req);
    } catch (_) {
      // mijoz uzib qo'ygan bo'lishi mumkin
    } finally {
      concurrent--;
    }
  }

  Future<void> _respond(HttpRequest req) async {
    final res = req.response;
    final path = req.uri.path;
    if (forceStatus != 0) {
      res.statusCode = forceStatus;
      await res.close();
      return;
    }
    if (failFirstRequests > 0) {
      failFirstRequests--;
      res.statusCode = 503;
      await res.close();
      return;
    }
    if (path == '/redirect') {
      res.statusCode = 302;
      res.headers.set('location', '/data.bin');
      await res.close();
      return;
    }
    final text = texts[path];
    if (text != null) {
      final bytes = Uint8List.fromList(text.codeUnits);
      res.headers.contentType = ContentType.parse(contentTypes[path] ?? 'text/plain');
      res.contentLength = bytes.length;
      res.add(bytes);
      await res.close();
      return;
    }
    final data = files[path == '/redirect' ? '/data.bin' : path];
    if (data == null) {
      res.statusCode = 404;
      await res.close();
      return;
    }
    res.headers.contentType = ContentType.parse(contentTypes[path] ?? 'application/octet-stream');
    if (etag != null) res.headers.set('etag', etag!);
    if (disposition != null) res.headers.set('content-disposition', disposition!);
    var start = 0;
    var end = data.length - 1;
    final range = req.headers.value('range');
    var partial = false;
    if (supportRanges && range != null) {
      final m = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(range);
      if (m != null) {
        start = int.parse(m.group(1)!);
        if (m.group(2)!.isNotEmpty) end = min(int.parse(m.group(2)!), data.length - 1);
        partial = true;
        rangeStarts.add(start);
        if (start >= data.length) {
          res.statusCode = 416;
          res.headers.set('content-range', 'bytes */${data.length}');
          await res.close();
          return;
        }
      }
    }
    if (partial) {
      res.statusCode = 206;
      res.headers.set('content-range', 'bytes $start-$end/${data.length}');
      res.headers.set('accept-ranges', 'bytes');
    }
    final length = end - start + 1;
    if (!chunkedNoLength) res.contentLength = length;
    var drop = false;
    if (partial && dropFirstRangeResponses > 0 && length > 64 * 1024) {
      dropFirstRangeResponses--;
      drop = true;
    }
    if (drop) {
      // Sarlavhani qo'lda yozib, tanani yarmida uzamiz (haqiqiy ulanish uzilishi kabi)
      final socket = await res.detachSocket(writeHeaders: false);
      final head = 'HTTP/1.1 206 Partial Content\r\n'
          'content-type: ${res.headers.contentType}\r\n'
          'content-range: bytes $start-$end/${data.length}\r\n'
          'accept-ranges: bytes\r\n'
          'content-length: $length\r\n\r\n';
      socket.add(head.codeUnits);
      socket.add(data.sublist(start, start + length ~/ 2));
      await socket.flush();
      socket.destroy();
      return;
    }
    const chunk = 16 * 1024;
    var sent = 0;
    final limit = length;
    while (sent < limit) {
      final n = min(chunk, limit - sent);
      res.add(data.sublist(start + sent, start + sent + n));
      sent += n;
      if (chunkDelay > Duration.zero) {
        await res.flush();
        await Future<void>.delayed(chunkDelay);
      }
    }
    await res.close();
  }
}
