@Tags(['ffmpeg'])
library;

// HLS ni haqiqiy ffmpeg bilan tayyorlab, mahalliy serverdan yuklab, .mp4 ga birlashtirish sinovi
import 'dart:convert';
import 'dart:io';

import 'package:any_to_any/downloader/common.dart';
import 'package:any_to_any/downloader/hls.dart';
import 'package:any_to_any/services/media_tools.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_server.dart';

Future<void> ff(List<String> args) async {
  final r = await Process.run('ffmpeg', ['-v', 'error', '-y', ...args]);
  expect(r.exitCode, 0, reason: 'ffmpeg ${args.join(' ')}\n${r.stderr}');
}

Future<Map<String, dynamic>> probe(String path) async {
  final r = await Process.run('ffprobe', ['-v', 'error', '-show_streams', '-show_format', '-of', 'json', path]);
  expect(r.exitCode, 0, reason: r.stderr.toString());
  return jsonDecode(r.stdout as String) as Map<String, dynamic>;
}

void main() {
  late Directory src;
  late Directory work;
  late TestServer server;

  void serveDir(Directory d, String prefix) {
    for (final f in d.listSync().whereType<File>()) {
      final name = f.uri.pathSegments.last;
      server.files['$prefix/$name'] = f.readAsBytesSync();
      if (name.endsWith('.m3u8')) {
        server.texts['$prefix/$name'] = f.readAsStringSync();
        server.contentTypes['$prefix/$name'] = 'application/vnd.apple.mpegurl';
      }
    }
  }

  setUpAll(() async {
    src = await Directory.systemTemp.createTemp('a2a_hls_src');
    // 4 soniyalik video, har soniyada kalit kadr (bo'laklar uchun)
    await ff([
      '-f', 'lavfi', '-i', 'testsrc=duration=4:size=320x240:rate=25',
      '-f', 'lavfi', '-i', 'sine=frequency=440:duration=4',
      '-c:v', 'libx264', '-g', '25', '-keyint_min', '25', '-sc_threshold', '0', '-pix_fmt', 'yuv420p',
      '-c:a', 'aac', '-shortest', '${src.path}/base.mp4',
    ]);
    Directory('${src.path}/plain').createSync();
    await ff([
      '-i', '${src.path}/base.mp4', '-c', 'copy', '-f', 'hls', '-hls_time', '1', '-hls_playlist_type', 'vod',
      '-hls_segment_filename', '${src.path}/plain/seg%d.ts', '${src.path}/plain/index.m3u8',
    ]);
    // AES-128
    Directory('${src.path}/enc').createSync();
    File('${src.path}/enc/secret.key').writeAsBytesSync(TestServer.random(16, seed: 77));
    File('${src.path}/keyinfo.txt').writeAsStringSync('secret.key\n${src.path}/enc/secret.key\n00112233445566778899aabbccddeeff\n');
    await ff([
      '-i', '${src.path}/base.mp4', '-c', 'copy', '-f', 'hls', '-hls_time', '1', '-hls_playlist_type', 'vod',
      '-hls_key_info_file', '${src.path}/keyinfo.txt', '-hls_segment_filename', '${src.path}/enc/seg%d.ts',
      '${src.path}/enc/index.m3u8',
    ]);
    // alohida audio oqimi bilan bosh ro'yxat
    Directory('${src.path}/split').createSync();
    await ff([
      '-i', '${src.path}/base.mp4', '-map', '0:v', '-map', '0:a', '-c', 'copy', '-f', 'hls', '-hls_time', '1',
      '-hls_playlist_type', 'vod', '-var_stream_map', 'v:0,agroup:aud a:0,agroup:aud,default:yes',
      '-master_pl_name', 'master.m3u8', '-hls_segment_filename', '${src.path}/split/s%v_%d.ts', '${src.path}/split/v%v.m3u8',
    ]);
  });

  tearDownAll(() => src.delete(recursive: true));

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux; // tizim ffmpeg'i ishlatiladi
    server = TestServer();
    await server.start();
    work = await Directory.systemTemp.createTemp('a2a_hls_work');
    serveDir(Directory('${src.path}/plain'), '/plain');
    serveDir(Directory('${src.path}/enc'), '/enc');
    serveDir(Directory('${src.path}/split'), '/split');
  });

  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    await server.close();
    await work.delete(recursive: true);
  });

  Future<HlsMedia> media(String path, {Map<String, String> headers = const {}}) async {
    final (text, url) = await fetchText(server.url(path), headers: headers);
    return parseHls(text, url) as HlsMedia;
  }

  test('plain HLS: downloads every part in parallel and muxes to a playable mp4', () async {
    server.chunkDelay = const Duration(milliseconds: 3);
    final m = await media('/plain/index.m3u8');
    expect(m.segments.length, greaterThanOrEqualTo(3));
    var bytes = 0;
    final seen = <int>[];
    final playlist = await downloadHlsMedia(m, Directory('${work.path}/hls'),
        parallel: 6, onBytes: (b) => bytes += b, onSegment: (d, t) => seen.add(d));
    expect(seen.last, m.segments.length);
    expect(bytes, greaterThan(10000));
    expect(server.peakConcurrent, greaterThan(1), reason: 'parts are fetched in parallel');

    final out = '${work.path}/out.mp4';
    expect(await runFfmpeg(hlsMuxArgs(videoPlaylist: playlist.path, outPath: out)), isTrue);
    final info = await probe(out);
    final streams = (info['streams'] as List).cast<Map<String, dynamic>>();
    expect(streams.map((s) => s['codec_name']), containsAll(['h264', 'aac']));
    expect(double.parse(info['format']['duration'] as String), closeTo(4.0, 0.6));
  });

  test('AES-128 encrypted HLS is decrypted into a clean mp4', () async {
    final m = await media('/enc/index.m3u8');
    expect(m.segments.first.key, isNotNull);
    final playlist = await downloadHlsMedia(m, Directory('${work.path}/hls'));
    final local = playlist.readAsStringSync();
    expect(local, contains('METHOD=AES-128'));
    expect(local, isNot(contains('http')), reason: 'local playlist refers to local files only');
    expect(File('${work.path}/hls/index_key0.bin').existsSync(), isTrue);

    final out = '${work.path}/out.mp4';
    expect(await runFfmpeg(hlsMuxArgs(videoPlaylist: playlist.path, outPath: out)), isTrue);
    final info = await probe(out);
    expect(double.parse(info['format']['duration'] as String), closeTo(4.0, 0.6));
    // to'liq dekodlanadi (shifr to'g'ri ochilgan)
    final dec = await Process.run('ffmpeg', ['-v', 'error', '-i', out, '-f', 'null', '-']);
    expect(dec.exitCode, 0);
    expect((dec.stderr as String).trim(), isEmpty, reason: 'no decode errors: ${dec.stderr}');
  });

  test('master playlist with a separate audio stream: both are fetched and muxed', () async {
    final (text, url) = await fetchText(server.url('/split/master.m3u8'));
    final master = parseHls(text, url) as HlsMaster;
    final variant = master.byQuality.first;
    final audioUrl = master.audioFor(variant);
    expect(audioUrl, isNotNull, reason: 'ffmpeg wrote a separate audio group');
    final (vt, vu) = await fetchText(variant.url);
    final (at, au) = await fetchText(audioUrl!);
    final video = await downloadHlsMedia(parseHls(vt, vu) as HlsMedia, Directory('${work.path}/hls'), name: 'video');
    final audio = await downloadHlsMedia(parseHls(at, au) as HlsMedia, Directory('${work.path}/hls'), name: 'audio');
    final out = '${work.path}/out.mp4';
    expect(await runFfmpeg(hlsMuxArgs(videoPlaylist: video.path, audioPlaylist: audio.path, outPath: out)), isTrue);
    final streams = ((await probe(out))['streams'] as List).cast<Map<String, dynamic>>();
    expect(streams.map((s) => s['codec_type']), containsAll(['video', 'audio']));
  });

  test('the page headers are sent with every part request', () async {
    final headers = {'Referer': 'https://site.example/watch', 'Cookie': 'sid=1'};
    final m = await media('/plain/index.m3u8', headers: headers);
    await downloadHlsMedia(m, Directory('${work.path}/hls'), headers: headers);
    final seg = m.segments.first.url.path;
    expect(server.seenHeaders[seg]!['referer'], 'https://site.example/watch');
    expect(server.seenHeaders[seg]!['cookie'], 'sid=1');
  });

  test('a missing part fails the whole download with a clear message', () async {
    final m = await media('/plain/index.m3u8');
    server.files.remove(m.segments[2].url.path);
    await expectLater(
      downloadHlsMedia(m, Directory('${work.path}/hls'), retryDelay: const Duration(milliseconds: 5)),
      throwsA(isA<DownloadException>().having((e) => e.message, 'm', contains('topilmadi'))),
    );
  });

  test('cancelling mid-way stops the workers', () async {
    server.chunkDelay = const Duration(milliseconds: 20);
    final m = await media('/plain/index.m3u8');
    final cancel = CancelToken();
    final future = downloadHlsMedia(m, Directory('${work.path}/hls'), cancel: cancel, parallel: 2, onSegment: (d, t) {
      if (d == 1) cancel.cancel();
    });
    await expectLater(future, throwsA(isA<DownloadCancelled>()));
  });

  test('live streams and DRM are refused before anything is downloaded', () async {
    final live = parseHls('#EXTM3U\n#EXTINF:2,\n${server.base}/plain/seg0.ts\n', server.url('/x.m3u8')) as HlsMedia;
    await expectLater(downloadHlsMedia(live, Directory('${work.path}/a')), throwsA(isA<DownloadException>().having((e) => e.message, 'm', contains('jonli'))));
    final drm = parseHls('#EXTM3U\n#EXT-X-KEY:METHOD=SAMPLE-AES,URI="skd://x"\n#EXTINF:2,\na.ts\n#EXT-X-ENDLIST\n', server.url('/x.m3u8')) as HlsMedia;
    await expectLater(downloadHlsMedia(drm, Directory('${work.path}/b')), throwsA(isA<DownloadException>().having((e) => e.message, 'm', contains('DRM'))));
    expect(server.hits.containsKey('/plain/seg0.ts'), isFalse);
  });
}
