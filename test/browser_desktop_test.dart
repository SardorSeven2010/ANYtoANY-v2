import 'package:any_to_any/app_theme.dart';
import 'package:any_to_any/browser/webview_backend.dart';
import 'package:any_to_any/downloader/detected.dart';
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

  Future<void> open(WidgetTester tester, String url) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(appThemes.first),
      home: BrowserScreen(
        initial: Uri.parse(url),
        backend: browser,
        detector: MediaDetector(
          probe: (u, h) async => ProbeResult(url: u, length: 5 << 20, acceptsRanges: true),
          fetch: (u, h) async => ('', u),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));
  }

  group('which sites get the desktop version', () {
    test('YouTube in all its forms; look-alike names are left alone', () {
      for (final url in [
        'https://www.youtube.com/watch?v=1',
        'https://m.youtube.com/watch?v=1',
        'https://music.youtube.com/',
        'https://youtube.com/',
        'https://youtu.be/abc',
      ]) {
        expect(siteNeedsDesktop(url), isTrue, reason: url);
      }
      for (final url in [
        'https://example.com/youtube.com',
        'https://notyoutube.com/',
        'https://youtube.com.evil.example/',
        'https://vimeo.com/1',
        'not a url',
      ]) {
        expect(siteNeedsDesktop(url), isFalse, reason: url);
      }
    });

    test('desktop User-Agent keeps the WebView Chrome version and hides the phone markers', () {
      final ua = desktopUserAgent(
        'Mozilla/5.0 (Linux; Android 14; Pixel 7 Build/UP1A; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/126.0.6478.122 Mobile Safari/537.36',
      );
      expect(ua, contains('Chrome/126.0.6478.122'));
      expect(ua, contains('X11; Linux x86_64'));
      expect(ua, isNot(contains('Android')));
      expect(ua, isNot(contains('Mobile')));
      expect(ua, isNot(contains('wv')));
      expect(desktopUserAgent(null), contains('Chrome/126.0.0.0'));
      final ios = desktopUserAgent('anything', ios: true);
      expect(ios, contains('Macintosh'));
      expect(ios, isNot(contains('iPhone')));
    });
  });

  group('desktop version in the mini-browser', () {
    testWidgets('a YouTube address opens straight in the desktop version (one load, no reload)', (tester) async {
      await open(tester, 'https://m.youtube.com/watch?v=1');
      expect(browser.desktopChanges, [true]);
      expect(browser.desktop, isTrue);
      expect(browser.loaded.single.toString(), 'https://m.youtube.com/watch?v=1');
      expect(browser.reloaded, isFalse, reason: 'the version was chosen before the page was loaded');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('an ordinary site stays on the phone version', (tester) async {
      await open(tester, 'https://example.com/');
      expect(browser.desktopChanges, isEmpty);
      expect(browser.desktop, isFalse);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('opening YouTube from a link on another page switches the version, reloads and tells why', (tester) async {
      await open(tester, 'https://example.com/');
      browser.navigate('https://m.youtube.com/watch?v=9');
      await tester.pump();
      expect(browser.desktop, isTrue);
      expect(browser.reloaded, isTrue);
      expect(find.textContaining('Kompyuter versiyasi yoqildi'), findsOneWidget);
      // boshqa saytga o'tilsa, telefon versiyasiga qaytadi
      browser.reloaded = false;
      await tester.pump(const Duration(seconds: 4));
      browser.navigate('https://example.com/other');
      await tester.pump();
      expect(browser.desktop, isFalse);
      expect(browser.reloaded, isTrue);
      expect(browser.desktopChanges, [true, false]);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the same page is not reloaded again and again while it redirects', (tester) async {
      await open(tester, 'https://example.com/');
      browser.navigate('https://m.youtube.com/watch?v=9');
      browser.navigate('https://www.youtube.com/watch?v=9'); // m. -> www. yo'naltirish
      await tester.pump();
      expect(browser.desktopChanges, [true]);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the button switches by hand and the choice is respected afterwards', (tester) async {
      await open(tester, 'https://example.com/');
      await tester.tap(find.byKey(const Key('browserDesktop')));
      await tester.pump();
      expect(browser.desktop, isTrue);
      expect(browser.reloaded, isTrue);
      // qo'lda tanlangandan keyin sayt almashsa ham o'zgarmaydi
      browser.navigate('https://vimeo.com/1');
      await tester.pump();
      expect(browser.desktop, isTrue);
      // qo'lda telefon versiyasiga qaytarilsa, YouTube ham telefon versiyasida qoladi
      await tester.tap(find.byKey(const Key('browserDesktop')));
      await tester.pump();
      expect(browser.desktop, isFalse);
      browser.navigate('https://m.youtube.com/watch?v=1');
      await tester.pump();
      expect(browser.desktop, isFalse);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('the page view is kept alive while a video plays', () {
    testWidgets('on while playing, still on during a short pause, off after a long one', (tester) async {
      await open(tester, 'https://example.com/');
      expect(bridge.webViewKeepAlives, isEmpty);
      browser.media(playing: true, title: 'Musiqa');
      await tester.pump();
      expect(bridge.webViewKeepAlives, [(7, true)]);
      // keyingi videoga o'tish payti: qisqa pauza
      browser.media(playing: false, title: 'Musiqa');
      await tester.pump(const Duration(seconds: 5));
      browser.media(playing: true, title: 'Keyingi');
      await tester.pump(const Duration(seconds: 30));
      expect(bridge.webViewKeepAlives, [(7, true)], reason: 'the playlist went on, nothing was switched off');
      // uzoq pauza: tirik tutish to'xtaydi
      browser.media(playing: false, title: 'Keyingi');
      await tester.pump(const Duration(seconds: 21));
      expect(bridge.webViewKeepAlives.last, (7, false));
      // yana o'ynasa, qayta yoqiladi
      browser.media(playing: true, title: 'Keyingi');
      await tester.pump();
      expect(bridge.webViewKeepAlives.last, (7, true));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a page without media or closing the browser switches it off at once', (tester) async {
      await open(tester, 'https://example.com/');
      browser.media(playing: true, title: 'A');
      await tester.pump();
      browser.media(playing: false, hasMedia: false);
      await tester.pump();
      expect(bridge.webViewKeepAlives.last, (7, false));
      browser.media(playing: true, title: 'B');
      await tester.pump();
      expect(bridge.webViewKeepAlives.last, (7, true));
      await tester.pumpWidget(const SizedBox()); // brauzer yopildi
      expect(bridge.webViewKeepAlives.last, (7, false));
    });
  });
}
