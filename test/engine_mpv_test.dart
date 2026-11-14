@Tags(['mpv'])
library;

// Haqiqiy dvigatel (media_kit + libmpv) bilan sinov: Linux'da, ffmpeg va libmpv o'rnatilgan bo'lsa.
import 'dart:async';
import 'dart:io';

import 'package:any_to_any/player/engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

/// Holat shartini tekshirib turadi (hodisa dvigatel ochilayotganda o'tib ketgan bo'lishi mumkin)
Future<void> until(bool Function() cond, {int seconds = 20}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (!cond()) {
    if (DateTime.now().isAfter(end)) throw TimeoutException('shart bajarilmadi');
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}

void main() {
  late Directory dir;
  late String clip;
  late MediaKitEngine engine;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('a2a_mpv');
    clip = '${dir.path}/clip.mp4';
    final r = await Process.run('ffmpeg', [
      '-v', 'error', '-y',
      '-f', 'lavfi', '-i', 'testsrc=duration=4:size=320x240:rate=25',
      '-f', 'lavfi', '-i', 'sine=frequency=440:duration=4',
      '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-shortest', clip,
    ]);
    expect(r.exitCode, 0, reason: r.stderr.toString());
  });

  setUp(() async {
    engine = MediaKitEngine();
    final native = engine.player.platform as NativePlayer;
    await native.setProperty('ao', 'null');
  });

  tearDown(() async => engine.dispose());
  tearDownAll(() => dir.delete(recursive: true));

  test('opens a file: duration, playing, position moves, pause works', () async {
    await engine.open(clip);
    await until(() => engine.duration > Duration.zero);
    expect(engine.duration.inMilliseconds, inInclusiveRange(3500, 4500));
    await until(() => engine.position > const Duration(milliseconds: 300));
    expect(engine.playing, isTrue);
    // Kadr o'lchami faqat video chizilganda (VideoController ulanganda) ma'lum bo'ladi
    expect(engine.videoWidth, anyOf(isNull, 320));
    expect(engine.videoHeight, anyOf(isNull, 240));
    await engine.pause();
    await until(() => !engine.playing);
    // pauzadan keyin joy o'zgarmay qolishini kutamiz (so'nggi kadr yetib kelishi mumkin)
    var stable = false;
    for (var i = 0; i < 20 && !stable; i++) {
      final before = engine.position;
      await Future<void>.delayed(const Duration(milliseconds: 300));
      stable = engine.position == before;
    }
    expect(stable, isTrue, reason: 'paused: position stands still');
    await engine.play();
    await until(() => engine.playing);
  });

  test('seek jumps to the requested position', () async {
    await engine.open(clip, play: false);
    await until(() => engine.duration > Duration.zero);
    await engine.seek(const Duration(seconds: 2));
    await until(() => engine.position >= const Duration(milliseconds: 1900));
    expect(engine.position.inMilliseconds, inInclusiveRange(1900, 2600));
  });

  test('speed from 0.25x to 4x is accepted', () async {
    await engine.open(clip, play: false);
    await until(() => engine.duration > Duration.zero);
    for (final rate in [0.25, 0.5, 1.0, 2.0, 4.0]) {
      await engine.setRate(rate);
      expect(engine.player.state.rate, rate);
    }
  });

  test('4x plays through faster and reports completion', () async {
    await engine.open(clip, play: false);
    await until(() => engine.duration > Duration.zero);
    await engine.setRate(4.0);
    final completed = Completer<void>();
    final sub = engine.completedStream.listen((c) {
      if (c && !completed.isCompleted) completed.complete();
    });
    final started = DateTime.now();
    await engine.play();
    await completed.future.timeout(const Duration(seconds: 15));
    await sub.cancel();
    expect(DateTime.now().difference(started).inMilliseconds, lessThan(3500), reason: '4 s clip at 4x');
  });

  test('starting at a position (used when the decoder is switched)', () async {
    await engine.open(clip, start: const Duration(seconds: 2), play: false);
    await until(() => engine.duration > Duration.zero);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(engine.position.inMilliseconds, greaterThanOrEqualTo(1900));
  });

  test('software and hardware decoder modes can be selected', () async {
    await engine.open(clip, play: false);
    await until(() => engine.duration > Duration.zero);
    for (final mode in DecoderMode.values) {
      await engine.setDecoder(mode);
    }
    await engine.setDecoder(DecoderMode.software);
    await engine.open(clip, play: true);
    await until(() => engine.position > const Duration(milliseconds: 200));
    final active = await engine.activeDecoder();
    expect(active == null || active == 'no', isTrue, reason: 'software mode: hwdec-current = $active');
  });

  test('a broken file reports an error', () async {
    final bad = File('${dir.path}/bad.mp4')..writeAsStringSync('this is not a video');
    final err = engine.errorStream.first.timeout(const Duration(seconds: 15));
    await engine.open(bad.path);
    expect((await err), isNotEmpty);
  });
}
