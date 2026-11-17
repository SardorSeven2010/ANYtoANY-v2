import 'dart:convert';

import 'package:any_to_any/ocr/docx_writer.dart';
import 'package:any_to_any/ocr/scan_page.dart';
import 'package:any_to_any/ocr/xlsx_writer.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

/// 3 ustun, 4 qator. Sarlavha 2 qator: 1-ustun 2 qatorga, 2-3 ustunlar 1-qatorda birlashgan.
ScanTable sampleTable({String name = 'Ali & "Vali" <B>', int rotation = 0}) {
  return ScanTable(
    const [100, 300, 200],
    const [60, 120, 50, 50],
    [
      const ScanCell(0, 0, 2, 1, 'T/r'),
      const ScanCell(0, 1, 1, 2, 'Guruh'),
      ScanCell(1, 1, 1, 1, '19/11/2026', rotation: rotation),
      const ScanCell(1, 2, 1, 1, '26/11/2026'),
      const ScanCell(2, 0, 1, 1, '1'),
      ScanCell(2, 1, 1, 1, name),
      const ScanCell(2, 2, 1, 1, ''),
      const ScanCell(3, 0, 1, 1, '2'),
      const ScanCell(3, 1, 1, 1, 'Vali'),
      const ScanCell(3, 2, 1, 1, '5'),
    ],
    22,
  );
}

ScanPage samplePage({ScanTable? table, List<ScanLine>? before, List<ScanLine>? after}) => ScanPage(
      800,
      1100,
      before ?? const [ScanLine('Sarlavha', 300, 500, 20, 50, 30)],
      table ?? sampleTable(),
      after ?? const [],
    );

Archive unzip(List<int> bytes) => ZipDecoder().decodeBytes(bytes);

String read(Archive a, String name) => utf8.decode(a.findFile(name)!.content as List<int>);

