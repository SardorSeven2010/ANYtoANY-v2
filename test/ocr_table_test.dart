import 'package:any_to_any/ocr/ocr_types.dart';
import 'package:any_to_any/ocr/scan_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'helpers/scan_fixtures.dart';

void main() {
  group('table detector', () {
    test('finds the grid, tolerates a slight skew, and merges cells that have no wall between them', () {
      final image = tablePage();
      final geometry = analyzeGeometry(image);
      final grid = geometry.grid;
      expect(grid, isNotNull);
      expect(grid!.colCount, 4);
      expect(grid.rowCount, 4);
      final merged = grid.cells.where((c) => c.rowSpan > 1 || c.colSpan > 1).map((c) => c.toString()).toSet();
      expect(merged, {'GridCell(0,0 2x1)', 'GridCell(0,2 1x2)'});
      expect(grid.cells.length, 16 - 1 - 1);
      // chiziqlar o'z joyida (± bir necha piksel)
      for (int i = 0; i < 5; i++) {
        expect(grid.xs[i], closeTo(const [100, 220, 520, 720, 900][i] + 0.004 * 500, 8), reason: 'column line $i');
      }
    });

    test('a page without a table has none', () {
      final image = img.Image(width: 800, height: 800, numChannels: 3);
      img.fill(image, color: img.ColorRgb8(255, 255, 255));
      // matnga o'xshash qisqa chiziqlar
      for (int y = 100; y < 700; y += 40) {
        img.drawLine(image, x1: 80, y1: y, x2: 140, y2: y, color: img.ColorRgb8(0, 0, 0), thickness: 3);
      }
      expect(analyzeGeometry(image).grid, isNull);
    });

    test('a straight scan needs no rotation', () {
      final geometry = analyzeGeometry(tablePage(vSlope: 0, hSlope: 0));
      expect(geometry.deskew.isIdentity, isTrue);
      expect(geometry.grid!.colCount, 4);
    });
  });

  group('page builder', () {
    Future<List<OcrWord>> none(img.Image crop, {bool lineMode = false}) async => [];

    OcrWord word(String text, double cx, double cy) => OcrWord(text, cx - 30, cy - 8, cx + 30, cy + 8);

    test('words land in their cells; text outside the table becomes lines before / after it', () async {
      final image = tablePage();
      final words = [
        word('Sarlavha', 500, 150),
        word('T/r', 160 + 2, 360 + 2),
        word('Ism', 340, 470),
        word('Ali', 400, 475),
        word('Vali', 620, 570),
        word('7', 810, 670),
        word('Izoh', 500, 800),
      ];
      final page = await buildScanPage(image: image, geometry: analyzeGeometry(image), words: words, recognizeCrop: none);
      expect(page.before.map((l) => l.text), ['Sarlavha']);
      expect(page.after.map((l) => l.text), ['Izoh']);
      final table = page.table!;
      expect(table.colCount, 4);
      expect(table.headerRows, 2);
      expect(table.textAt(0, 0), 'T/r');
      expect(table.textAt(1, 1), 'Ism Ali');
      expect(table.textAt(2, 2), 'Vali');
      expect(table.textAt(2, 3), '');
      expect(table.textAt(3, 3), '7');
    });

    test('junk marks the OCR makes from table lines are dropped', () async {
      final image = tablePage();
      final words = [word('|', 220, 400), word('—', 300, 300), word('Matn', 370, 470)];
      final page = await buildScanPage(image: image, geometry: analyzeGeometry(image), words: words, recognizeCrop: none);
      expect(page.table!.textAt(1, 1), 'Matn');
      expect(page.before, isEmpty);
    });

    test('a narrow tall header cell with ink but no text is turned and read again; the direction is kept', () async {
      final image = tablePage(rotatedHeaderInk: true);
      final tried = <String>[];
      Future<List<OcrWord>> recognize(img.Image crop, {bool lineMode = false}) async {
        // burilgan (yotiq) kesim: sana o'qiladi; tik kesim: hech narsa
        final landscape = crop.width > crop.height;
        tried.add(landscape ? 'turned' : 'upright');
        return landscape ? [OcrWord('19/11/2026', 0, 0, 100, 20)] : [];
      }

      final page = await buildScanPage(
        image: image,
        geometry: analyzeGeometry(image),
        words: const [],
        recognizeCrop: recognize,
      );
      final cell = page.table!.cells.firstWhere((c) => c.row == 0 && c.col == 0);
      expect(cell.text, '19/11/2026');
      expect(cell.rotation, 90, reason: 'the first direction that reads wins');
      expect(tried, contains('upright'));
    });

    test('an empty cell with no ink at all is not sent to OCR', () async {
      final image = tablePage();
      int calls = 0;
      await buildScanPage(
        image: image,
        geometry: analyzeGeometry(image),
        words: const [],
        recognizeCrop: (crop, {bool lineMode = false}) async {
          calls++;
          return [];
        },
      );
      expect(calls, 0);
    });

    test('without a table all words become text lines, side by side blocks are separate lines', () async {
      final image = img.Image(width: 800, height: 800, numChannels: 3);
      img.fill(image, color: img.ColorRgb8(255, 255, 255));
      final words = [
        OcrWord('Chap', 50, 100, 110, 120),
        OcrWord('matn', 120, 100, 180, 120),
        OcrWord('O\'ng', 600, 100, 660, 120),
        OcrWord('Pastda', 50, 300, 130, 320),
      ];
      final page = await buildScanPage(image: image, geometry: analyzeGeometry(image), words: words, recognizeCrop: none);
      expect(page.table, isNull);
      expect(page.before.map((l) => l.text), ['Chap matn', "O'ng", 'Pastda']);
    });
  });

  group('tesseract output', () {
    test('only word rows are taken; confidence becomes 0..1', () {
      const tsv = 'level\tpage_num\tblock_num\tpar_num\tline_num\tword_num\tleft\ttop\twidth\theight\tconf\ttext\n'
          '1\t1\t0\t0\t0\t0\t0\t0\t800\t600\t-1\t\n'
          '5\t1\t1\t1\t1\t1\t10\t20\t50\t12\t91.5\tSalom\n'
          '5\t1\t1\t1\t1\t2\t70\t20\t40\t12\t-1\t \n'
          '5\t1\t1\t1\t1\t3\t120\t20\t30\t12\t80\tdunyo\n';
      final words = parseTesseractTsv(tsv);
      expect(words.map((w) => w.text), ['Salom', 'dunyo']);
      expect(words.first.left, 10);
      expect(words.first.right, 60);
      expect(words.first.confidence, closeTo(0.915, 1e-9));
    });
  });
}
