import 'dart:convert';
import 'dart:io';

import 'package:any_to_any/app_theme.dart';
import 'package:any_to_any/ocr/ocr_types.dart';
import 'package:any_to_any/ocr/pdf_probe.dart';
import 'package:any_to_any/ocr/scan_convert.dart';
import 'package:any_to_any/ocr/scan_service.dart';
import 'package:any_to_any/screens/online_pdf_screen.dart';
import 'package:any_to_any/services/native_bridge.dart';
import 'package:any_to_any/services/profile_service.dart';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/widgets.dart' as pw;

import 'helpers/fake_native.dart';
import 'helpers/scan_fixtures.dart';

/// Soxta matn tanish dvigateli: sahifa rasmi uchun tayyor so'zlar, kesilgan bo'laklar uchun bo'sh ro'yxat
class FakeOcr implements OcrEngine {
  FakeOcr({this.available = true, this.pageWords = const []});

  final bool available;
  final List<OcrWord> pageWords;
  final List<String> seen = [];

  @override
  double get fontFactor => 1.0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<List<OcrWord>> recognize(String imagePath, {bool lineMode = false}) async {
    seen.add(imagePath.split(Platform.pathSeparator).last);
    return imagePath.contains('clean_') ? pageWords : [];
  }
}

OcrWord word(String text, double cx, double cy) => OcrWord(text, cx - 30, cy - 8, cx + 30, cy + 8);

