import 'dart:convert';
import 'dart:io';

import 'package:any_to_any/downloader/common.dart';
import 'package:any_to_any/downloader/detected.dart';
import 'package:any_to_any/downloader/detector_js.dart';
import 'package:any_to_any/downloader/job_runner.dart';
import 'package:any_to_any/downloader/segmented.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 30));

ProbeResult probeOf(String url, int? length) => ProbeResult(url: Uri.parse(url), length: length, acceptsRanges: true);

void main() {
  group('classify', () {
    test('by extension and by content type', () {
      DetectedKind? k(String u, [String m = '']) => classifyDetected(Uri.parse(u), m);
      expect(k('https://a/v.mp4'), DetectedKind.video);
      expect(k('https://a/v.webm?x=1'), DetectedKind.video);
      expect(k('https://a/play.m3u8'), DetectedKind.hls);
      expect(k('https://a/stream', 'application/vnd.apple.mpegurl'), DetectedKind.hls);
      expect(k('https://a/m.mpd'), DetectedKind.dash);
      expect(k('https://a/s.mp3'), DetectedKind.audio);
      expect(k('https://a/get?id=1', 'video/mp4'), DetectedKind.video);
      expect(k('blob:https://a/1-2'), DetectedKind.blob);
    });

    test('segments, pictures, subtitles and other schemes are ignored', () {
      DetectedKind? k(String u, [String m = '']) => classifyDetected(Uri.parse(u), m);
      for (final u in ['https://a/s1.ts', 'https://a/c.m4s', 'https://a/p.jpg', 'https://a/x.vtt', 'https://a/app.js', 'ftp://a/v.mp4', 'file:///v.mp4']) {
        expect(k(u), isNull, reason: u);
      }
      expect(k('https://a/page'), isNull);
    });
  });

  group('detector', () {
    late MediaDetector d;
    late int probes;
    final texts = <String, String>{};

    setUp(() {
      probes = 0;
      texts.clear();
      d = MediaDetector(
        probe: (u, h) async {
          probes++;
          return probeOf(u.toString(), u.path.contains('tiny') ? 5000 : 12 * 1024 * 1024);
        },
        fetch: (u, h) async => (texts[u.toString()] ?? '', u),
      );
    });

    test('messages from the page script are collected once per address', () async {
      String msg(String url, {String type = '', String title = 'Kino'}) => jsonEncode({'url': url, 'type': type, 'title': title, 'page': 'https://site.test/watch'});
      d.onMessage(msg('https://cdn.test/a.mp4'));
      d.onMessage(msg('https://cdn.test/a.mp4#t=5'));
      d.onMessage(msg('https://cdn.test/b.webm'));
      d.onMessage('not json');
      d.onMessage(msg('https://cdn.test/seg.ts'));
      await settle();
      expect(d.items.map((m) => m.url.path), ['/a.mp4', '/b.webm']);
      expect(d.count, 2);
      expect(d.items.first.pageTitle, 'Kino');
      expect(d.items.first.bytes, 12 * 1024 * 1024, reason: 'size found with a Range probe');
    });

    test('the page headers are used when checking the files', () async {
      Map<String, String>? seen;
      final dd = MediaDetector(probe: (u, h) async {
        seen = h;
        return probeOf(u.toString(), 1 << 20);
      });
      dd.headers = {'Referer': 'https://site.test/watch', 'Cookie': 'a=1'};
      dd.add(url: 'https://cdn.test/a.mp4');
      await settle();
      expect(seen, {'Referer': 'https://site.test/watch', 'Cookie': 'a=1'});
    });

    test('tiny files (ads, icons) are hidden', () async {
      d.add(url: 'https://cdn.test/tiny.mp4');
      d.add(url: 'https://cdn.test/real.mp4');
      await settle();
      expect(d.items.map((m) => m.url.path), ['/real.mp4']);
    });

    test('HLS master playlist lists qualities and hides its own variant playlists', () async {
      texts['https://cdn.test/master.m3u8'] = '#EXTM3U\n'
          '#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360\nlow.m3u8\n'
          '#EXT-X-STREAM-INF:BANDWIDTH=2800000,RESOLUTION=1920x1080\nhigh.m3u8\n';
      // avval variant, keyin bosh ro'yxat kelsa ham yashirinadi
      d.add(url: 'https://cdn.test/low.m3u8');
      d.add(url: 'https://cdn.test/master.m3u8');
      await settle();
      d.add(url: 'https://cdn.test/high.m3u8');
      await settle();
      expect(d.items.map((m) => m.url.path), ['/master.m3u8']);
      expect(d.items.single.qualities.map((q) => q.label), ['1080p', '360p']);
    });

    test('a plain HLS playlist shows its length; DRM and live streams are marked', () async {
      texts['https://cdn.test/ok.m3u8'] = '#EXTM3U\n#EXTINF:30,\na.ts\n#EXTINF:30,\nb.ts\n#EXT-X-ENDLIST\n';
      texts['https://cdn.test/drm.m3u8'] = '#EXTM3U\n#EXT-X-KEY:METHOD=SAMPLE-AES,URI="skd://x"\n#EXTINF:30,\na.ts\n#EXT-X-ENDLIST\n';
      texts['https://cdn.test/live.m3u8'] = '#EXTM3U\n#EXTINF:6,\na.ts\n';
      d.add(url: 'https://cdn.test/ok.m3u8');
      d.add(url: 'https://cdn.test/drm.m3u8');
      d.add(url: 'https://cdn.test/live.m3u8');
      await settle();
      final byPath = {for (final m in d.items) m.url.path: m};
      expect(byPath['/ok.m3u8']!.seconds, 60);
      expect(byPath['/ok.m3u8']!.downloadable, isTrue);
      expect(byPath['/drm.m3u8']!.error, contains('DRM'));
      expect(byPath['/drm.m3u8']!.downloadable, isFalse);
      expect(byPath['/live.m3u8']!.error, 'Jonli efir');
    });

    test('DASH with DRM is marked', () async {
      texts['https://cdn.test/a.mpd'] = '<MPD><Period><ContentProtection schemeIdUri="urn:uuid:x"/></Period></MPD>';
      d.add(url: 'https://cdn.test/a.mpd');
      await settle();
      expect(d.items.single.error, contains('DRM'));
    });

    test('blob videos are shown as protected and cannot be downloaded', () async {
      final m = d.add(url: 'blob:https://site.test/1234')!;
      await settle();
      expect(m.kind, DetectedKind.blob);
      expect(m.downloadable, isFalse);
      expect(m.typeLabel, 'Himoyalangan oqim');
      expect(probes, 0, reason: 'blob addresses are never fetched');
    });

    test('a failing probe keeps the item; reset clears the list on navigation', () async {
      final dd = MediaDetector(probe: (u, h) async => throw const DownloadException('x'));
      dd.add(url: 'https://cdn.test/a.mp4');
      await settle();
      expect(dd.count, 1);
      expect(dd.items.single.bytes, isNull);
      dd.reset();
      expect(dd.count, 0);
    });

    test('suggested title: page title, else file name', () {
      final a = DetectedMedia(url: Uri.parse('https://cdn.test/x/film_01.mp4'), kind: DetectedKind.video, pageTitle: 'Zo\'r kino: 1-qism', page: Uri.parse('https://s'));
      final b = DetectedMedia(url: Uri.parse('https://cdn.test/x/film_01.mp4'), kind: DetectedKind.video, pageTitle: '', page: Uri.parse('https://s'));
      expect(d.suggestedTitle(a), "Zo'r kino_ 1-qism");
      expect(d.suggestedTitle(b), 'film_01');
      expect(a.mediaKind, MediaKind.direct);
      expect(DetectedMedia(url: Uri.parse('https://a/m.m3u8'), kind: DetectedKind.hls, pageTitle: '', page: Uri.parse('https://s')).mediaKind, MediaKind.hls);
    });
  });

  group('page script (real DOM via jsdom)', () {
    test('finds videos in video/source tags, fetch, XHR and ignores segments', () async {
      final node = await Process.run('node', ['--version']).catchError((Object _) => ProcessResult(0, 127, '', ''));
      if (node.exitCode != 0) return markTestSkipped('node o\'rnatilmagan');
      final dir = await Directory.systemTemp.createTemp('a2a_detector');
      addTearDown(() => dir.delete(recursive: true));
      final script = File('${dir.path}/detector.js')..writeAsStringSync(detectorScript);
      final r = await Process.run('node', ['tools/detector_check.js', script.path]);
      if (r.exitCode == 2) return markTestSkipped('jsdom o\'rnatilmagan (NODE_PATH)');
      expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
      expect(r.stdout.toString(), contains('ALL OK'));
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
