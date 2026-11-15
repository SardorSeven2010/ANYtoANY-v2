@Tags(['ffmpeg'])
library;

// Yuklash jarayoni boshidan oxirigacha: mahalliy server + haqiqiy ffmpeg
import 'dart:convert';
import 'dart:io';

import 'package:any_to_any/downloader/common.dart';
import 'package:any_to_any/downloader/job_runner.dart';
import 'package:any_to_any/services/gallery.dart';
import 'package:any_to_any/services/media_tools.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_server.dart';

Future<ProcessResult> run(String exe, List<String> args) => Process.run(exe, args);

Future<void> ff(List<String> args) async {
  final r = await run('ffmpeg', ['-v', 'error', '-y', ...args]);
  expect(r.exitCode, 0, reason: 'ffmpeg ${args.join(' ')}\n${r.stderr}');
}

Future<Map<String, dynamic>> probe(String path) async {
  final r = await run('ffprobe', ['-v', 'error', '-show_streams', '-show_format', '-of', 'json', path]);
  expect(r.exitCode, 0, reason: r.stderr.toString());
  return jsonDecode(r.stdout as String) as Map<String, dynamic>;
}

List<String> codecs(Map<String, dynamic> info) => (info['streams'] as List).map((s) => (s as Map)['codec_name'] as String).toList();

Future<bool> hasEncoder(String name) async {
  final r = await run('ffmpeg', ['-hide_banner', '-encoders']);
  return (r.stdout as String).contains(name);
}

