import 'package:any_to_any/app_theme.dart';
import 'package:any_to_any/player/controller.dart';
import 'package:any_to_any/player/engine.dart';
import 'package:any_to_any/player/play_queue.dart';
import 'package:any_to_any/screens/player_screen.dart';
import 'package:any_to_any/screens/player_sheets.dart';
import 'package:any_to_any/services/audio_focus.dart';
import 'package:any_to_any/services/background.dart';
import 'package:any_to_any/services/device_controls.dart';
import 'package:any_to_any/services/native_bridge.dart';
import 'package:any_to_any/services/screenshots.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fake_device.dart';
import 'helpers/fake_engine.dart';
import 'helpers/fake_native.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeEngine engine;
  late FakeNativeBridge bridge;
  final orientationCalls = <List<Object?>>[];
  final systemUiModes = <Object?>[];

  List<QueueItem> videos(int n) => [for (var i = 0; i < n; i++) QueueItem(title: 'film$i.mp4', path: '/m/film$i.mp4')];

  late FakeDeviceControls device;
  late FakeAudioFocus focus;

  setUp(() {
    device = FakeDeviceControls();
    focus = FakeAudioFocus();
    setDeviceControls(device);
    setAudioFocus(focus);
    engine = FakeEngine();
    bridge = FakeNativeBridge();
    playerEngineFactory = () => engine;
    setNativeBridge(bridge);
    setBackgroundService(BackgroundCoordinator(bridge));
    screenshotSaver = (png, name) async => 'Galereya (test)';
    orientationCalls.clear();
    systemUiModes.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemChrome.setPreferredOrientations') orientationCalls.add(call.arguments as List<Object?>);
      if (call.method == 'SystemChrome.setEnabledSystemUIMode') systemUiModes.add(call.arguments);
      return null;
    });
  });

  tearDown(() {
    setDeviceControls(null);
    setAudioFocus(null);
    playerEngineFactory = () => MediaKitEngine();
    screenshotSaver = saveScreenshotToDevice;
    setNativeBridge(null);
    setBackgroundService(null);
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> open(WidgetTester tester, {List<QueueItem>? items, int start = 0, Size size = const Size(2400, 1080)}) async {
    // keng (gorizontal) ekran: 800x360 mantiqiy piksel
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(appThemes.first),
      home: PlayerScreen.queue(items: items ?? videos(3), startIndex: start),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> doubleTapAt(WidgetTester tester, Offset p) async {
    await tester.tapAt(p);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(p);
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// Ekranning [fraction] eni, balandligining 30% da (o'rtadagi tugmalarga tegmaydi)
  Offset zoneCenter(WidgetTester tester, double fraction) {
    final box = tester.getRect(find.byKey(const Key('gestureLayer')));
    return Offset(box.left + box.width * fraction, box.top + box.height * 0.3);
  }

  testWidgets('starts the chosen file and shows title, position in the queue and the video', (tester) async {
    await open(tester, start: 1);
    expect(engine.opened.single.source, '/m/film1.mp4');
    expect(find.text('film1.mp4'), findsOneWidget);
    expect(find.text('2 / 3'), findsOneWidget);
    expect(find.byKey(const Key('fakeVideo')), findsOneWidget);
    expect(systemUiModes, contains('SystemUiMode.immersiveSticky'));
    await tester.pumpWidget(const SizedBox());
  });

  group('double tap gestures', () {
    testWidgets('left third: 10 seconds back', (tester) async {
      await open(tester);
      engine.tick(const Duration(seconds: 60));
      await doubleTapAt(tester, zoneCenter(tester, 0.15));
      expect(engine.seeks.last, const Duration(seconds: 50));
      expect(find.byKey(const Key('feedback_left')), findsOneWidget);
      expect(find.text('10 s'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('right third: 10 seconds forward, repeated taps add up', (tester) async {
      await open(tester);
      engine.tick(const Duration(seconds: 10));
      await doubleTapAt(tester, zoneCenter(tester, 0.85));
      expect(engine.seeks.last, const Duration(seconds: 20));
      await doubleTapAt(tester, zoneCenter(tester, 0.85));
      expect(engine.seeks.last, const Duration(seconds: 30));
      expect(find.text('20 s'), findsOneWidget, reason: 'the indicator adds up: 10 + 10');
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('middle: pause, and again: play', (tester) async {
      await open(tester);
      expect(engine.playing, isTrue);
      await doubleTapAt(tester, zoneCenter(tester, 0.5));
      expect(engine.playing, isFalse);
      expect(find.byKey(const Key('feedback_center')), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await doubleTapAt(tester, zoneCenter(tester, 0.5));
      expect(engine.playing, isTrue);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a single tap only shows / hides the controls (no seeking)', (tester) async {
      await open(tester);
      await tester.tapAt(zoneCenter(tester, 0.15));
      await tester.pump(const Duration(milliseconds: 400));
      expect(engine.seeks, isEmpty);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('transport buttons: play/pause, next, previous', (tester) async {
    await open(tester, start: 1);
    await tester.tap(find.byKey(const Key('playPauseButton')));
    await tester.pump();
    expect(engine.playing, isFalse);
    await tester.tap(find.byKey(const Key('nextButton')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(engine.opened.last.source, '/m/film2.mp4');
    expect(find.text('3 / 3'), findsOneWidget);
    engine.tick(const Duration(seconds: 1));
    await tester.tap(find.byKey(const Key('prevButton')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(engine.opened.last.source, '/m/film1.mp4');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('next file starts by itself when the video ends', (tester) async {
    await open(tester);
    engine.finish();
    await tester.pump(const Duration(milliseconds: 50));
    expect(engine.opened.last.source, '/m/film1.mp4');
    expect(find.text('2 / 3'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  group('queue controls', () {
    testWidgets('repeat button cycles stop -> list -> one and tells which', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('repeatButton')));
      await tester.pump();
      expect(find.text("Ro'yxatni takrorlash"), findsWidgets);
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.byKey(const Key('repeatButton')));
      await tester.pump();
      expect(find.text('Bittasini takrorlash'), findsWidgets);
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.byKey(const Key('repeatButton')));
      await tester.pump();
      expect(find.text("Oxirigacha, so'ng to'xtash"), findsWidgets);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('shuffle button toggles', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('shuffleButton')));
      await tester.pump();
      expect(find.text('Aralashtirish yoqildi'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.byKey(const Key('shuffleButton')));
      await tester.pump();
      expect(find.text("Aralashtirish o'chirildi"), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('queue sheet: all three modes, shuffle switch and jump to a file', (tester) async {
      await open(tester, items: videos(4));
      await tester.tap(find.byKey(const Key('queueButton')));
      await tester.pumpAndSettle();
      expect(find.text('Navbat (4 ta)'), findsOneWidget);
      final segments = find.byKey(const Key('repeatSegments'));
      for (final t in ["To'xtash", "Ro'yxat", 'Bitta']) {
        expect(find.descendant(of: segments, matching: find.text(t)), findsOneWidget, reason: t);
      }
      await tester.tap(find.descendant(of: segments, matching: find.text("Ro'yxat")));
      await tester.pumpAndSettle();
      expect(find.text("Ro'yxatni takrorlash"), findsWidgets);
      await tester.tap(find.byKey(const Key('shuffleSwitch')));
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(find.byKey(const Key('shuffleSwitch'))).value, isTrue);
      await tester.tap(find.byKey(const Key('shuffleSwitch')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('queue_2')),
        80,
        scrollable: find.descendant(of: find.byType(QueueSheet), matching: find.byType(Scrollable)).first,
      );
      await tester.ensureVisible(find.byKey(const Key('queue_2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('queue_2')));
      await tester.pumpAndSettle();
      expect(engine.opened.last.source, '/m/film2.mp4');
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('speed 0.25x - 4x', () {
    testWidgets('presets and the slider', (tester) async {
      await open(tester);
      expect(find.text('1x'), findsOneWidget);
      await tester.tap(find.byKey(const Key('speedButton')));
      await tester.pumpAndSettle();
      expect(find.text('Video tezligi: 1x'), findsOneWidget);
      for (final p in [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0, 4.0]) {
        expect(find.byKey(Key('speed_$p')), findsOneWidget, reason: '$p');
      }
      await tester.tap(find.byKey(const Key('speed_4.0')));
      await tester.pumpAndSettle();
      expect(engine.rate, 4.0);
      expect(find.text('Video tezligi: 4x'), findsOneWidget);
      await tester.tap(find.byKey(const Key('speed_0.25')));
      await tester.pumpAndSettle();
      expect(engine.rate, 0.25);
      // surgich ham ishlaydi
      final slider = tester.getCenter(find.byKey(const Key('speedSlider')));
      await tester.tapAt(slider);
      await tester.pumpAndSettle();
      expect(engine.rate, inInclusiveRange(0.25, 4.0));
      expect(engine.rate, isNot(0.25));
      // yopilgandan keyin tugmada ko'rinadi
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('decoder sheet: hardware / software, reopens at the same position', (tester) async {
    await open(tester);
    engine.tick(const Duration(seconds: 33));
    await tester.tap(find.byKey(const Key('decoderButton')));
    await tester.pumpAndSettle();
    expect(find.text('Video dekoderi'), findsOneWidget);
    for (final m in DecoderMode.values) {
      expect(find.byKey(Key('decoder_${m.name}')), findsOneWidget);
    }
    expect(find.textContaining('dasturiy (protsessor)'), findsOneWidget, reason: 'shows what is in use now');
    await tester.ensureVisible(find.byKey(const Key('decoder_software')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('decoder_software')));
    await tester.pumpAndSettle();
    expect(engine.decoder, DecoderMode.software);
    expect(engine.opened.last.start, const Duration(seconds: 33));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('aspect sheet: 16:9, 19.5:9 and others change how the video is laid out', (tester) async {
    await open(tester);
    expect(engine.lastFit, BoxFit.contain);
    await tester.tap(find.byKey(const Key('aspectButton')));
    await tester.pumpAndSettle();
    for (final l in ["Asl o'lcham", "To'ldirish (cho'zish)", "Kesib to'ldirish", '16:9', '19.5:9', '18:9', '21:9', '4:3', '1:1']) {
      expect(find.text(l), findsOneWidget, reason: l);
    }
    await tester.tap(find.byKey(const Key('aspect_r19_5x9')));
    await tester.pumpAndSettle();
    final box = tester.widget<AspectRatio>(find.descendant(of: find.byType(PlayerScreen), matching: find.byType(AspectRatio)));
    expect(box.aspectRatio, closeTo(19.5 / 9, 1e-9));
    expect(engine.lastFit, BoxFit.fill);
    await tester.tap(find.byKey(const Key('aspect_cover')));
    await tester.pumpAndSettle();
    expect(engine.lastFit, BoxFit.cover);
    expect(find.descendant(of: find.byType(PlayerScreen), matching: find.byType(AspectRatio)), findsNothing);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('Kesish'), findsOneWidget, reason: 'the button shows the current mode');
    await tester.pumpWidget(const SizedBox());
  });

  group('screenshot', () {
    testWidgets('saves and tells where', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('screenshotButton')));
      await tester.pump(const Duration(milliseconds: 50));
      // saver sinovda bu yerda real saver: fayl yozadi yoki xato beradi. Xabar baribir chiqadi.
      expect(find.byKey(const Key('playerToast')), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('no frame -> a clear message', (tester) async {
      await open(tester);
      engine.screenshotBytes = null;
      await tester.tap(find.byKey(const Key('screenshotButton')));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text("Skrinshot olib bo'lmadi"), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('screen rotation', () {
    testWidgets('mobile: button rotates to landscape and back', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await open(tester, size: const Size(1080, 2400)); // tik ekran
      await tester.tap(find.byKey(const Key('rotateButton')));
      await tester.pump();
      expect(orientationCalls.last, containsAll(['DeviceOrientation.landscapeLeft', 'DeviceOrientation.landscapeRight']));
      await tester.pumpWidget(const SizedBox());
      // ekran yopilganda hamma yo'nalish qaytariladi
      expect(orientationCalls.last.length, 4);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('mobile in landscape: button goes back to portrait', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await open(tester); // gorizontal ekran
      await tester.tap(find.byKey(const Key('rotateButton')));
      await tester.pump();
      expect(orientationCalls.last, ['DeviceOrientation.portraitUp']);
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('desktop has no rotate button', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      await open(tester);
      expect(find.byKey(const Key('rotateButton')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('picture in picture', () {
    testWidgets('button asks Android for a floating window', (tester) async {
      await open(tester);
      engine.setSize(1280, 720);
      await tester.tap(find.byKey(const Key('pipButton')));
      await tester.pump();
      expect(bridge.pipEntered, 1);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('no button where PiP is unavailable', (tester) async {
      setNativeBridge(FakeNativeBridge(supported: false));
      await open(tester);
      expect(find.byKey(const Key('pipButton')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('inside the floating window only the video is shown', (tester) async {
      await open(tester);
      expect(find.byKey(const Key('playPauseButton')), findsOneWidget);
      bridge.emit('pipChanged', true);
      await tester.pump();
      expect(find.byKey(const Key('playPauseButton')), findsNothing);
      expect(find.byKey(const Key('fakeVideo')), findsOneWidget);
      bridge.emit('pipChanged', false);
      await tester.pump();
      expect(find.byKey(const Key('playPauseButton')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('audio file: cover art, no video-only buttons, notification controls', (tester) async {
    await open(tester, items: [
      const QueueItem(title: 'qoshiq1.mp3', path: '/m/qoshiq1.mp3'),
      const QueueItem(title: 'qoshiq2.mp3', path: '/m/qoshiq2.mp3'),
    ]);
    expect(find.byIcon(Icons.music_note_rounded), findsOneWidget);
    expect(find.byKey(const Key('fakeVideo')), findsNothing);
    expect(find.byKey(const Key('aspectButton')), findsNothing);
    expect(find.byKey(const Key('screenshotButton')), findsNothing);
    expect(find.byKey(const Key('pipButton')), findsNothing);
    expect(find.byKey(const Key('speedButton')), findsOneWidget);
    expect(find.byKey(const Key('queueButton')), findsOneWidget);
    await tester.pump();
    expect(bridge.foregrounds.last['kind'], 'media', reason: 'keeps playing in the background');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('seek bar jumps to the dragged position', (tester) async {
    await open(tester);
    engine.tick(const Duration(seconds: 5));
    await tester.pump();
    final bar = find.byKey(const Key('seekBar'));
    final rect = tester.getRect(bar);
    await tester.tapAt(Offset(rect.left + rect.width * 0.5, rect.center.dy));
    await tester.pump();
    expect(engine.seeks, isNotEmpty);
    expect(engine.seeks.last.inSeconds, inInclusiveRange(45, 55));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('error: message with retry', (tester) async {
    engine.openError = Exception('boom');
    await open(tester);
    expect(find.textContaining("ijro etib bo'lmadi"), findsOneWidget);
    expect(find.text('Qayta urinish'), findsOneWidget);
    expect(find.text('Keyingisi'), findsOneWidget);
    engine.openError = null;
    await tester.tap(find.text('Qayta urinish'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(engine.opened, isNotEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('leaving the player releases the engine, notification and restores the screen', (tester) async {
    await open(tester);
    await tester.pumpWidget(const SizedBox());
    expect(engine.disposed, isTrue);
    expect(systemUiModes.last, 'SystemUiMode.edgeToEdge');
    expect(orientationCalls.last.length, 4);
    expect(bridge.calls, contains('stopForeground'));
    expect(bridge.pipArmed, isFalse);
  });

  group('swipe gestures', () {
    Future<void> drag(WidgetTester tester, Offset from, Offset by) async {
      final gesture = await tester.startGesture(from);
      await gesture.moveBy(Offset(by.dx.sign * 25, by.dy.sign * 25)); // ishqalanish chegarasidan o'tish
      await gesture.moveBy(by);
      await tester.pump();
    }

    Offset at(WidgetTester tester, double fx, double fy) {
      final r = tester.getRect(find.byKey(const Key('gestureLayer')));
      return Offset(r.left + r.width * fx, r.top + r.height * fy);
    }

    testWidgets('left to right: goes forward by the swiped distance; shows where it will land', (tester) async {
      await open(tester);
      engine.tick(const Duration(seconds: 20));
      final gesture = await tester.startGesture(at(tester, 0.2, 0.4));
      await gesture.moveBy(const Offset(25, 0));
      await gesture.moveBy(const Offset(200, 0));
      await tester.pump();
      expect(find.byKey(const Key('swipeIndicator_seek')), findsOneWidget);
      expect(engine.seeks, isEmpty, reason: 'it jumps when the finger is lifted');
      await gesture.up();
      await tester.pump();
      // 800 px eni = 60 s (video 100 s: choragi 25 s < 1 daqiqa); 200 px = 15 s
      expect(engine.seeks.last.inSeconds, inInclusiveRange(34, 36));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const Key('swipeIndicator_seek')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('right to left: goes back', (tester) async {
      await open(tester);
      engine.tick(const Duration(seconds: 60));
      final gesture = await tester.startGesture(at(tester, 0.8, 0.4));
      await gesture.moveBy(const Offset(-25, 0));
      await gesture.moveBy(const Offset(-200, 0));
      await gesture.up();
      await tester.pump();
      expect(engine.seeks.last.inSeconds, inInclusiveRange(44, 46));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('left half, upwards: brighter; downwards: darker', (tester) async {
      await open(tester);
      await tester.pump(const Duration(milliseconds: 50));
      final before = device.bright;
      await drag(tester, at(tester, 0.2, 0.55), const Offset(0, -120));
      expect(find.byKey(const Key('swipeIndicator_brightness')), findsOneWidget);
      expect(device.brightnessSets, isNotEmpty);
      expect(device.bright, greaterThan(before));
      expect(device.volumeSets, isEmpty, reason: 'the left half never touches the volume');
      final up = device.bright;
      await tester.pump(const Duration(seconds: 1));
      await drag(tester, at(tester, 0.2, 0.25), const Offset(0, 100));
      expect(device.bright, lessThan(up));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('right half, upwards: louder; downwards: quieter', (tester) async {
      await open(tester);
      await tester.pump(const Duration(milliseconds: 50));
      final before = device.vol!;
      await drag(tester, at(tester, 0.8, 0.55), const Offset(0, -120));
      expect(find.byKey(const Key('swipeIndicator_volume')), findsOneWidget);
      expect(device.vol!, greaterThan(before));
      expect(device.brightnessSets, isEmpty, reason: 'the right half never touches the brightness');
      final up = device.vol!;
      await tester.pump(const Duration(seconds: 1));
      await drag(tester, at(tester, 0.8, 0.25), const Offset(0, 100));
      expect(device.vol!, lessThan(up));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the brightness is given back when the player is closed', (tester) async {
      await open(tester);
      await tester.pumpWidget(const SizedBox());
      expect(device.brightnessResets, 1);
    });

    testWidgets('double tap still works next to the swipes', (tester) async {
      await open(tester);
      engine.tick(const Duration(seconds: 60));
      await doubleTapAt(tester, zoneCenter(tester, 0.85));
      expect(engine.seeks.last, const Duration(seconds: 70));
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('one video', () {
    testWidgets('a repeat button is shown (and no shuffle); it turns repeating on and off', (tester) async {
      await open(tester, items: videos(1));
      expect(find.text('Takrorlash'), findsOneWidget);
      expect(find.byKey(const Key('shuffleButton')), findsNothing);
      await tester.tap(find.byKey(const Key('repeatButton')));
      await tester.pump();
      expect(find.text('Video takrorlanadi'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      engine.finish();
      await tester.pump(const Duration(milliseconds: 50));
      expect(engine.log.takeLast(2), ['seek:0', 'play'], reason: 'plays again by itself');
      await tester.tap(find.byKey(const Key('repeatButton')));
      await tester.pump();
      expect(find.text("Takrorlash o'chirildi"), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('when it ends, a big "Qayta ijro" (replay) button appears', (tester) async {
      await open(tester, items: videos(1));
      engine.finish();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const Key('replayLabel')), findsOneWidget);
      expect(find.byIcon(Icons.replay_rounded), findsOneWidget);
      await tester.tap(find.byKey(const Key('playPauseButton')));
      await tester.pump(const Duration(milliseconds: 50));
      expect(engine.log.takeLast(2), ['seek:0', 'play']);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('background sound', () {
    testWidgets('the "Fon" sheet: background sound and the floating window switches', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('backgroundButton')));
      await tester.pumpAndSettle();
      expect(find.text('Fon va qalqib chiquvchi oyna'), findsOneWidget);
      expect(find.text('Fonda ovoz'), findsOneWidget);
      expect(find.byKey(const Key('autoPipSwitch')), findsOneWidget);
      await tester.tap(find.byKey(const Key('backgroundAudioSwitch')));
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(find.byKey(const Key('backgroundAudioSwitch'))).value, isTrue);
      await tester.ensureVisible(find.byKey(const Key('pipNowButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pipNowButton')));
      await tester.pumpAndSettle();
      expect(bridge.pipEntered, 1);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('leaving the app: the video pauses unless background sound is on', (tester) async {
      await open(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(engine.playing, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(engine.playing, isTrue);

      await tester.tap(find.byKey(const Key('backgroundButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('backgroundAudioSwitch')));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(engine.playing, isTrue, reason: 'sound goes on in the background');
      expect(bridge.foregrounds.last['kind'], 'media');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('no picture: the decoder is switched and a message is shown', (tester) async {
      blackScreenTimeout = const Duration(milliseconds: 150);
      addTearDown(() => blackScreenTimeout = const Duration(seconds: 4));
      await open(tester);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('dekoder avtomatik'), findsOneWidget);
      expect(engine.decoder, DecoderMode.software);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('desktop keyboard: space, arrows, N and P', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await open(tester);
    engine.tick(const Duration(seconds: 50));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(engine.seeks.last, const Duration(seconds: 60));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    expect(engine.seeks.last, const Duration(seconds: 50));
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(engine.playing, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.pump(const Duration(milliseconds: 50));
    expect(engine.opened.last.source, '/m/film1.mp4');
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });
}

extension on List<String> {
  List<String> takeLast(int n) => sublist(length - n);
}