String read(Archive a, String name) => utf8.decode(a.findFile(name)!.content as List<int>);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('is a PDF scanned?', () {
    test('a PDF with real text has text; one that is only a picture does not', () async {
      final text = pw.Document()..addPage(pw.Page(build: (c) => pw.Center(child: pw.Text('Salom dunyo, bu matnli hujjat'))));
      expect(pdfBytesHaveText(await text.save()), isTrue);

      final plain = pw.Document(compress: false)..addPage(pw.Page(build: (c) => pw.Text('Oddiy matn')));
      expect(pdfBytesHaveText(await plain.save()), isTrue, reason: 'uncompressed content is read too');

      final picture = pw.MemoryImage(img.encodePng(tablePage()));
      final scan = pw.Document()..addPage(pw.Page(build: (c) => pw.Image(picture)));
      expect(pdfBytesHaveText(await scan.save()), isFalse);
    });

    test('files that cannot be read are treated as ordinary PDFs (the online converter handles them)', () async {
      expect(await pdfHasText('/nonexistent/file.pdf'), isTrue);
      final dir = await Directory.systemTemp.createTemp('probe');
      addTearDown(() => dir.delete(recursive: true));
      final broken = File('${dir.path}/x.pdf')..writeAsBytesSync([1, 2, 3, 4]);
      expect(await pdfHasText(broken.path), isFalse, reason: 'nothing that looks like text');
    });
  });

  group('scan -> Word / Excel', () {
    late Directory dir;
    final words = [
      word('Sarlavha', 500, 150),
      word('T/r', 160, 360),
      word('Guruh', 620, 350),
      word('Ism', 370, 470),
      word('Vali', 620, 570),
    ];

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('scanconv');
    });
    tearDown(() => dir.delete(recursive: true));

    Future<List<String>> renderOnePage(String pdf, Directory work) async {
      final f = File('${work.path}/page_1.png')..writeAsBytesSync(img.encodePng(tablePage()));
      return [f.path];
    }

    test('the table comes out as a real Word table with merged headers; nothing is left in the work folder', () async {
      final stages = <String>[];
      final out = '${dir.path}/natija.docx';
      await convertScannedPdf(
        pdfPath: 'x.pdf',
        outPath: out,
        format: 'docx',
        engine: FakeOcr(pageWords: words),
        renderPages: renderOnePage,
        workDir: dir,
        onStage: stages.add,
      );
      final doc = read(ZipDecoder().decodeBytes(File(out).readAsBytesSync()), 'word/document.xml');
      expect(doc, contains('<w:tbl>'));
      expect(doc, contains('Sarlavha'));
      expect(doc, contains('T/r'));
      expect(doc, contains('Guruh'));
      expect(doc, contains('w:gridSpan w:val="2"'));
      expect(doc, contains('w:vMerge w:val="restart"'));
      expect(stages.first, contains('tayyorlanmoqda'));
      expect(stages.any((s) => s.contains('matn tanilmoqda')), isTrue);
      expect(dir.listSync().whereType<File>().map((f) => f.uri.pathSegments.last), ['natija.docx'],
          reason: 'page and cleaned images were removed');
    });

    test('Excel output has the merged header and the numbers as cells', () async {
      final out = '${dir.path}/natija.xlsx';
      await convertScannedPdf(
        pdfPath: 'x.pdf',
        outPath: out,
        format: 'xlsx',
        engine: FakeOcr(pageWords: [...words, word('7', 810, 670)]),
        renderPages: renderOnePage,
        workDir: dir,
      );
      final sheet = read(ZipDecoder().decodeBytes(File(out).readAsBytesSync()), 'xl/worksheets/sheet1.xml');
      expect(sheet, contains('<mergeCell ref="A2:A3"/>'));
      expect(sheet, contains('<mergeCell ref="C2:D2"/>'));
      expect(sheet, contains('<v>7</v>'));
    });

    test('clear errors: engine missing, wrong format, nothing recognised, too many pages', () async {
      Future<void> run({OcrEngine? engine, String format = 'docx', PageRenderer? render}) => convertScannedPdf(
            pdfPath: 'x.pdf',
            outPath: '${dir.path}/o.$format',
            format: format,
            engine: engine ?? FakeOcr(pageWords: words),
            renderPages: render ?? renderOnePage,
            workDir: dir,
          );

      await expectLater(run(engine: FakeOcr(available: false)), throwsA(isA<ScanConvertException>()));
      await expectLater(run(format: 'pptx'), throwsA(isA<ScanConvertException>()));
      // matn ham, jadval ham yo'q: bo'sh oq sahifa
      Future<List<String>> blank(String pdf, Directory work) async {
        final image = img.Image(width: 600, height: 800, numChannels: 3);
        img.fill(image, color: img.ColorRgb8(255, 255, 255));
        return [(File('${work.path}/b.png')..writeAsBytesSync(img.encodePng(image))).path];
      }

      await expectLater(
        run(engine: FakeOcr(), render: blank),
        throwsA(isA<ScanConvertException>().having((e) => e.message, 'message', contains('matn topilmadi'))),
      );
      await expectLater(
        run(render: (pdf, work) async => List.generate(maxScanPages + 1, (i) => 'p$i.png')),
        throwsA(isA<ScanConvertException>().having((e) => e.message, 'message', contains('$maxScanPages'))),
      );
      expect(File('${dir.path}/o.docx').existsSync(), isFalse, reason: 'no half-written file');
    });
  });

  group('Android ML Kit bridge', () {
    tearDown(() => setNativeBridge(null));

    test('words come back with their positions; broken rows are skipped', () async {
      final bridge = FakeNativeBridge()
        ..ocrResult = [
          {'text': 'Salom', 'left': 10, 'top': 20, 'right': 80, 'bottom': 40},
          {'text': '  ', 'left': 1, 'top': 1, 'right': 2, 'bottom': 2},
          {'text': 'xato'},
        ];
      setNativeBridge(bridge);
      final engine = NativeOcrEngine();
      expect(await engine.isAvailable(), isTrue);
      final found = await engine.recognize('/tmp/a.png');
      expect(found, hasLength(1));
      expect(found.single.text, 'Salom');
      expect(found.single.right, 80);
      expect(bridge.calls, contains('ocr:/tmp/a.png'));
    });

    test('when the platform says no, the engine is unavailable and failing recognition is an error', () async {
      setNativeBridge(FakeNativeBridge(supported: false));
      expect(await NativeOcrEngine().isAvailable(), isFalse);
      setNativeBridge(FakeNativeBridge()); // ocrResult == null
      await expectLater(NativeOcrEngine().recognize('/tmp/a.png'), throwsA(isA<OcrException>()));
    });
  });

  group('PDF screen', () {
    tearDown(() => setOcrEngine(null));

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      profile.isPro = true;
      profile.proUntil = DateTime.now().add(const Duration(days: 10));
      await tester.pumpWidget(MaterialApp(theme: buildAppTheme(appThemes.first), home: const OnlinePdfScreen()));
      await tester.pump();
      await tester.pump();
    }

    testWidgets('where text can be read on the device, Word and Excel get the scan switch; PowerPoint does not', (tester) async {
      setOcrEngine(FakeOcr());
      await open(tester);
      expect(find.byKey(const Key('scanSwitch')), findsOneWidget);
      await tester.tap(find.text('PowerPoint'));
      await tester.pump();
      expect(find.byKey(const Key('scanSwitch')), findsNothing);
      await tester.tap(find.text('Excel'));
      await tester.pump();
      expect(find.byKey(const Key('scanSwitch')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('where it cannot (iPhone, Windows), nothing changes: no switch', (tester) async {
      setOcrEngine(FakeOcr(available: false));
      await open(tester);
      expect(find.byKey(const Key('scanSwitch')), findsNothing);
      expect(find.text('Aylantirish (0 ta)'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