void main() {
  late Directory src;
  late Directory out;
  late Directory root;
  late TestServer server;

  void serve(String path, String file, {String? type}) {
    server.files[path] = File(file).readAsBytesSync();
    if (type != null) server.contentTypes[path] = type;
  }

  void serveDir(Directory d, String prefix) {
    for (final f in d.listSync().whereType<File>()) {
      final name = f.uri.pathSegments.last;
      server.files['$prefix/$name'] = f.readAsBytesSync();
      if (name.endsWith('.m3u8') || name.endsWith('.mpd')) {
        server.texts['$prefix/$name'] = f.readAsStringSync();
        server.contentTypes['$prefix/$name'] = name.endsWith('.mpd') ? 'application/dash+xml' : 'application/vnd.apple.mpegurl';
      }
    }
  }

  setUpAll(() async {
    final v = await Process.run('ffmpeg', ['-version']);
    printOnFailure((v.stdout as String).split('\n').first);
    src = await Directory.systemTemp.createTemp('a2a_job_src');
    const gop = ['-g', '25', '-keyint_min', '25', '-sc_threshold', '0'];
    // 3 MB atrofidagi mp4: bo'laklab yuklashni sinash uchun
    await ff([
      '-f', 'lavfi', '-i', 'testsrc2=duration=6:size=640x360:rate=25',
      '-f', 'lavfi', '-i', 'sine=frequency=440:duration=6',
      '-c:v', 'libx264', '-b:v', '4M', ...gop, '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-shortest', '${src.path}/big.mp4',
    ]);
    await ff(['-i', '${src.path}/big.mp4', '-c', 'copy', '${src.path}/clip.mkv']);
    if (await hasEncoder('libvpx') && await hasEncoder('libvorbis')) {
      await ff([
        '-f', 'lavfi', '-i', 'testsrc=duration=3:size=320x240:rate=25', '-f', 'lavfi', '-i', 'sine=frequency=330:duration=3',
        '-c:v', 'libvpx', '-b:v', '500k', '-c:a', 'libvorbis', '-shortest', '${src.path}/clip.webm',
      ]);
    }
    Directory('${src.path}/hls').createSync();
    File('${src.path}/hls/k.key').writeAsBytesSync(TestServer.random(16, seed: 9));
    File('${src.path}/keyinfo.txt').writeAsStringSync('k.key\n${src.path}/hls/k.key\n00112233445566778899aabbccddeeff\n');
    await ff([
      '-i', '${src.path}/big.mp4', '-c', 'copy', '-f', 'hls', '-hls_time', '1', '-hls_playlist_type', 'vod',
      '-hls_key_info_file', '${src.path}/keyinfo.txt', '-hls_segment_filename', '${src.path}/hls/s%d.ts', '${src.path}/hls/index.m3u8',
    ]);
    Directory('${src.path}/split').createSync();
    await ff([
      '-i', '${src.path}/big.mp4', '-map', '0:v', '-map', '0:a', '-c', 'copy', '-f', 'hls', '-hls_time', '1',
      '-hls_playlist_type', 'vod', '-var_stream_map', 'v:0,agroup:aud a:0,agroup:aud,default:yes',
      '-master_pl_name', 'master.m3u8', '-hls_segment_filename', '${src.path}/split/s%v_%d.ts', '${src.path}/split/v%v.m3u8',
    ]);
    Directory('${src.path}/dash').createSync();
    await ff([
      '-i', '${src.path}/big.mp4', '-c', 'copy', '-f', 'dash', '-seg_duration', '2', '${src.path}/dash/manifest.mpd',
    ]);
  });

  tearDownAll(() => src.delete(recursive: true));

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    server = TestServer();
    await server.start();
    out = await Directory.systemTemp.createTemp('a2a_job_out');
    root = await Directory.systemTemp.createTemp('a2a_job_work');
    workRoot = () async => root;
    serve('/big.mp4', '${src.path}/big.mp4', type: 'video/mp4');
    serve('/clip.mkv', '${src.path}/clip.mkv', type: 'video/x-matroska');
    if (File('${src.path}/clip.webm').existsSync()) serve('/clip.webm', '${src.path}/clip.webm', type: 'video/webm');
    serveDir(Directory('${src.path}/hls'), '/hls');
    serveDir(Directory('${src.path}/split'), '/split');
    serveDir(Directory('${src.path}/dash'), '/dash');
  });

  tearDown(() async {
    printOnFailure('oxirgi ffmpeg xatosi: $lastFfmpegError');
    debugDefaultTargetPlatformOverride = null;
    await server.close();
    await out.delete(recursive: true);
    await root.delete(recursive: true);
  });

  JobCallbacks callbacks({List<JobStage>? stages, List<int>? bytes, CancelToken? cancel}) => JobCallbacks(
        cancel: cancel ?? CancelToken(),
        onStage: stages?.add,
        onProgress: (r, t, s) => bytes?.add(r),
      );

  int leftoverWork() => root.listSync(recursive: true).whereType<File>().length;

  test('guessKind: m3u8, mpd and plain files', () {
    expect(guessKind(Uri.parse('https://x/a/index.m3u8?t=1')), MediaKind.hls);
    expect(guessKind(Uri.parse('https://x/a/stream'), contentType: 'application/vnd.apple.mpegurl'), MediaKind.hls);
    expect(guessKind(Uri.parse('https://x/a/manifest.mpd')), MediaKind.dash);
    expect(guessKind(Uri.parse('https://x/a/video.mp4')), MediaKind.direct);
  });

  test('plain mp4: 6 parts, saved as is under the title and the work folder is cleaned', () async {
    server.chunkDelay = const Duration(milliseconds: 2);
    final stages = <JobStage>[];
    final bytes = <int>[];
    final r = await runDownloadJob(
      DownloadRequest(url: server.url('/big.mp4'), title: 'Mening videom', segments: 6),
      out,
      <String>{},
      callbacks(stages: stages, bytes: bytes),
    );
    expect(r.path, endsWith('Mening videom.mp4'));
    expect(File(r.path).readAsBytesSync(), File('${src.path}/big.mp4').readAsBytesSync(), reason: 'untouched, not re-encoded');
    expect(r.segmentsUsed, greaterThan(1));
    expect(server.peakConcurrent, greaterThan(2));
    expect(stages, containsAllInOrder([JobStage.probing, JobStage.downloading]));
    expect(bytes.last, File(r.path).lengthSync());
    expect(leftoverWork(), 0);
  });

  test('the finished video is published to the gallery and the result points to the gallery copy', () async {
    final saved = <String>[];
    final stages = <JobStage>[];
    galleryPublisher = (path, kind, {name}) async {
      saved.add('${kind.name}:${File(path).existsSync()}:${name ?? ''}');
      return const GalleryResult('/storage/emulated/0/Movies/CORE/Galereya.mp4', inGallery: true);
    };
    addTearDown(() => galleryPublisher = publishToGallery);
    final r = await runDownloadJob(DownloadRequest(url: server.url('/big.mp4'), title: 'Galereya'), out, <String>{}, callbacks(stages: stages));
    expect(saved, ['video:true:Galereya.mp4'], reason: 'published once the mp4 is complete');
    expect(r.path, '/storage/emulated/0/Movies/CORE/Galereya.mp4');
    expect(r.inGallery, isTrue);
    expect(r.bytes, greaterThan(100000));
    expect(stages.last, JobStage.saving);
  });

  test('two downloads with the same title do not overwrite each other', () async {
    final used = <String>{};
    final a = await runDownloadJob(DownloadRequest(url: server.url('/big.mp4'), title: 'Bir xil'), out, used, callbacks());
    final b = await runDownloadJob(DownloadRequest(url: server.url('/big.mp4'), title: 'Bir xil'), out, used, callbacks());
    expect(a.path, isNot(b.path));
    expect(File(a.path).existsSync() && File(b.path).existsSync(), isTrue);
  });

  test('mkv is remuxed into mp4 without re-encoding', () async {
    final r = await runDownloadJob(DownloadRequest(url: server.url('/clip.mkv'), title: 'mkv video'), out, <String>{}, callbacks());
    final info = await probe(r.path);
    expect(info['format']['format_name'], contains('mp4'));
    expect(codecs(info), containsAll(['h264', 'aac']));
  });

  test('webm whose audio cannot go into mp4 falls back to H.264 + AAC', () async {
    if (!File('${src.path}/clip.webm').existsSync()) return markTestSkipped('no libvpx/libvorbis');
    final r = await runDownloadJob(DownloadRequest(url: server.url('/clip.webm'), title: 'webm video'), out, <String>{}, callbacks());
    final info = await probe(r.path);
    expect(info['format']['format_name'], contains('mp4'));
    expect(codecs(info), containsAll(['h264', 'aac']));
  });

  test('PRO: H.265 choice re-encodes to HEVC', () async {
    if (!await hasEncoder('libx265')) return markTestSkipped('no libx265');
    final stages = <JobStage>[];
    final r = await runDownloadJob(
      DownloadRequest(url: server.url('/big.mp4'), title: 'hevc', codec: OutputCodec.h265),
      out,
      <String>{},
      callbacks(stages: stages),
    );
    expect(codecs(await probe(r.path)), contains('hevc'));
    expect(stages, contains(JobStage.converting));
  });

  test('PRO: H.264 choice re-encodes from another codec', () async {
    if (!await hasEncoder('libx265')) return markTestSkipped('no libx265');
    final hevc = '${src.path}/hevc_src.mp4';
    await ff(['-i', '${src.path}/big.mp4', '-t', '2', '-c:v', 'libx265', '-tag:v', 'hvc1', '-c:a', 'aac', hevc]);
    serve('/hevc_src.mp4', hevc);
    final r = await runDownloadJob(DownloadRequest(url: server.url('/hevc_src.mp4'), title: 'to264', codec: OutputCodec.h264), out, <String>{}, callbacks());
    expect(codecs(await probe(r.path)), contains('h264'));
  });

  test('HLS with AES-128: parts in parallel, one mp4 at the end, work folder cleaned', () async {
    final bytes = <int>[];
    final r = await runDownloadJob(
      DownloadRequest(url: server.url('/hls/index.m3u8'), title: 'hls video', kind: MediaKind.hls, segments: 8),
      out,
      <String>{},
      callbacks(bytes: bytes),
    );
    final info = await probe(r.path);
    expect(double.parse(info['format']['duration'] as String), closeTo(6.0, 0.8));
    expect(codecs(info), containsAll(['h264', 'aac']));
    expect(bytes, isNotEmpty);
    expect(leftoverWork(), 0);
  });

  test('HLS master with separate audio: best quality and audio are merged', () async {
    final r = await runDownloadJob(
      DownloadRequest(url: server.url('/split/master.m3u8'), title: 'master video', kind: MediaKind.hls),
      out,
      <String>{},
      callbacks(),
    );
    expect(codecs(await probe(r.path)), containsAll(['h264', 'aac']));
  });

  test('DASH: ffmpeg reads the manifest and saves mp4', () async {
    final r = await runDownloadJob(
      DownloadRequest(url: server.url('/dash/manifest.mpd'), title: 'dash video', kind: MediaKind.dash),
      out,
      <String>{},
      callbacks(),
    );
    final info = await probe(r.path);
    expect(double.parse(info['format']['duration'] as String), closeTo(6.0, 0.8));
  });

  test('DASH with DRM or live manifest is refused', () {
    expect(() => checkDashManifest('<MPD><Period><AdaptationSet><ContentProtection schemeIdUri="urn:uuid:edef8ba9"/></AdaptationSet></Period></MPD>'),
        throwsA(isA<DownloadException>().having((e) => e.message, 'm', contains('DRM'))));
    expect(() => checkDashManifest('<MPD type="dynamic"><Period/></MPD>'), throwsA(isA<DownloadException>().having((e) => e.message, 'm', contains('jonli'))));
    expect(() => checkDashManifest('<MPD type="static"><Period/></MPD>'), returnsNormally);
  });

  test('cancel in the middle leaves nothing behind', () async {
    server.chunkDelay = const Duration(milliseconds: 8);
    final cancel = CancelToken();
    var cancelled = false;
    final future = runDownloadJob(
      DownloadRequest(url: server.url('/big.mp4'), title: 'bekor', segments: 6),
      out,
      <String>{},
      JobCallbacks(cancel: cancel, onProgress: (r, t, s) {
        if (!cancelled && r > 200 * 1024) {
          cancelled = true;
          cancel.cancel();
        }
      }),
    );
    await expectLater(future, throwsA(isA<DownloadCancelled>()));
    expect(out.listSync(), isEmpty);
    expect(leftoverWork(), 0);
  });

  test('a failed download does not leave a half-written output', () async {
    server.files.remove('/big.mp4');
    await expectLater(
      runDownloadJob(DownloadRequest(url: server.url('/big.mp4'), title: 'yoq'), out, <String>{}, callbacks()),
      throwsA(isA<DownloadException>()),
    );
    expect(out.listSync(), isEmpty);
  });
}
