import 'dart:io';

import 'package:any_to_any/app_theme.dart';
import 'package:any_to_any/downloader/detected.dart';
import 'package:any_to_any/downloader/media_keepalive_js.dart';
import 'package:any_to_any/downloader/segmented.dart';
import 'package:any_to_any/screens/browser_screen.dart';
import 'package:any_to_any/services/background.dart';
import 'package:any_to_any/services/native_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fake_browser.dart';
import 'helpers/fake_native.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeBrowser browser;
  late FakeNativeBridge bridge;

  setUp(() {
    browser = FakeBrowser();
    bridge = FakeNativeBridge();
    setNativeBridge(bridge);
    setBackgroundService(BackgroundCoordinator(bridge));
  });

  tearDown(() {
    setNativeBridge(null);
    setBackgroundService(null);
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(appThemes.first),
      home: BrowserScreen(
        initial: Uri.parse('https://youtube.test/watch?v=1'),
        backend: browser,
        detector: MediaDetector(
          probe: (u, h) async => ProbeResult(url: u, length: 5 << 20, acceptsRanges: true),
          fetch: (u, h) async => ('', u),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('a video starts playing in the page: the player appears in the notification bar and the service starts', (tester) async {
    await open(tester);
    expect(bridge.foregrounds, isEmpty, reason: 'nothing plays yet');
    browser.media(playing: true, title: 'Pleylist: 1-video');
    await tester.pump();
    expect(bridge.foregrounds.last['kind'], 'media');
    expect(bridge.foregrounds.last['title'], 'Pleylist: 1-video');
    expect(bridge.foregrounds.last['text'], 'Mini-brauzer');
    expect(bridge.foregrounds.last['playing'], true);
    // pauza
    browser.media(playing: false, title: 'Pleylist: 1-video');
    await tester.pump();
    expect(bridge.foregrounds.last['playing'], false);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the next playlist video keeps the notification going (title changes, never an interruption)', (tester) async {
    await open(tester);
    browser.media(playing: true, title: 'Video 1');
    await tester.pump();
    browser.media(playing: false, title: 'Video 1'); // o'tish payti qisqa pauza
    browser.media(playing: true, title: 'Video 2');
    await tester.pump();
    expect(bridge.foregrounds.last['title'], 'Video 2');
    expect(bridge.foregrounds.last['playing'], true);
    expect(bridge.calls, isNot(contains('stopForeground')), reason: 'the service is never stopped between videos');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('notification buttons control the page video', (tester) async {
    await open(tester);
    browser.media(playing: true, title: 'Video');
    await tester.pump();
    for (final action in ['play', 'pause', 'playpause', 'next', 'previous', 'stop']) {
      bridge.emit('mediaAction', action);
    }
    await tester.pump();
    expect(browser.commands, ['play', 'pause', 'toggle', 'next', 'previous', 'pause']);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('leaving the app tells the page it is in the background; coming back clears it', (tester) async {
    await open(tester);
    for (final s in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
    await tester.pump();
    expect(browser.background, isTrue);
    for (final s in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
    await tester.pump();
    expect(browser.background, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('another page or closing the browser removes the notification', (tester) async {
    await open(tester);
    browser.media(playing: true, title: 'Video');
    await tester.pump();
    browser.navigate('https://youtube.test/other');
    await tester.pump(const Duration(milliseconds: 100));
    expect(bridge.calls.last, 'stopForeground');

    browser.media(playing: true, title: 'Boshqa video');
    await tester.pump();
    expect(bridge.foregrounds.last['title'], 'Boshqa video');
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(bridge.calls.last, 'stopForeground');
  });

  testWidgets('a page without any media shows nothing', (tester) async {
    await open(tester);
    browser.media(playing: false, hasMedia: false);
    await tester.pump();
    expect(bridge.foregrounds, isEmpty);
    expect(bridge.calls, isNot(contains('stopForeground')));
    await tester.pumpWidget(const SizedBox());
  });

  test('page script (real DOM via jsdom): visibility fake, state reports, controls, auto-resume in the background', () async {
    final node = await Process.run('node', ['--version']).catchError((Object _) => ProcessResult(0, 127, '', ''));
    if (node.exitCode != 0) return markTestSkipped("node o'rnatilmagan");
    final dir = await Directory.systemTemp.createTemp('a2a_keepalive');
    addTearDown(() => dir.delete(recursive: true));
    final script = File('${dir.path}/keepalive.js')..writeAsStringSync(mediaKeepAliveScript);
    final r = await Process.run('node', ['tools/media_keepalive_check.js', script.path]);
    if (r.exitCode == 2) return markTestSkipped("jsdom o'rnatilmagan (NODE_PATH)");
    expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
    expect(r.stdout.toString(), contains('ALL OK'));
  }, timeout: const Timeout(Duration(seconds: 90)));
}
