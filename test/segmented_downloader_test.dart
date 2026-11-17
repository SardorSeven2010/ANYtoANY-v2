import 'dart:io';

import 'package:any_to_any/downloader/common.dart';
import 'package:any_to_any/downloader/segmented.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_server.dart';

void main() {
  late TestServer server;
  late Directory dir;
  late File out;

  setUp(() async {
    server = TestServer();
    await server.start();
    dir = await Directory.systemTemp.createTemp('a2a_dl');
    out = File('${dir.path}/video.mp4');
  });

  tearDown(() async {
    await server.close();
    await dir.delete(recursive: true);
  });

  List<String> leftovers() => dir.listSync().map((e) => e.uri.pathSegments.last).where((n) => n != 'video.mp4').toList();

  group('probe', () {
    test('reads size, range support, type, name and etag without downloading the file', () async {
      server.files['/data.bin'] = TestServer.random(300 * 1024);
      server.contentTypes['/data.bin'] = 'video/mp4';
      server.disposition = 'attachment; filename="Sinov video.mp4"';
      final p = await probeUrl(server.url('/data.bin'));
      expect(p.length, 300 * 1024);
      expect(p.acceptsRanges, isTrue);
      expect(p.contentType, 'video/mp4');
      expect(p.fileName, 'Sinov video.mp4');
      expect(p.etag, '"v1"');
      expect(server.rangeStarts, [0]);
    });

    test('follows redirects', () async {
      server.files['/data.bin'] = TestServer.random(50 * 1024);
      final p = await probeUrl(server.url('/redirect'));
      expect(p.length, 50 * 1024);
      expect(p.url.path, '/data.bin');
    });

    test('server without Range: size from Content-Length, ranges off', () async {
      server.files['/data.bin'] = TestServer.random(80 * 1024);
      server.supportRanges = false;
      final p = await probeUrl(server.url('/data.bin'));
      expect(p.length, 80 * 1024);
      expect(p.acceptsRanges, isFalse);
    });

    test('clear messages for 404 and 403', () async {
      await expectLater(probeUrl(server.url('/yoq')), throwsA(isA<DownloadException>().having((e) => e.message, 'm', contains('topilmadi'))));
      server.forceStatus = 403;
      await expectLater(probeUrl(server.url('/data.bin')), throwsA(isA<DownloadException>().having((e) => e.message, 'm', contains('ruxsat'))));
    });

    test('sends the page headers (Referer, Cookie) so protected files can be fetched', () async {
      server.files['/data.bin'] = TestServer.random(1024);
      await probeUrl(server.url('/data.bin'), headers: {'Referer': 'https://example.com/page', 'Cookie': 'a=b'});
      expect(server.seenHeaders['/data.bin']!['referer'], 'https://example.com/page');
      expect(server.seenHeaders['/data.bin']!['cookie'], 'a=b');
      expect(server.seenHeaders['/data.bin']!['user-agent'], contains('Mozilla'));
    });
  });

  group('segmented download', () {
    test('6 parallel parts give an identical file and clean up after themselves', () async {
      final data = TestServer.random(6 * 1024 * 1024 + 123);
      server.files['/data.bin'] = data;
      server.chunkDelay = const Duration(milliseconds: 2);
      final progress = <DownloadProgress>[];
      final d = SegmentedDownloader(url: server.url('/data.bin'), outFile: out, segments: 6);
      await d.run(onProgress: progress.add);
      expect(out.readAsBytesSync(), data);
      expect(d.usedSegments, 6);
      expect(server.peakConcurrent, inInclusiveRange(5, 7), reason: '6 parallel connections (+ probe)');
      expect(progress.last.received, data.length);
      expect(progress.last.total, data.length);
      expect(progress.last.fraction, 1.0);
      var prev = 0;
      for (final p in progress) {
        expect(p.received, greaterThanOrEqualTo(prev), reason: 'progress never goes backwards');
        prev = p.received;
      }
      expect(leftovers(), isEmpty, reason: 'no .part / .cdl / .tmp files remain');
    });

    test('18 parts (PRO maximum)', () async {
      final data = TestServer.random(9 * 1024 * 1024 + 7, seed: 5);
      server.files['/data.bin'] = data;
      server.chunkDelay = const Duration(milliseconds: 2);
      final d = SegmentedDownloader(url: server.url('/data.bin'), outFile: out, segments: 18);
      await d.run();
      expect(out.readAsBytesSync(), data);
      expect(d.usedSegments, 18);
      expect(server.peakConcurrent, inInclusiveRange(16, 19));
      expect(leftovers(), isEmpty);
    });

    test('a small file is not split into tiny pieces', () async {
      final data = TestServer.random(600 * 1024, seed: 2);
      server.files['/data.bin'] = data;
      final d = SegmentedDownloader(url: server.url('/data.bin'), outFile: out, segments: 18);
      await d.run();
      expect(out.readAsBytesSync(), data);
      expect(d.usedSegments, 2, reason: '600 KB / 256 KB minimum part');
    });

    test('a tiny file uses one plain connection', () async {
      final data = TestServer.random(40 * 1024, seed: 3);
      server.files['/data.bin'] = data;
      final d = SegmentedDownloader(url: server.url('/data.bin'), outFile: out, segments: 12);
      await d.run();
      expect(out.readAsBytesSync(), data);
      expect(d.usedSegments, 1);
    });

    test('server without Range support: downloads with one connection', () async {
      final data = TestServer.random(2 * 1024 * 1024, seed: 4);
      server.files['/data.bin'] = data;
      server.supportRanges = false;
      final d = SegmentedDownloader(url: server.url('/data.bin'), outFile: out, segments: 8);
      await d.run();
      expect(out.readAsBytesSync(), data);
      expect(d.usedSegments, 1);
    });

    test('unknown length (chunked) streams to the end', () async {
      final data = TestServer.random(700 * 1024, seed: 6);
      server.files['/data.bin'] = data;
      server.supportRanges = false;
      server.chunkedNoLength = true;
      final d = SegmentedDownloader(url: server.url('/data.bin'), outFile: out, segments: 8);
      final progress = <DownloadProgress>[];
      await d.run(onProgress: progress.add);
      expect(out.readAsBytesSync(), data);
      expect(progress.last.received, data.length);
    });

    test('connections that drop mid-way are resumed from where they stopped', () async {
      final data = TestServer.random(4 * 1024 * 1024, seed: 8);
      server.files['/data.bin'] = data;
      server.dropFirstRangeResponses = 5;
      final d = SegmentedDownloader(url: server.url('/data.bin'), outFile: out, segments: 6, retryDelay: const Duration(milliseconds: 10));
      await d.run();
      expect(out.readAsBytesSync(), data);
      // qayta urinishlar 0-baytdan emas, uzilgan joydan boshlangan
      final resumed = server.rangeStarts.where((s) => s > 0).toSet();
      expect(resumed.length, greaterThan(6), reason: 'retries start in the middle of a part');
    });

    test('temporary server errors (503) are retried', () async {
      final data = TestServer.random(1024 * 1024, seed: 9);
      server.files['/data.bin'] = data;
      final p = await probeUrl(server.url('/data.bin'));
      server.failFirstRequests = 3;
      final d = SegmentedDownloader(url: server.url('/data.bin'), outFile: out, segments: 4, retryDelay: const Duration(milliseconds: 10));
      await d.run(probe: p);
      expect(out.readAsBytesSync(), data);
    });

    test('a permanent error stops with a clear message and no endless retry', () async {
      server.files['/data.bin'] = TestServer.random(1024 * 1024);
      final p = await probeUrl(server.url('/data.bin'));
      server.forceStatus = 403;
      final d = SegmentedDownloader(url: server.url('/data.bin'), outFile: out, segments: 4, retryDelay: const Duration(milliseconds: 10));
      await expectLater(d.run(probe: p), throwsA(isA<DownloadException>().having((e) => e.message, 'm', contains('ruxsat'))));
      expect(out.existsSync(), isFalse);
    });

    test('cancel stops quickly; running again resumes instead of starting over', () async {
      final data = TestServer.random(8 * 1024 * 1024, seed: 10);
      server.files['/data.bin'] = data;
      server.chunkDelay = const Duration(milliseconds: 5);
      final cancel = CancelToken();
      var cancelled = false;
      final first = SegmentedDownloader(url: server.url('/data.bin'), outFile: out, segments: 6);
      await expectLater(
        first.run(
          cancel: cancel,
          onProgress: (p) {
            if (!cancelled && p.received > 3 * 1024 * 1024) {
              cancelled = true;
              cancel.cancel();
            }
          },
        ),
        throwsA(isA<DownloadCancelled>()),
      );
      expect(out.existsSync(), isFalse, reason: 'no half-finished final file');
      final partials = dir.listSync().where((e) => e.path.contains('.part')).length;
      expect(partials, greaterThan(0), reason: 'parts are kept for resuming');

      server.rangeStarts.clear();
      server.chunkDelay = Duration.zero;
      final second = SegmentedDownloader(url: server.url('/data.bin'), outFile: out, segments: 6);
      await second.run();
      expect(out.readAsBytesSync(), data);
      expect(server.rangeStarts.where((s) => s > 0).length, greaterThan(0));
      expect(leftovers(), isEmpty);
    });

    test('a changed file on the server does not mix with old parts', () async {
      final v1 = TestServer.random(2 * 1024 * 1024, seed: 11);
      final v2 = TestServer.random(2 * 1024 * 1024, seed: 12);
      server.files['/data.bin'] = v1;
      server.chunkDelay = const Duration(milliseconds: 5);
      final cancel = CancelToken();
      var stopped = false;
      await expectLater(
        SegmentedDownloader(url: server.url('/data.bin'), outFile: out, segments: 4).run(
          cancel: cancel,
          onProgress: (p) {
            if (!stopped && p.received > 600 * 1024) {
              stopped = true;
              cancel.cancel();
            }
          },
        ),
        throwsA(isA<DownloadCancelled>()),
      );
      server.files['/data.bin'] = v2;
      server.etag = '"v2"';
      server.chunkDelay = Duration.zero;
      await SegmentedDownloader(url: server.url('/data.bin'), outFile: out, segments: 4).run();
      expect(out.readAsBytesSync(), v2);
    });
  });

  test('file name helpers', () {
    expect(safeFileName('a/b:c*d?.mp4'), 'a_b_c_d_.mp4');
    expect(safeFileName('   '), 'video');
    expect(safeFileName('x' * 200).length, 80);
    expect(fileNameFromDisposition("attachment; filename*=UTF-8''Ali%20video.mp4"), 'Ali video.mp4');
    expect(fileNameFromDisposition('attachment; filename=plain.mp4'), 'plain.mp4');
    expect(fileNameFromDisposition(null), isNull);
  });
}
