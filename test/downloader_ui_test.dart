import 'dart:async';
import 'dart:io';

import 'package:any_to_any/app_theme.dart';
import 'package:any_to_any/config.dart';
import 'package:any_to_any/downloader/common.dart';
import 'package:any_to_any/downloader/detected.dart';
import 'package:any_to_any/downloader/hls.dart';
import 'package:any_to_any/downloader/job_runner.dart';
import 'package:any_to_any/downloader/manager.dart';
import 'package:any_to_any/downloader/segmented.dart';
import 'package:any_to_any/screens/browser_screen.dart';
import 'package:any_to_any/screens/download_sheets.dart';
import 'package:any_to_any/screens/downloader_tab.dart';
import 'package:any_to_any/screens/subscription_screen.dart';
import 'package:any_to_any/services/background.dart';
import 'package:any_to_any/services/native_bridge.dart';
import 'package:any_to_any/services/profile_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fake_browser.dart';
import 'helpers/fake_native.dart';

class MemoryLog implements DownloadLog {
  final List<DateTime> starts = [];
  @override
  Future<List<DateTime>> recent() async => List.of(starts);
  @override
  Future<void> record({required String host, required String kind}) async => starts.add(DateTime.now());
}

class HoldRunner {
  final List<Completer<JobResult>> pending = [];
  final List<DownloadRequest> started = [];
  JobCallbacks? cb;
  Future<JobResult> call(DownloadRequest r, Directory out, Set<String> used, JobCallbacks callbacks) {
    started.add(r);
    cb = callbacks;
    final c = Completer<JobResult>();
    pending.add(c);
    callbacks.cancel.onCancel(() {
      if (!c.isCompleted) c.completeError(const DownloadCancelled());
    });
    return c.future;
  }
}

