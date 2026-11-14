@Tags(['ffmpeg'])
library;

// Linux rejimida ilovaning konvertatsiya funksiyasi tizimning haqiqiy ffmpeg dasturi bilan sinaladi.
import 'dart:io';

import 'package:any_to_any/services/media_tools.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class FakePathProvider extends PathProviderPlatform with MockPlatformInterfaceMixin {
  FakePathProvider(this.temp);
  final String temp;
  @override
  Future<String?> getTemporaryPath() async => temp;
}

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('a2a_linux');
    PathProviderPlatform.instance = FakePathProvider(dir.path);
    Future<void> make(List<String> args) async {
      final r = await Process.run('ffmpeg', ['-v', 'error', '-y', ...args]);
      expect(r.exitCode, 0, reason: r.stderr.toString());
    }

    await make(['-f', 'lavfi', '-i', 'testsrc=size=321x241:rate=15:duration=2', '-f', 'lavfi', '-i',
      'sine=frequency=440:duration=2', '-c:v', 'libx264', '-pix_fmt', 'yuv444p', '-shortest', '${dir.path}/dars "1".mp4']);
    await make(['-f', 'lavfi', '-i', 'testsrc=size=300x200:rate=1:duration=1', '-frames:v', '1', '${dir.path}/surat.png']);
  });

  tearDownAll(() => dir.delete(recursive: true));

  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.linux);
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  Future<ConvertOutcome> convert(String name, String format, {String codec = 'libx264', String? bitrate}) async {
    final out = Directory('${dir.path}/out')..createSync(recursive: true);
    return convertFile(
      inPath: '${dir.path}/$name',
      fileName: name,
      format: format,
      outDir: out,
      usedPaths: <String>{},
      videoCodec: codec,
      audioBitrate: bitrate,
    );
  }

  Future<String> probe(String path, String entries) async {
    final r = await Process.run('ffprobe', ['-v', 'error', '-show_entries', entries, '-of', 'csv=p=0', path]);
    return r.stdout.toString().trim();
  }

  for (final c in [
    ('mp3', 'libx264', '192k', 'mp3'),
    ('m4a', 'libx264', null, 'aac'),
    ('flac', 'libx264', null, 'flac'),
    ('ogg', 'libx264', null, 'vorbis'),
  ]) {
    test('video -> ${c.$1} (audio only)', () async {
      final r = await convert('dars "1".mp4', c.$1, codec: c.$2, bitrate: c.$3);
      expect(r.error, isNull);
      expect(await probe(r.outputs.single, 'stream=codec_name'), c.$4);
    });
  }

  for (final c in [
    ('mkv', 'libx265', 'hevc'),
    ('webm', 'libvpx-vp9', 'vp9'),
    ('avi', 'mpeg4', 'mpeg4'),
    ('mp4', 'copy', 'h264'),
    ('mov', 'libx264', 'h264'),
  ]) {
    test('video -> ${c.$1} with ${c.$2}', () async {
      final r = await convert('dars "1".mp4', c.$1, codec: c.$2);
      expect(r.error, isNull);
      final codecs = await probe(r.outputs.single, 'stream=codec_name');
      expect(codecs.split('\n').first, c.$3);
    });
  }

  test('video -> gif and png', () async {
    expect((await convert('dars "1".mp4', 'gif')).error, isNull);
    final png = await convert('dars "1".mp4', 'png');
    expect(png.error, isNull);
    expect(pngSize(File(png.outputs.single).readAsBytesSync()), (321, 241));
  });

  test('image -> pdf (png goes through ffmpeg first)', () async {
    final r = await convert('surat.png', 'pdf');
    expect(r.error, isNull);
    expect(String.fromCharCodes(File(r.outputs.single).readAsBytesSync().take(5)), '%PDF-');
  });

  test('missing ffmpeg gives a clear message', () {
    expect(const FfmpegMissingException().toString(), contains('sudo apt install ffmpeg'));
  });
}
