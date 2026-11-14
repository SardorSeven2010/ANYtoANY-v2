import 'dart:math';
import 'dart:typed_data';

import 'package:any_to_any/player/aspect.dart';
import 'package:any_to_any/player/controller.dart';
import 'package:any_to_any/player/engine.dart';
import 'package:any_to_any/player/play_queue.dart';
import 'package:any_to_any/services/background.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fake_engine.dart';
import 'helpers/fake_native.dart';

List<QueueItem> videos(int n) => [for (var i = 0; i < n; i++) QueueItem(title: 'film$i.mp4', path: '/m/film$i.mp4')];

Future<void> pump() => Future<void>.delayed(Duration.zero);

void main() {
  late FakeEngine engine;
  late FakeNativeBridge bridge;

  Future<PlayerController> make(List<QueueItem> items, {int start = 0, BackgroundCoordinator? bg, Random? random}) async {
    engine = FakeEngine();
    bridge = FakeNativeBridge();
    final c = PlayerController(
      engine: engine,
      queue: PlayQueue(items, start: start, random: random),
      bridge: bridge,
      background: bg,
      saver: (png, name) async => 'saqlandi:$name:${png.length}',
    );
    await c.start();
    addTearDown(() => c.dispose());
    return c;
  }

  group('autoplay: next video or song', () {
    test('opens the chosen file first, then goes on by itself when it ends', () async {
      final c = await make(videos(3), start: 1);
      expect(engine.opened.single.source, '/m/film1.mp4');
      expect(c.playing, isTrue);
      engine.finish();
      await pump();
      expect(engine.opened.last.source, '/m/film2.mp4');
      expect(c.queue.index, 2);
      expect(c.loading, isFalse);
      expect(c.playing, isTrue, reason: 'next file starts playing by itself');
    });

    test('after the last file it stops (default "play to the end")', () async {
      final c = await make(videos(2), start: 1);
      engine.finish();
      await pump();
      expect(engine.opened.length, 1, reason: 'nothing else to open');
      expect(c.ended, isTrue);
      expect(c.playing, isFalse);
      // play tugmasi boshidan qayta boshlaydi
      await c.togglePlay();
      expect(engine.log.takeLast(2), ['seek:0', 'play']);
      expect(c.ended, isFalse);
    });

    test('repeat the list: wraps from the last file to the first', () async {
      final c = await make(videos(2), start: 1);
      c.cycleRepeat();
      expect(c.queue.repeat, QueueRepeat.all);
      engine.finish();
      await pump();
      expect(engine.opened.last.source, '/m/film0.mp4');
      expect(c.queue.index, 0);
    });

    test('repeat one: the same file starts again without reopening', () async {
      final c = await make(videos(3));
      c.cycleRepeat();
      c.cycleRepeat();
      expect(c.queue.repeat, QueueRepeat.one);
      engine.finish();
      await pump();
      expect(engine.opened.length, 1);
      expect(engine.log.takeLast(2), ['seek:0', 'play']);
      expect(c.queue.index, 0);
    });

    test('shuffle: files come in the shuffled order and each plays once', () async {
      final c = await make(videos(5), random: Random(4));
      c.toggleShuffle();
      expect(c.queue.shuffle, isTrue);
      final played = <String>[engine.opened.last.source];
      for (var i = 0; i < 4; i++) {
        engine.finish();
        await pump();
        played.add(engine.opened.last.source);
      }
      expect(played.toSet().length, 5);
      engine.finish();
      await pump();
      expect(c.ended, isTrue, reason: 'shuffle without repeat stops after everything was played');
    });

    test('a lazily resolved gallery file is opened by its resolved path', () async {
      final c = await make([QueueItem(title: 'IMG_9', resolve: () async => '/storage/IMG_9.mp4')]);
      expect(engine.opened.single.source, '/storage/IMG_9.mp4');
      expect(c.error, isNull);
    });
  });

  group('double tap: left back, right forward, middle pause', () {
    test('zones are thirds of the width', () {
      expect(tapZoneFor(10, 300), TapZone.left);
      expect(tapZoneFor(99, 300), TapZone.left);
      expect(tapZoneFor(150, 300), TapZone.center);
      expect(tapZoneFor(201, 300), TapZone.right);
      expect(tapZoneFor(299, 300), TapZone.right);
      expect(tapZoneFor(5, 0), TapZone.center);
    });

    test('left = 10 s back, right = 10 s forward, middle = pause / play', () async {
      final c = await make(videos(1));
      engine.tick(const Duration(seconds: 40));
      await c.onDoubleTap(TapZone.left);
      expect(engine.seeks.last, const Duration(seconds: 30));
      await c.onDoubleTap(TapZone.right);
      await c.onDoubleTap(TapZone.right);
      expect(engine.seeks.last, const Duration(seconds: 50));
      expect(c.position.value, const Duration(seconds: 50));
      expect(c.playing, isTrue);
      await c.onDoubleTap(TapZone.center);
      expect(c.playing, isFalse);
      await c.onDoubleTap(TapZone.center);
      expect(c.playing, isTrue);
    });

    test('never seeks before the start or past the end', () async {
      final c = await make(videos(1));
      engine.tick(const Duration(seconds: 4));
      await c.onDoubleTap(TapZone.left);
      expect(engine.seeks.last, Duration.zero);
      engine.tick(const Duration(seconds: 95));
      await c.onDoubleTap(TapZone.right);
      expect(engine.seeks.last, const Duration(seconds: 100));
    });
  });

  group('speed 0.25x - 4x', () {
    test('is clamped, rounded to 0.05 and kept for the next file', () async {
      final c = await make(videos(2));
      await c.setSpeed(0.1);
      expect(c.speed, 0.25);
      await c.setSpeed(9);
      expect(c.speed, 4.0);
      await c.setSpeed(1.237);
      expect(c.speed, 1.25);
      expect(engine.rate, 1.25);
      engine.finish();
      await pump();
      expect(engine.rate, 1.25, reason: 'the chosen speed is re-applied to the next video');
      for (final s in [0.25, 0.5, 0.75, 1.0, 1.5, 2.0, 3.0, 4.0]) {
        await c.setSpeed(s);
        expect(engine.rate, s);
      }
    });
  });

  group('decoder', () {
    test('switching reopens at the same position and keeps playing', () async {
      final c = await make(videos(1));
      engine.tick(const Duration(seconds: 42));
      await c.setDecoder(DecoderMode.software);
      expect(engine.decoder, DecoderMode.software);
      expect(engine.opened.last.start, const Duration(seconds: 42));
      expect(engine.opened.last.play, isTrue);
      expect(c.decoder, DecoderMode.software);
      // pauza holatida pauzada qoladi
      await c.togglePlay();
      engine.tick(const Duration(seconds: 50));
      await c.setDecoder(DecoderMode.hardware);
      expect(engine.opened.last.start, const Duration(seconds: 50));
      expect(engine.opened.last.play, isFalse);
    });

    test('choosing the current decoder does nothing', () async {
      final c = await make(videos(1));
      await c.setDecoder(DecoderMode.auto);
      expect(engine.opened.length, 1);
    });

    test('mpv values per mode', () {
      expect(hwdecValue(DecoderMode.software), 'no');
      expect(hwdecValue(DecoderMode.auto), 'auto-safe');
      expect(hwdecValue(DecoderMode.hardware), isNotEmpty);
      expect(DecoderMode.values.map((m) => m.label).toSet().length, DecoderMode.values.length);
    });
  });

  test('aspect modes include 16:9 and 19.5:9', () async {
    final c = await make(videos(1));
    final labels = AspectMode.values.map((a) => a.label).toList();
    expect(labels, containsAll(['16:9', '19.5:9', '4:3', '21:9', '1:1']));
    expect(AspectMode.r19_5x9.ratio, closeTo(19.5 / 9, 1e-9));
    expect(AspectMode.original.ratio, isNull);
    c.setAspect(AspectMode.r16x9);
    expect(c.aspect, AspectMode.r16x9);
  });

  group('previous / next', () {
    test('previous after 3 s restarts the file, early on it goes to the previous one', () async {
      final c = await make(videos(3), start: 1);
      engine.tick(const Duration(seconds: 20));
      await c.previous();
      expect(c.queue.index, 1);
      expect(engine.seeks.last, Duration.zero);
      engine.tick(const Duration(seconds: 1));
      await c.previous();
      expect(c.queue.index, 0);
      expect(engine.opened.last.source, '/m/film0.mp4');
      await c.previous();
      expect(c.queue.index, 0, reason: 'first file: just restarts');
    });

    test('rapid Next presses only open the last requested file', () async {
      final c = await make(videos(5));
      final a = c.next();
      final b = c.next();
      final d = c.next();
      await Future.wait([a, b, d]);
      expect(c.queue.index, 3);
      expect(engine.opened.last.source, '/m/film3.mp4');
      expect(c.loading, isFalse);
    });

    test('jumpTo from the queue list opens that file', () async {
      final c = await make(videos(4));
      await c.jumpTo(2);
      expect(engine.opened.last.source, '/m/film2.mp4');
      expect(c.queue.index, 2);
    });
  });

  group('screenshot', () {
    test('saves the current frame under the file name', () async {
      final c = await make(videos(1));
      expect(await c.screenshot(), 'saqlandi:film0:4');
    });

    test('nothing to save when the engine has no frame', () async {
      final c = await make(videos(1));
      engine.screenshotBytes = null;
      expect(await c.screenshot(), isNull);
      engine.screenshotBytes = Uint8List(0);
      expect(await c.screenshot(), isNull);
    });
  });

  group('background play and notification', () {
    test('media notification follows play state, track and ends with the player', () async {
      final bgBridge = FakeNativeBridge();
      final c = await make(videos(3), start: 1, bg: BackgroundCoordinator(bgBridge));
      await pump();
      expect(bgBridge.foregrounds.last['kind'], 'media');
      expect(bgBridge.foregrounds.last['title'], 'film1.mp4');
      expect(bgBridge.foregrounds.last['text'], '2 / 3');
      expect(bgBridge.foregrounds.last['playing'], true);
      await c.togglePlay();
      await pump();
      expect(bgBridge.foregrounds.last['playing'], false);
      engine.finish();
      await pump();
      expect(bgBridge.foregrounds.last['title'], 'film2.mp4', reason: 'next track shown after autoplay');
      c.dispose();
      await pump();
      expect(bgBridge.calls.last, 'stopForeground');
    });

    test('notification buttons control the player', () async {
      final c = await make(videos(3), start: 1);
      bridge.emit('mediaAction', 'playpause');
      await pump();
      expect(c.playing, isFalse);
      bridge.emit('mediaAction', 'playpause');
      await pump();
      expect(c.playing, isTrue);
      bridge.emit('mediaAction', 'next');
      await pump();
      await pump();
      expect(c.queue.index, 2);
      engine.tick(const Duration(seconds: 1));
      bridge.emit('mediaAction', 'previous');
      await pump();
      await pump();
      expect(c.queue.index, 1);
    });
  });

  group('picture in picture', () {
    test('armed only while a video plays; sized to the video; closes with the player', () async {
      final c = await make(videos(1));
      expect(bridge.pipArmed, isTrue);
      engine.setSize(1920, 1080);
      expect(await c.enterPip(), isTrue);
      expect(bridge.pipEntered, 1);
      await c.togglePlay();
      expect(bridge.pipArmed, isFalse, reason: 'paused: Home should not shrink it');
      bridge.emit('pipChanged', true);
      await pump();
      expect(c.inPip, isTrue);
      bridge.emit('pipChanged', false);
      await pump();
      expect(c.inPip, isFalse);
    });

    test('audio files never go to PiP', () async {
      final c = await make([const QueueItem(title: 'qoshiq.mp3', path: '/m/qoshiq.mp3')]);
      expect(c.isAudio, isTrue);
      expect(bridge.pipArmed, isFalse);
      expect(await c.enterPip(), isFalse);
    });
  });

  group('errors', () {
    test('a missing file and an engine failure are reported, not thrown', () async {
      final c = await make([const QueueItem(title: 'yoq.mp4')]);
      expect(c.error, 'Fayl topilmadi');
      expect(c.loading, isFalse);

      final failing = FakeEngine()..openError = Exception('boom');
      final c2 = PlayerController(engine: failing, queue: PlayQueue(videos(1)), bridge: FakeNativeBridge());
      await c2.start();
      expect(c2.error, contains("ijro etib bo'lmadi"));
      c2.dispose();
    });

    test('an error while playing is shown', () async {
      final c = await make(videos(1));
      engine.failWith('decoder failed');
      expect(c.error, isNotNull);
    });
  });

  test('dispose releases the engine and the notification', () async {
    final c = await make(videos(1));
    c.dispose();
    await pump();
    expect(engine.disposed, isTrue);
  });
}

extension on List<String> {
  List<String> takeLast(int n) => sublist(length - n);
}