DetectedMedia video(String url, {String title = 'Kino', DetectedKind kind = DetectedKind.video, int? bytes = 25 * 1024 * 1024}) =>
    DetectedMedia(url: Uri.parse(url), kind: kind, pageTitle: title, page: Uri.parse('https://site.test/watch'))
      ..bytes = bytes
      ..checked = true;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HoldRunner runner;
  late MemoryLog log;
  late FakeNativeBridge bridge;
  late DownloadManager manager;
  late Directory dir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    runner = HoldRunner();
    log = MemoryLog();
    bridge = FakeNativeBridge();
    setNativeBridge(bridge);
    setBackgroundService(BackgroundCoordinator(bridge));
    dir = await Directory.systemTemp.createTemp('a2a_ui_dl');
    manager = DownloadManager(runner: runner.call, log: log, bridge: bridge, background: BackgroundCoordinator(bridge), outDir: () async => dir);
    profile
      ..isPro = false
      ..proUntil = null
      ..trialStartedAt = null;
  });

  tearDown(() async {
    manager.dispose();
    setNativeBridge(null);
    setBackgroundService(null);
    profile
      ..isPro = false
      ..proUntil = null;
    await dir.delete(recursive: true);
  });

  void tall(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  Future<void> pumpApp(WidgetTester tester, Widget home) async {
    tall(tester);
    await tester.pumpWidget(MaterialApp(theme: buildAppTheme(appThemes.first), home: Scaffold(body: home)));
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  group('address bar input', () {
    test('address, host and search', () {
      expect(addressFromInput('https://a.b/c').toString(), 'https://a.b/c');
      expect(addressFromInput('example.com/page').toString(), 'https://example.com/page');
      expect(addressFromInput('kino haqida').host, 'duckduckgo.com');
      expect(addressFromInput('kino haqida').queryParameters['q'], 'kino haqida');
      expect(addressFromInput('   ').toString(), 'about:blank');
      expect(addressFromInput('localhost').host, 'duckduckgo.com', reason: 'a bare word is a search');
    });
  });

  group('download options sheet', () {
    Future<void> openSheet(WidgetTester tester, DetectedMedia media, {required bool pro}) async {
      tall(tester);
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(appThemes.first),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showDownloadSheet(context, media: media, title: 'Kino nomi', headers: {'Referer': 'https://site.test'}, manager: manager, pro: pro),
                child: const Text('ochish'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('ochish'));
      await tester.pumpAndSettle();
    }

    testWidgets('free: 6 parts, MP4 only, PRO hints, weekly counter', (tester) async {
      await openSheet(tester, video('https://cdn.test/a.mp4'), pro: false);
      expect(find.text('Videoni yuklash'), findsOneWidget);
      expect(find.text('Video • 25.0 MB'), findsOneWidget);
      expect(find.text('6 ta'), findsOneWidget);
      expect(find.byKey(const Key('segmentsSlider')), findsNothing);
      expect(find.textContaining("PRO'da 18 tagacha"), findsOneWidget);
      expect(find.textContaining('H.264 yoki H.265 tanlash faqat PRO'), findsOneWidget);
      expect(find.byKey(const Key('codec_h265')), findsNothing);
      expect(find.text('Bu hafta qoldi: 10 / 10'), findsOneWidget);
      expect(find.text('.mp4'), findsOneWidget);
      await tester.tap(find.byKey(const Key('dlStart')));
      await tester.pumpAndSettle();
      expect(runner.started.single.segments, 6);
      expect(runner.started.single.title, 'Kino nomi');
      expect(runner.started.single.headers['Referer'], 'https://site.test');
      expect(runner.started.single.codec, OutputCodec.original);
      expect(find.textContaining('Yuklash boshlandi'), findsOneWidget);
    });

    testWidgets('PRO: 6..18 parts slider and the codec choice H.264 / H.265', (tester) async {
      await openSheet(tester, video('https://cdn.test/a.mp4'), pro: true);
      expect(find.text('12 ta'), findsOneWidget, reason: 'PRO default');
      final slider = tester.widget<Slider>(find.byKey(const Key('segmentsSlider')));
      expect((slider.min, slider.max), (6.0, 18.0));
      expect(find.text('PRO: haftasiga cheklovsiz'), findsOneWidget);
      for (final k in ['codec_original', 'codec_h264', 'codec_h265']) {
        expect(find.byKey(Key(k)), findsOneWidget, reason: k);
      }
      await tester.tap(find.byKey(const Key('codec_h265')));
      await tester.pump();
      expect(find.textContaining('Qayta kodlash'), findsOneWidget);
      // surgichni oxirigacha
      final rect = tester.getRect(find.byKey(const Key('segmentsSlider')));
      await tester.tapAt(Offset(rect.right - 20, rect.center.dy));
      await tester.pump();
      expect(find.text('18 ta'), findsOneWidget);
      await tester.tap(find.byKey(const Key('dlStart')));
      await tester.pumpAndSettle();
      expect(runner.started.single.segments, 18);
      expect(runner.started.single.codec, OutputCodec.h265);
    });

    testWidgets('HLS master: pick the quality', (tester) async {
      final m = video('https://cdn.test/master.m3u8', kind: DetectedKind.hls, bytes: null)
        ..qualities = [
          HlsVariantForTest.make('https://cdn.test/hi.m3u8', 1080),
          HlsVariantForTest.make('https://cdn.test/lo.m3u8', 360),
        ];
      await openSheet(tester, m, pro: true);
      expect(find.text('1080p'), findsOneWidget);
      expect(find.text('360p'), findsOneWidget);
      await tester.tap(find.byKey(const Key('quality_1')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('dlStart')));
      await tester.pumpAndSettle();
      expect(runner.started.single.variantUrl.toString(), 'https://cdn.test/lo.m3u8');
      expect(runner.started.single.kind, MediaKind.hls);
    });

    testWidgets('free weekly limit reached: message, PRO button, nothing starts', (tester) async {
      final first = DateTime.now().subtract(const Duration(days: 5));
      for (var i = 0; i < 10; i++) {
        log.starts.add(first.add(Duration(hours: i)));
      }
      await openSheet(tester, video('https://cdn.test/a.mp4'), pro: false);
      expect(find.text('Bu hafta qoldi: 0 / 10'), findsOneWidget);
      await tester.tap(find.byKey(const Key('dlStart')));
      await tester.pumpAndSettle();
      expect(runner.started, isEmpty);
      expect(find.byKey(const Key('dlBlocked')), findsOneWidget);
      expect(find.textContaining('10 ta yuklash limiti tugadi'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('dlGetPro')));
      await tester.tap(find.byKey(const Key('dlGetPro')));
      await tester.pumpAndSettle();
      expect(find.byType(SubscriptionScreen), findsOneWidget);
    });

    testWidgets('an empty name is refused', (tester) async {
      await openSheet(tester, video('https://cdn.test/a.mp4'), pro: false);
      await tester.enterText(find.byKey(const Key('dlTitle')), '   ');
      await tester.tap(find.byKey(const Key('dlStart')));
      await tester.pump();
      expect(find.text('Fayl nomini yozing'), findsOneWidget);
      expect(runner.started, isEmpty);
    });
  });

  group('downloads tab', () {
    final detector = MediaDetector(
      probe: (u, h) async => ProbeResult(url: u, length: 5 * 1024 * 1024, acceptsRanges: true, contentType: u.path.endsWith('.html') ? 'text/html' : 'video/mp4'),
      fetch: (u, h) async => ('', u),
    );

    testWidgets('empty state, weekly counter and the browser button (phone)', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await pumpApp(tester, DownloaderTab(manager: manager, detector: detector));
      await settle(tester);
      expect(find.text('Video yuklash'), findsOneWidget);
      expect(find.byKey(const Key('noDownloads')), findsOneWidget);
      expect(find.text('Bu hafta qoldi: 10 / 10'), findsOneWidget);
      expect(find.byKey(const Key('openBrowser')), findsOneWidget);
      expect(find.textContaining('DRM'), findsWidgets);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('a direct video link opens the options sheet and starts a download with progress', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      await pumpApp(tester, DownloaderTab(manager: manager, detector: detector));
      expect(find.byKey(const Key('openBrowser')), findsNothing, reason: 'no WebView on desktop');
      await tester.enterText(find.byKey(const Key('linkField')), 'https://cdn.test/video/dars.mp4');
      await tester.tap(find.byKey(const Key('submitLink')));
      await tester.pumpAndSettle();
      expect(find.text('Videoni yuklash'), findsOneWidget);
      expect(find.byKey(const Key('dlTitle')), findsOneWidget);
      await tester.tap(find.byKey(const Key('dlStart')));
      await settle(tester);
      expect(runner.started.single.url.toString(), 'https://cdn.test/video/dars.mp4');

      final job = manager.jobs.single;
      runner.cb!.onProgress!(1024 * 1024, 4 * 1024 * 1024, 6);
      // tezlik hisobi haqiqiy vaqt bo'yicha (kamida 0.7 s oralig'ida) yangilanadi
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 800)));
      runner.cb!.onProgress!(2 * 1024 * 1024, 4 * 1024 * 1024, 6);
      await tester.pump();
      expect(find.byKey(Key('detail_${job.id}')), findsOneWidget);
      final detail = tester.widget<Text>(find.byKey(Key('detail_${job.id}'))).data!;
      expect(detail, contains('50%'));
      expect(detail, contains('6 bo\'lak'));
      expect(detail, contains('MB/s'));
      await tester.pump(const Duration(seconds: 2)); // fon xizmati taymeri

      // tugaydi
      runner.pending.single.complete(JobResult('${dir.path}/dars.mp4', 4 * 1024 * 1024, 6));
      await settle(tester);
      expect(tester.widget<Text>(find.byKey(Key('detail_${job.id}'))).data, startsWith('Tayyor'));
      expect(find.byKey(Key('play_${job.id}')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('on desktop a normal web page link explains what to do instead of opening a browser', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      await pumpApp(tester, DownloaderTab(manager: manager, detector: detector));
      await tester.enterText(find.byKey(const Key('linkField')), 'https://site.test/page.html');
      await tester.tap(find.byKey(const Key('submitLink')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('downloaderMessage')), findsOneWidget);
      expect(find.textContaining('telefon ilovasidagi brauzer'), findsOneWidget);
      await tester.tap(find.byKey(const Key('submitLink')));
      await tester.pumpAndSettle();
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('empty input asks for a link', (tester) async {
      await pumpApp(tester, DownloaderTab(manager: manager, detector: detector));
      await tester.tap(find.byKey(const Key('submitLink')));
      await tester.pump();
      expect(find.text('Avval video yoki sayt havolasini joylang'), findsOneWidget);
    });

    testWidgets('cancel, retry and remove from the list', (tester) async {
      await pumpApp(tester, DownloaderTab(manager: manager, detector: detector));
      final o = await manager.start(DownloadRequest(url: Uri.parse('https://cdn.test/x.mp4'), title: 'Birinchi'), pro: true);
      final job = o.job!;
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Birinchi'), findsOneWidget);
      await tester.tap(find.byKey(Key('cancel_${job.id}')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(job.status, JobStatus.canceled);
      expect(tester.widget<Text>(find.byKey(Key('detail_${job.id}'))).data, 'Bekor qilindi');
      await tester.tap(find.byKey(Key('retry_${job.id}')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(job.status, JobStatus.running);
      await tester.tap(find.byKey(Key('cancel_${job.id}')));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byKey(Key('remove_${job.id}')));
      await tester.pumpAndSettle();
      expect(manager.jobs, isEmpty);
      expect(find.byKey(const Key('noDownloads')), findsOneWidget);
    });

    testWidgets('finished download: remove only from the list or delete the file too', (tester) async {
      final f = File('${dir.path}/tayyor.mp4')..writeAsBytesSync([1, 2, 3]);
      await pumpApp(tester, DownloaderTab(manager: manager, detector: detector));
      final job = (await manager.start(DownloadRequest(url: Uri.parse('https://cdn.test/t.mp4'), title: 'Tayyor'), pro: true)).job!;
      await tester.pump(const Duration(milliseconds: 50));
      runner.pending.single.complete(JobResult(f.path, 3, 6));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('remove_${job.id}')));
      await tester.pumpAndSettle();
      expect(find.text("Ro'yxatdan olib tashlash"), findsOneWidget);
      await tester.tap(find.byKey(const Key('removeDelete')));
      await tester.pumpAndSettle(); // oyna yopiladi, o'chirish boshlanadi
      // haqiqiy fayl amallari (exists, delete) bir necha navbatda tugaydi
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
        await tester.pump();
      }
      expect(manager.jobs, isEmpty);
      expect(f.existsSync(), isFalse);
    });

    testWidgets('PRO users see the unlimited label', (tester) async {
      profile
        ..isPro = true
        ..proUntil = DateTime.now().add(const Duration(days: 30));
      await pumpApp(tester, DownloaderTab(manager: manager, detector: detector));
      await settle(tester);
      expect(find.text('PRO: haftasiga cheklovsiz'), findsOneWidget);
    });
  });

  group('browser screen', () {
    late FakeBrowser browser;
    late MediaDetector detector;

    Future<void> openBrowser(WidgetTester tester, {Uri? initial}) async {
      browser = FakeBrowser();
      detector = MediaDetector(
        probe: (u, h) async => ProbeResult(url: u, length: 8 * 1024 * 1024, acceptsRanges: true),
        fetch: (u, h) async => ('', u),
      );
      tall(tester);
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(appThemes.first),
        home: BrowserScreen(initial: initial, backend: browser, detector: detector, manager: manager),
      ));
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets('start page, then typing an address loads it', (tester) async {
      await openBrowser(tester);
      expect(find.text('Videoni toping va yuklang'), findsOneWidget);
      expect(find.byKey(const Key('videoFound')).evaluate().isNotEmpty, isTrue);
      await tester.enterText(find.byKey(const Key('browserAddress')), 'example.com/kino');
      await tester.tap(find.byKey(const Key('browserGo')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(browser.loaded.single.toString(), 'https://example.com/kino');
      expect(find.text('Videoni toping va yuklang'), findsNothing);
    });

    testWidgets('a video starts playing: the Download button appears with the count; the sheet lists it', (tester) async {
      await openBrowser(tester, initial: Uri.parse('https://site.test/watch'));
      final scale = find.ancestor(of: find.byKey(const Key('videoFound')), matching: find.byType(AnimatedScale));
      expect(tester.widget<AnimatedScale>(scale).scale, 0, reason: 'hidden while nothing was found');
      browser.onMessage!('{"url":"https://cdn.test/film.mp4","type":"video/mp4","title":"Zo\'r kino","page":"https://site.test/watch"}');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.widget<AnimatedScale>(scale).scale, 1);
      expect(find.text('Yuklash (1)'), findsOneWidget);
      await tester.tap(find.byKey(const Key('videoFound')));
      await tester.pumpAndSettle();
      expect(find.text('Topilgan videolar (1)'), findsOneWidget);
      expect(find.text("Zo'r kino"), findsOneWidget);
      expect(find.textContaining('8.0 MB'), findsOneWidget);
      await tester.tap(find.byKey(const Key('detected_0')));
      await tester.pumpAndSettle();
      expect(find.text('Videoni yuklash'), findsOneWidget);
      await tester.tap(find.byKey(const Key('dlStart')));
      await tester.pumpAndSettle();
      final r = runner.started.single;
      expect(r.url.toString(), 'https://cdn.test/film.mp4');
      expect(r.title, "Zo'r kino");
      expect(r.headers['Referer'], 'https://site.test/watch', reason: 'the page address is sent as Referer');
      expect(r.headers['Cookie'], 'sid=42');
      expect(r.headers['User-Agent'], 'FakeUA');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('going to another page clears the old videos', (tester) async {
      await openBrowser(tester, initial: Uri.parse('https://site.test/a'));
      browser.onMessage!('{"url":"https://cdn.test/a.mp4","type":"video/mp4","title":"A","page":"https://site.test/a"}');
      await tester.pump(const Duration(milliseconds: 300));
      expect(detector.count, 1);
      browser.navigate('https://site.test/b');
      await tester.pump(const Duration(milliseconds: 300));
      expect(detector.count, 0);
      expect(find.text('Yuklash (0)'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('DRM and blob streams are listed as protected and cannot be tapped to download', (tester) async {
      await openBrowser(tester, initial: Uri.parse('https://site.test/a'));
      browser.onMessage!('{"url":"blob:https://site.test/xyz","type":"","title":"Himoyali","page":"https://site.test/a"}');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const Key('videoFound')));
      await tester.pumpAndSettle();
      expect(find.text('Himoyalangan oqim'), findsWidgets);
      expect(find.textContaining('blob'), findsOneWidget);
      await tester.tap(find.byKey(const Key('detected_0')));
      await tester.pumpAndSettle();
      expect(find.text('Videoni yuklash'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('navigation buttons follow the history', (tester) async {
      await openBrowser(tester, initial: Uri.parse('https://site.test/1'));
      browser.navigate('https://site.test/2');
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.widget<IconButton>(find.byKey(const Key('browserBack'))).onPressed, isNotNull);
      expect(tester.widget<IconButton>(find.byKey(const Key('browserForward'))).onPressed, isNull);
      await tester.tap(find.byKey(const Key('browserBack')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(browser.index, 0);
      expect(tester.widget<IconButton>(find.byKey(const Key('browserForward'))).onPressed, isNotNull);
      await tester.pumpWidget(const SizedBox());
    });
  });
}

/// HlsVariant yaratish uchun yordamchi
class HlsVariantForTest {
  static HlsVariant make(String url, int height) => HlsVariant(url: Uri.parse(url), bandwidth: height * 1000, height: height);
}