void main() {
  group('Word (.docx)', () {
    test('every part is well-formed XML and the document has a real table', () {
      final z = unzip(buildDocx([samplePage()]));
      for (final f in z.files) {
        expect(() => XmlDocument.parse(utf8.decode(f.content as List<int>)), returnsNormally, reason: f.name);
      }
      final doc = XmlDocument.parse(read(z, 'word/document.xml'));
      expect(doc.findAllElements('w:tbl'), hasLength(1));
      expect(doc.findAllElements('w:tr'), hasLength(4));
      expect(doc.findAllElements('w:gridCol'), hasLength(3));
    });

    test('merged cells use gridSpan / vMerge; every row covers all three grid columns', () {
      final doc = XmlDocument.parse(read(unzip(buildDocx([samplePage()])), 'word/document.xml'));
      expect(doc.findAllElements('w:gridSpan').map((e) => e.getAttribute('w:val')), ['2']);
      final vMerge = doc.findAllElements('w:vMerge').toList();
      expect(vMerge.where((e) => e.getAttribute('w:val') == 'restart'), hasLength(1));
      expect(vMerge.where((e) => e.getAttribute('w:val') == null), hasLength(1), reason: 'the continuation cell');
      for (final row in doc.findAllElements('w:tr')) {
        int cols = 0;
        for (final tc in row.findElements('w:tc')) {
          final span = tc.findAllElements('w:gridSpan').firstOrNull?.getAttribute('w:val');
          cols += int.parse(span ?? '1');
        }
        expect(cols, 3);
      }
    });

    test('text is escaped, rotated header cells keep their direction, headers repeat', () {
      final xml = read(unzip(buildDocx([samplePage(table: sampleTable(rotation: 90))])), 'word/document.xml');
      expect(xml, contains('Ali &amp; &quot;Vali&quot; &lt;B&gt;'));
      expect(xml, contains('w:textDirection w:val="btLr"'));
      expect(RegExp('<w:tblHeader/>').allMatches(xml).length, 2, reason: 'two header rows');
      expect(xml, contains('Sarlavha'));
    });

    test('pages are separated by a page break; the last page is not', () {
      final xml = read(unzip(buildDocx([samplePage(), samplePage()])), 'word/document.xml');
      expect(RegExp('w:br w:type="page"').allMatches(xml).length, 1);
      expect(RegExp('<w:tbl>').allMatches(xml).length, 2);
    });

    test('invalid control characters from OCR never break the file', () {
      final page = samplePage(table: sampleTable(name: 'A\u0000B\u0008C'));
      expect(() => XmlDocument.parse(read(unzip(buildDocx([page])), 'word/document.xml')), returnsNormally);
    });

    test('a wide scan makes a landscape document; no pages still gives a valid file', () {
      final wide = ScanPage(1200, 800, const [], sampleTable(), const []);
      expect(read(unzip(buildDocx([wide])), 'word/document.xml'), contains('w:orient="landscape"'));
      expect(() => XmlDocument.parse(read(unzip(buildDocx(const [])), 'word/document.xml')), returnsNormally);
    });

    test('long table text does not get a font too large to fit the original row heights', () {
      final cells = [
        for (int r = 0; r < 12; r++) ...[
          ScanCell(r, 0, 1, 1, 'AMONOVA MUHABBAT ABDULLAYEVNA QIZI'),
          ScanCell(r, 1, 1, 1, 'x'),
        ],
      ];
      // 1-ustun jadval enining 20% i, qator balandligi ~21 pt: matn 3 qatorga o'ralsa sig'maydi
      final table = ScanTable(const [200, 800], [for (int i = 0; i < 12; i++) 40.0], cells, 40);
      final xml = read(unzip(buildDocx([ScanPage(800, 1100, const [], table, const [])])), 'word/document.xml');
      final sizes = RegExp(r'<w:sz w:val="(\d+)"/>').allMatches(xml).map((m) => int.parse(m.group(1)!)).toSet();
      final biggest = sizes.reduce((a, b) => a > b ? a : b);
      expect(biggest, lessThanOrEqualTo(18), reason: 'shrunk from the 11pt start so two lines fit the row');
      expect(biggest, greaterThanOrEqualTo(13), reason: 'but not unreadably small');
    });
  });

  group('Excel (.xlsx)', () {
    test('every part is well-formed and the cells, merges and widths are there', () {
      final z = unzip(buildXlsx([samplePage()]));
      for (final f in z.files) {
        expect(() => XmlDocument.parse(utf8.decode(f.content as List<int>)), returnsNormally, reason: f.name);
      }
      final sheet = XmlDocument.parse(read(z, 'xl/worksheets/sheet1.xml'));
      // sarlavha qatori + 4 jadval qatori
      expect(sheet.findAllElements('row'), hasLength(5));
      final merges = sheet.findAllElements('mergeCell').map((e) => e.getAttribute('ref')).toSet();
      expect(merges, {'A1:C1', 'A2:A3', 'B2:C2'});
      expect(sheet.findAllElements('col'), hasLength(3));
      final xml = read(z, 'xl/worksheets/sheet1.xml');
      expect(xml, contains('Ali &amp; &quot;Vali&quot; &lt;B&gt;'));
    });

    test('plain whole numbers become numbers; header numbers and dates stay text', () {
      final xml = read(unzip(buildXlsx([samplePage()])), 'xl/worksheets/sheet1.xml');
      expect(xml, contains('<v>1</v>'));
      expect(xml, contains('<v>5</v>'));
      expect(xml, contains('19/11/2026'));
      expect(xml, isNot(contains('<v>19/11/2026</v>')));
    });

    test('rotated header cells use text rotation', () {
      final z = unzip(buildXlsx([samplePage(table: sampleTable(rotation: 90))]));
      expect(read(z, 'xl/styles.xml'), contains('textRotation="90"'));
    });

    test('a second page with the same repeated header continues the same sheet without the header', () {
      final z = unzip(buildXlsx([samplePage(before: const []), samplePage(before: const [])]));
      expect(z.files.where((f) => f.name.startsWith('xl/worksheets/')), hasLength(1));
      final sheet = XmlDocument.parse(read(z, 'xl/worksheets/sheet1.xml'));
      // 4 qator + 2 ta (sarlavhasiz) qator
      expect(sheet.findAllElements('row'), hasLength(6));
      expect(sheet.findAllElements('mergeCell'), hasLength(2), reason: 'the header merges are not repeated');
    });

    test('a different table gets its own sheet; a page without a table gets a text sheet', () {
      final other = ScanTable(const [100, 100], const [50, 50], const [
        ScanCell(0, 0, 1, 1, 'Mahsulot'),
        ScanCell(0, 1, 1, 1, 'Narx'),
        ScanCell(1, 0, 1, 1, 'Non'),
        ScanCell(1, 1, 1, 1, '5000'),
      ], 20);
      final textOnly = ScanPage(800, 1100, const [ScanLine('Faqat matn', 100, 300, 100, 130, 24)], null, const []);
      final z = unzip(buildXlsx([samplePage(), ScanPage(800, 1100, const [], other, const []), textOnly]));
      final names = XmlDocument.parse(read(z, 'xl/workbook.xml')).findAllElements('sheet').map((e) => e.getAttribute('name')).toList();
      expect(names, ['Jadval', 'Jadval 2', 'Matn 1']);
    });

    test('no pages still gives a valid workbook', () {
      final z = unzip(buildXlsx(const []));
      expect(() => XmlDocument.parse(read(z, 'xl/worksheets/sheet1.xml')), returnsNormally);
    });
  });
}
