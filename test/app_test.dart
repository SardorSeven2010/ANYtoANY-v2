import 'package:any_to_any/app_theme.dart';
import 'package:any_to_any/config.dart';
import 'package:any_to_any/main.dart';
import 'package:any_to_any/screens/converter_screen.dart';
import 'package:any_to_any/screens/online_pdf_screen.dart';
import 'package:any_to_any/screens/media_library.dart';
import 'package:any_to_any/screens/pdf_merge_screen.dart';
import 'package:any_to_any/player/engine.dart';
import 'package:any_to_any/screens/player_screen.dart';
import 'package:any_to_any/screens/subscription_screen.dart';
import 'package:any_to_any/services/media_tools.dart';
import 'package:any_to_any/services/online_pdf.dart';
import 'package:any_to_any/services/profile_service.dart';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker_platform_interface/file_picker_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

class FakeLauncher extends UrlLauncherPlatform with MockPlatformInterfaceMixin {
  String? launched;
  @override
  LinkDelegate? get linkDelegate => null;
  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched = url;
    return true;
  }
}

final class FakeFile extends PlatformFile {
  FakeFile(this.name);
  @override
  final String name;
  @override
  Uri get uri => Uri.file('/cache/$name');
  @override
  XFile get xFile => XFile('/cache/$name');
  @override
  int? lengthSync() => 2 * 1024 * 1024;
  @override
  Future<int?> length() async => lengthSync();
  @override
  Future<Uint8List> readAsBytes() async => Uint8List(0);
  @override
  Stream<Uint8List> readAsByteStream() => const Stream.empty();
}

class FakePicker extends FilePickerPlatform with MockPlatformInterfaceMixin {
  List<String> next = [];
  FileType? lastType;
  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    lastType = type;
    return [for (final n in next) FakeFile(n)];
  }
}

String formatOf(WidgetTester tester) => tester.widget<DropdownButton<String>>(find.byType(DropdownButton<String>).first).value!;

Future<void> settle(WidgetTester tester) async {
  for (int i = 0; i < 4; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
    await tester.pump(const Duration(milliseconds: 400));
  }
}

void phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({'user_email': 'ali@example.com'});
    await themeController.select(appThemes.first);
    profile
      ..isPro = false
      ..proUntil = null
      ..isAdmin = false
      ..paymentRequested = false
      ..totalSeconds = 0;
  });

  group('logic', () {
    test('prices and formatting', () {
      expect(proPlans.map((p) => p.priceLabel).toList(), ["12 000 so'm", "32 000 so'm", "50 000 so'm", "72 000 so'm", "100 000 so'm"]);
      expect(proPlans.map((p) => p.months).toList(), [1, 3, 6, 9, 12]);
      expect(planById('month_3')!.price, 32000);
      expect(planById('month_9')!.price, 72000);
      expect(formatSom(999), "999 so'm");
      expect(formatSom(1234567), "1 234 567 so'm");
      expect(planById('month_6')!.price, 50000);
      expect(planById('nope'), isNull);
      expect(supportPhone, '+998887028708');
      expect(formatDate(DateTime(2026, 12, 5)), '05.12.2026');
    });

    test('subscription expiry', () {
      final p = ProfileService();
      expect(p.proActive, isFalse);
      p.isPro = true;
      expect(p.proActive, isTrue, reason: 'no expiry date = active');
      p.proUntil = DateTime.now().add(const Duration(days: 3));
      expect(p.proActive, isTrue);
      expect(p.proLabel, contains('gacha'));
      p.proUntil = DateTime.now().subtract(const Duration(minutes: 1));
      expect(p.proActive, isFalse, reason: 'expired subscription must not count as PRO');
      expect(p.proLabel, 'Bepul tarif');
      p.isPro = false;
      p.proUntil = DateTime.now().add(const Duration(days: 3));
      expect(p.proActive, isFalse);
    });

    test('ffmpeg arguments', () {
      expect(buildFfmpegArgs(inPath: 'a.mp4', outPath: 'o.mp3', format: 'mp3'), ['-y', '-i', 'a.mp4', '-vn', 'o.mp3']);
      expect(buildFfmpegArgs(inPath: 'a.mp4', outPath: 'o.mp3', format: 'mp3', audioBitrate: '192k'),
          ['-y', '-i', 'a.mp4', '-vn', '-b:a', '192k', 'o.mp3']);
      // lossless formats ignore bitrate
      expect(buildFfmpegArgs(inPath: 'a.mp4', outPath: 'o.flac', format: 'flac', audioBitrate: '192k'),
          ['-y', '-i', 'a.mp4', '-vn', 'o.flac']);
      final webm = buildFfmpegArgs(inPath: 'a b".mp4', outPath: 'o.webm', format: 'webm', videoCodec: 'libvpx-vp9');
      expect(webm, containsAllInOrder(['-i', 'a b".mp4', '-c:v', 'libvpx-vp9', '-c:a', 'libvorbis', 'o.webm']));
      expect(buildFfmpegArgs(inPath: 'a.mkv', outPath: 'o.mp4', format: 'mp4', videoCodec: 'copy'),
          ['-y', '-i', 'a.mkv', '-c:v', 'copy', '-c:a', 'aac', 'o.mp4']);
      expect(buildFfmpegArgs(inPath: 'a.mp4', outPath: 'o.png', format: 'png'),
          ['-y', '-i', 'a.mp4', '-an', '-frames:v', '1', '-update', '1', 'o.png']);
      expect(codecsFor('webm').map((c) => c.value), ['libvpx-vp9', 'copy']);
      expect(codecsFor('avi').map((c) => c.value), ['libx264', 'mpeg4', 'copy']);
      expect(codecsFor('mp4').length, 5);
    });

    test('outdated server function is explained, not shown as a raw error', () async {
      // eski funksiya: start bosqichida targetFormat so'raydi
      Future<Map<String, dynamic>> oldFunction(Map<String, dynamic> body) async =>
          throw const OnlinePdfException("targetFormat noto'g'ri");
      await expectLater(
        convertOnline(
          sourcePath: '/x/hisobot.pptx',
          outPath: '/x/hisobot.pdf',
          operation: OnlineOperation.create,
          sourceFormat: 'pptx',
          invoke: oldFunction,
        ),
        throwsA(isA<OnlinePdfException>().having((e) => e.message, 'message', outdatedFunctionMessage)),
      );
      expect(outdatedFunctionMessage, contains('quick-worker'));
      expect(outdatedFunctionMessage, contains('Deploy'));
      // PDF dan Word yo'nalishida boshqa xatolar o'zgarmasdan qaytadi
      await expectLater(
        convertOnline(
          sourcePath: '/x/a.pdf',
          outPath: '/x/a.docx',
          targetFormat: 'exe',
          invoke: oldFunction,
        ),
        throwsA(isA<OnlinePdfException>().having((e) => e.message, 'message', "targetFormat noto'g'ri")),
      );
    });

    test('png size is read from the file header', () {
      // 8 bayt imzo + IHDR: uzunlik(4) "IHDR"(4) eni(4) bo'yi(4)
      final header = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52,
        0, 0, 0x02, 0x53, 0, 0, 0x03, 0x4A];
      expect(pngSize(header), (595, 842));
      expect(pngSize([1, 2, 3]), isNull);
    });

    test('file helpers', () {
      expect(extensionOf('My.Video.MP4'), 'mp4');
      expect(extensionOf('noext'), '');
      expect(baseNameOf('a.b.mp3'), 'a.b');
      expect(isVideoFile('x.MKV'), isTrue);
      expect(isAudioFile('x.flac'), isTrue);
      expect(isPlayableFile('x.pdf'), isFalse);
      expect(isPdfFile('x.PDF'), isTrue);
      expect(appThemes.length, greaterThanOrEqualTo(6));
      expect(appThemes.map((t) => t.id).toSet().length, appThemes.length);
    });
  });

  testWidgets('login screen', (tester) async {
    phone(tester);
    await tester.pumpWidget(const CoreApp(isLoggedIn: false));
    await settle(tester);
    expect(find.text("Kirish yoki ro'yxatdan o'tish"), findsOneWidget);
    expect(find.text('Tasdiqlash kodini olish'), findsOneWidget);
    // invalid email is rejected locally
    await tester.tap(find.text('Tasdiqlash kodini olish'));
    await tester.pump();
    expect(find.text("Iltimos, to'g'ri elektron pochta kiriting!"), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home: tools, hamburger menu, support call, theme change', (tester) async {
    // baland ekran: konvertorlar ro'yxatining hammasi birdan chiziladi
    tester.view.physicalSize = const Size(1080, 3900);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final launcher = FakeLauncher();
    UrlLauncherPlatform.instance = launcher;

    await tester.pumpWidget(const CoreApp(isLoggedIn: true));
    await settle(tester);
    for (final t in ['Video va audio', 'Video konvertor', 'Videodan audio', 'Audio konvertor', 'PDF, hujjat va rasm', 'PDF dan Word', 'Hujjatdan PDF', 'PDF birlashtirish', 'Rasm va PDF', "PDF o'qish"]) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    // pastki qatorda 3 ta bo'lim
    expect(find.byType(NavigationDestination), findsNWidgets(3));
    final labels = tester.widgetList<NavigationDestination>(find.byType(NavigationDestination)).map((d) => d.label).toList();
    expect(labels, ['Konvertor', 'Video', 'Audio']);
    await tester.tap(find.text('Video'));
    await settle(tester);
    expect(find.text('Video fayllar'), findsWidgets);
    expect(find.text('Ruxsat berish'), findsOneWidget);
    expect(find.text('Fayllardan tanlash'), findsOneWidget);
    expect(find.text('Video konvertor'), findsNothing);
    await tester.tap(find.text('Audio'));
    await settle(tester);
    expect(find.textContaining('audio fayllar'), findsOneWidget);
    await tester.tap(find.text('Konvertor'));
    await settle(tester);
    expect(find.text('Video konvertor'), findsOneWidget);
    expect(find.text('Media konvertor'), findsNothing, reason: 'no second, overlapping video converter');
    // PDF birlashtirish alohida satr
    await tester.ensureVisible(find.text('PDF birlashtirish'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PDF birlashtirish'));
    await tester.pumpAndSettle();
    expect(find.byType(PdfMergeScreen), findsOneWidget);
    expect(find.text("PDF fayl qo'shish"), findsOneWidget);
    expect(find.text('Birlashtirish (0 ta)'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    // Hujjatdan PDF alohida satr
    await tester.ensureVisible(find.text('Hujjatdan PDF'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hujjatdan PDF'));
    await tester.pumpAndSettle();
    expect(find.byType(OnlinePdfScreen), findsOneWidget);
    expect(find.text('Faqat PRO obunachilar uchun'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('ali@example.com'), findsOneWidget);
    expect(find.text('PRO OLISH'), findsOneWidget);

    // 3 chiziq (hamburger) at top-left opens the menu
    final menu = find.byTooltip('Open navigation menu');
    expect(menu, findsOneWidget);
    expect(tester.getCenter(menu).dx, lessThan(60));
    await tester.tap(menu);
    await tester.pumpAndSettle();
    expect(find.text('Ilova mavzusi'), findsOneWidget);
    expect(find.text("Qo'llab-quvvatlash xizmati"), findsOneWidget);
    expect(find.text('+998887028708'), findsOneWidget);
    expect(find.text('PRO obuna'), findsOneWidget);
    expect(find.text('Admin panel'), findsNothing, reason: 'non-admin must not see admin panel');

    // support -> phone dialer with the number
    await tester.tap(find.text("Qo'llab-quvvatlash xizmati"));
    await tester.pumpAndSettle();
    expect(launcher.launched, 'tel:+998887028708');

    // theme change from the menu
    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ilova mavzusi'));
    await tester.pumpAndSettle();
    for (final theme in appThemes) {
      await tester.scrollUntilVisible(find.text(theme.name), 200, scrollable: find.byType(Scrollable).last);
      expect(find.text(theme.name), findsOneWidget);
    }
    await tester.scrollUntilVisible(find.text('Sakura'), -200, scrollable: find.byType(Scrollable).last);
    expect(Theme.of(tester.element(find.text('Sakura'))).brightness, Brightness.dark);
    await tester.tap(find.text('Sakura'));
    await tester.pumpAndSettle();
    expect(themeController.current.id, 'sakura');
    expect(Theme.of(tester.element(find.text('Sakura'))).brightness, Brightness.light);
    expect((await SharedPreferences.getInstance()).getString('theme_id'), 'sakura');

    // a fresh controller restores the saved theme
    final restored = ThemeController();
    await restored.load();
    expect(restored.current.id, 'sakura');

    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('admin entry appears only for admin', (tester) async {
    phone(tester);
    await tester.pumpWidget(const CoreApp(isLoggedIn: true));
    await settle(tester);
    profile.isAdmin = true;
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    expect(find.text('Admin panel'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  Widget conv(ConverterMode mode, [String key = 'k']) =>
      MaterialApp(theme: buildAppTheme(appThemes.first), home: ConverterScreen(key: ValueKey(key), mode: mode));

  Future<void> pickFormat(WidgetTester tester, String label) async {
    await tester.tap(find.byType(DropdownButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  testWidgets('video -> video: codecs are shown straight away', (tester) async {
    phone(tester);
    profile
      ..isPro = true
      ..proUntil = DateTime.now().add(const Duration(days: 5));

    await tester.pumpWidget(conv(ConverterMode.video, 'video'));
    await settle(tester);
    expect(find.text('Video konvertor'), findsOneWidget);
    expect(find.text('Video tanlash'), findsOneWidget);
    expect(find.text('Qaysi formatga aylantirilsin'), findsOneWidget);
    expect(formatOf(tester), 'mp4');
    expect(find.text('Video kodekni tanlang'), findsOneWidget);
    expect(find.text('H.264 (Barcha telefonlar uchun)'), findsOneWidget);
    expect(find.text('Ovoz sifati'), findsNothing);
    await tester.tap(find.byType(DropdownButton<String>).first);
    await tester.pumpAndSettle();
    expect(find.text('MP3'), findsNothing, reason: 'video converter offers no audio formats');
    for (final f in ['MP4', 'MKV', 'AVI', 'MOV', 'WEBM', 'GIF']) {
      expect(find.text(f), findsWidgets, reason: f);
    }
    await tester.tap(find.text('WEBM').last);
    await tester.pumpAndSettle();
    expect(find.text('VP9 (WebM / YouTube kodeki)'), findsOneWidget);
    await pickFormat(tester, 'AVI');
    expect(find.text('H.264 (Barcha telefonlar uchun)'), findsOneWidget);
    await pickFormat(tester, 'MKV');
    await tester.tap(find.text('H.264 (Barcha telefonlar uchun)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('H.265 / HEVC (Kichik hajm, yuqori sifat)').last);
    await tester.pumpAndSettle();
    expect(tester.widget<DropdownButton<String>>(find.byType(DropdownButton<String>).last).value, 'libx265');
    // GIF uchun kodek kerak emas
    await pickFormat(tester, 'GIF');
    expect(find.text('Video kodekni tanlang'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('each converter has its own job: audio, video-to-audio, image/pdf', (tester) async {
    phone(tester);
    final picker = FakePicker();
    FilePickerPlatform.instance = picker;
    profile
      ..isPro = true
      ..proUntil = DateTime.now().add(const Duration(days: 5));

    // Audio konvertor: faqat audio formatlar, audio fayl so'raydi
    await tester.pumpWidget(conv(ConverterMode.audio, 'audio'));
    await settle(tester);
    expect(find.text('Audio konvertor'), findsOneWidget);
    expect(formatOf(tester), 'mp3');
    expect(find.text('Ovoz sifati'), findsOneWidget);
    expect(find.text('Video kodekni tanlang'), findsNothing);
    await tester.tap(find.byType(DropdownButton<String>).first);
    await tester.pumpAndSettle();
    expect(find.text('MP4'), findsNothing);
    expect(find.text('PNG'), findsNothing);
    await tester.tap(find.text('WAV').last);
    await tester.pumpAndSettle();
    picker.next = ['qoshiq.flac'];
    await tester.tap(find.text('Audio tanlash'));
    await tester.pumpAndSettle();
    expect(picker.lastType, FileType.audio);
    expect(find.text('WAV ga aylantirish (1 ta)'), findsOneWidget);

    // Videodan audio
    await tester.pumpWidget(conv(ConverterMode.videoToAudio, 'v2a'));
    await settle(tester);
    expect(find.text('Videodan audio'), findsOneWidget);
    expect(formatOf(tester), 'mp3');
    expect(find.text('Ovoz sifati'), findsOneWidget);
    await pickFormat(tester, 'FLAC');
    expect(find.text('Ovoz sifati'), findsNothing, reason: 'flac is lossless');
    await pickFormat(tester, 'M4A');
    await tester.tap(find.text('Avto sifat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('320 kbit/s (eng yuqori)').last);
    await tester.pumpAndSettle();
    expect(find.text('320 kbit/s (eng yuqori)'), findsOneWidget);
    picker.next = ['dars.mp4'];
    await tester.tap(find.text('Video tanlash'));
    await tester.pumpAndSettle();
    expect(picker.lastType, FileType.video);

    // Rasm va PDF: PDF tanlansa PNG, rasm tanlansa PDF
    await tester.pumpWidget(conv(ConverterMode.pdfImage, 'p1'));
    await settle(tester);
    expect(find.text('Rasm va PDF'), findsOneWidget);
    expect(formatOf(tester), 'pdf');
    picker.next = ['kitob.pdf'];
    await tester.tap(find.text('Fayl tanlash'));
    await tester.pumpAndSettle();
    expect(formatOf(tester), 'png', reason: 'a PDF cannot be converted to PDF');
    await tester.pumpWidget(conv(ConverterMode.pdfImage, 'p2'));
    await settle(tester);
    picker.next = ['surat.jpg', 'chek.png'];
    await tester.tap(find.text('Fayl tanlash'));
    await tester.pumpAndSettle();
    expect(formatOf(tester), 'pdf');
    // foydalanuvchi o'zi tanlagan format o'zgartirilmaydi
    await tester.pumpWidget(conv(ConverterMode.pdfImage, 'p3'));
    await settle(tester);
    await pickFormat(tester, 'JPG');
    picker.next = ['surat.png'];
    await tester.tap(find.text('Fayl tanlash'));
    await tester.pumpAndSettle();
    expect(formatOf(tester), 'jpg');

    // bepul tarif: 3 tadan ortiq fayl olinmaydi
    profile
      ..isPro = false
      ..proUntil = null;
    await tester.pumpWidget(conv(ConverterMode.video, 'f'));
    await settle(tester);
    picker.next = ['1.mp4', '2.mp4', '3.mp4', '4.mp4', '5.mp4'];
    await tester.tap(find.text('Video tanlash'));
    await tester.pumpAndSettle();
    expect(find.text('MP4 ga aylantirish (3 ta)'), findsOneWidget);
    expect(find.textContaining('Bepul tarifda 3 tagacha fayl'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('free tier: only H.264, other codecs and WEBM need PRO', (tester) async {
    phone(tester);
    expect(codecAllowed('libx264', pro: false), isTrue);
    expect(codecAllowed('libx265', pro: false), isFalse);
    expect(codecAllowed('libx265', pro: true), isTrue);
    expect(formatNeedsPro('webm'), isTrue);
    expect(formatNeedsPro('mp4'), isFalse);
    expect(formatNeedsPro('mp3'), isFalse);

    await tester.pumpWidget(conv(ConverterMode.video, 'free'));
    await settle(tester);
    expect(find.text('H.264 (Barcha telefonlar uchun)'), findsOneWidget);
    expect(find.textContaining('Bepul tarifda faqat H.264'), findsOneWidget);

    // WEBM ro'yxatda PRO belgisi bilan turadi va tanlanmaydi
    await tester.tap(find.byType(DropdownButton<String>).first);
    await tester.pumpAndSettle();
    expect(find.text('PRO'), findsOneWidget);
    await tester.tap(find.text('WEBM').last);
    await tester.pumpAndSettle();
    expect(find.text('WEBM formati faqat PRO obunada ochiladi.'), findsOneWidget);
    expect(formatOf(tester), 'mp4', reason: 'format must not change');

    // qulflangan kodeklar PRO belgisi bilan ko'rinadi, lekin tanlanmaydi
    await pickFormat(tester, 'MKV');
    await tester.tap(find.text('H.264 (Barcha telefonlar uchun)'));
    await tester.pumpAndSettle();
    expect(find.text('PRO'), findsNWidgets(4));
    await tester.tap(find.text('H.265 / HEVC (Kichik hajm, yuqori sifat)').last, warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(tester.widget<DropdownButton<String>>(find.byType(DropdownButton<String>).last).value, 'libx264');

    // PRO yoqilgach hammasi ochiladi
    profile
      ..isPro = true
      ..proUntil = DateTime.now().add(const Duration(days: 30));
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    profile.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.textContaining('Bepul tarifda faqat H.264'), findsNothing);
    await tester.tap(find.byType(DropdownButton<String>).first);
    await tester.pumpAndSettle();
    expect(find.text('PRO'), findsNothing);
    await tester.tap(find.text('WEBM').last);
    await tester.pumpAndSettle();
    expect(find.text('VP9 (WebM / YouTube kodeki)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('subscription plans', (tester) async {
    // baland ekran: ro'yxatning hammasi birdan chiziladi, surish kerak emas
    tester.view.physicalSize = const Size(1080, 9000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: buildAppTheme(appThemes.first), home: const SubscriptionScreen()));
    await settle(tester);
    expect(find.text('Bepul tarif'), findsOneWidget);
    for (final t in ['1 oylik', "12 000 so'm", '3 oylik', "32 000 so'm", '6 oylik', "50 000 so'm", '9 oylik', "72 000 so'm", '1 yillik', "100 000 so'm"]) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    expect(find.textContaining('Umrbod'), findsNothing);
    expect(find.textContaining('Barcha video kodeklar'), findsOneWidget);
    expect(find.textContaining('Word, PowerPoint va Excel'), findsOneWidget);
    expect(find.text("Oyiga 10 667 so'm\n4 000 so'm tejaysiz"), findsOneWidget); // 3 oy: 36 000 o'rniga 32 000
    expect(find.text("Oyiga 8 000 so'm\n36 000 so'm tejaysiz"), findsOneWidget); // 9 oy: 108 000 o'rniga 72 000
    expect(find.text("Oyiga 8 333 so'm\n22 000 so'm tejaysiz"), findsOneWidget); // 6 oy: 72 000 o'rniga 50 000
    expect(find.text("Oyiga 8 333 so'm\n44 000 so'm tejaysiz"), findsOneWidget); // 1 yil: 144 000 o'rniga 100 000
    expect(find.text("To'lov: 1 oylik tarif — 12 000 so'm"), findsOneWidget);
    await tester.tap(find.text('1 yillik'));
    await tester.pumpAndSettle();
    expect(find.text("To'lov: 1 yillik tarif — 100 000 so'm"), findsOneWidget);
    await tester.tap(find.text('6 oylik'));
    await tester.pumpAndSettle();
    expect(find.text("To'lov: 6 oylik tarif — 50 000 so'm"), findsOneWidget);

    // empty payment info is rejected
    await tester.tap(find.text("To'lov qildim"));
    await tester.pump();
    expect(find.text("Kartangiz oxirgi 4 raqami yoki ismingizni yozing."), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('iPhone: audio tab offers the Files app instead of a permission prompt', (tester) async {
    phone(tester);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final picker = FakePicker();
    FilePickerPlatform.instance = picker;
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(appThemes.first),
      home: const Scaffold(body: MediaLibraryTab(kind: MediaKind.audio)),
    ));
    await settle(tester);
    expect(find.text('Ruxsat berish'), findsNothing);
    expect(find.textContaining("Fayllar ilovasidan"), findsOneWidget);
    expect(find.text('Fayllardan tanlash'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Linux: if libmpv is missing the file opens in the system player', (tester) async {
    phone(tester);
    final launcher = FakeLauncher();
    UrlLauncherPlatform.instance = launcher;
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    playerEngineFactory = () => throw Exception('libmpv topilmadi');
    addTearDown(() => playerEngineFactory = () => MediaKitEngine());
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(appThemes.first),
      home: const PlayerScreen(path: '/home/ali/Videos/dars.mp4', title: 'dars.mp4'),
    ));
    await settle(tester);
    expect(find.textContaining("kompyuteringizdagi pleyerda"), findsOneWidget);
    expect(find.textContaining("libmpv"), findsOneWidget);
    expect(find.text('Tizim pleyerida ochish'), findsOneWidget);
    expect(launcher.launched, 'file:///home/ali/Videos/dars.mp4');
    launcher.launched = null;
    await tester.tap(find.text('Tizim pleyerida ochish'));
    await tester.pumpAndSettle();
    expect(launcher.launched, 'file:///home/ali/Videos/dars.mp4');
    debugDefaultTargetPlatformOverride = null;
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('documents -> PDF screen (PRO)', (tester) async {
    phone(tester);
    final picker = FakePicker();
    FilePickerPlatform.instance = picker;
    await tester.pumpWidget(MaterialApp(theme: buildAppTheme(appThemes.first), home: const OnlinePdfScreen(mode: OnlineMode.toPdf)));
    await settle(tester);
    expect(find.text('Hujjatdan PDF'), findsOneWidget);
    expect(find.text('Faqat PRO obunachilar uchun'), findsOneWidget);

    profile
      ..isPro = true
      ..proUntil = DateTime.now().add(const Duration(days: 10));
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    profile.notifyListeners();
    await tester.pump();
    expect(find.text('Hujjatlarni tanlash'), findsOneWidget);
    expect(find.text('PDF ga aylantirish (0 ta)'), findsOneWidget);
    expect(find.text('Word'), findsNothing, reason: 'no target choice: the result is always PDF');

    // faqat qo'llab-quvvatlanadigan hujjat turlari qabul qilinadi
    picker.next = ['shartnoma.docx', 'hisobot.XLSX', 'taqdimot.pptx', 'virus.exe', 'kitob.pdf'];
    await tester.tap(find.text('Hujjatlarni tanlash'));
    await tester.pumpAndSettle();
    expect(find.text('shartnoma.docx'), findsOneWidget);
    expect(find.text('hisobot.XLSX'), findsOneWidget);
    expect(find.text('taqdimot.pptx'), findsOneWidget);
    expect(find.text('virus.exe'), findsNothing);
    expect(find.text('kitob.pdf'), findsNothing);
    expect(find.text('PDF ga aylantirish (3 ta)'), findsOneWidget);
    expect(picker.lastType, FileType.custom);
    expect(onlineSourceFormats, containsAll(['doc', 'docx', 'ppt', 'pptx', 'xls', 'xlsx']));
    expect(tester.takeException(), isNull);
  });

  testWidgets('online pdf is locked without PRO and open with PRO', (tester) async {
    phone(tester);
    await tester.pumpWidget(MaterialApp(theme: buildAppTheme(appThemes.first), home: const OnlinePdfScreen()));
    await settle(tester);
    expect(find.text('Faqat PRO obunachilar uchun'), findsOneWidget);
    expect(find.text('PDF fayllarni tanlash'), findsNothing);

    profile.isPro = true;
    profile.proUntil = DateTime.now().add(const Duration(days: 10));
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    profile.notifyListeners();
    await tester.pump();
    expect(find.text('PDF fayllarni tanlash'), findsOneWidget);
    expect(find.text('Aylantirish (0 ta)'), findsOneWidget);
    for (final t in ['Word', 'PowerPoint', 'Excel']) {
      expect(find.text(t), findsOneWidget);
    }

    profile.proUntil = DateTime.now().subtract(const Duration(days: 1));
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    profile.notifyListeners();
    await tester.pump();
    expect(find.text('Faqat PRO obunachilar uchun'), findsOneWidget, reason: 'expired PRO locks again');
  });
}
