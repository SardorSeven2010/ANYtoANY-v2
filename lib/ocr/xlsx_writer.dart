import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'scan_page.dart';
import 'xml_util.dart';

/// Skanerlangan sahifalardan Excel (.xlsx) fayli yaratadi. Jadval katakchalari, birlashgan kataklar va ustun enlari
/// saqlanadi. Bir xil ustunli jadvalning keyingi sahifalari (takrorlanuvchi sarlavhasi bilan) bitta varaqqa
/// davom qilib qo'shiladi.
Uint8List buildXlsx(List<ScanPage> pages) {
  final sheets = <_Sheet>[];
  _Sheet? current;
  ScanTable? currentTable;
  int textSheets = 0, tableSheets = 0;

  for (final page in pages) {
    final table = page.table;
    final continues = table != null &&
        current != null &&
        currentTable != null &&
        currentTable.colCount == table.colCount &&
        _headerSimilar(currentTable, table);

    if (table == null) {
      if (page.before.isEmpty && page.after.isEmpty) continue;
      // jadvalsiz sahifa: oldingi jadvalga tegmaymiz, alohida varaq
      current = _Sheet('Matn ${++textSheets}');
      sheets.add(current);
      currentTable = null;
      for (final line in [...page.before, ...page.after]) {
        current.addLine(line, page.width, 1, 12);
      }
      continue;
    }

    if (!continues) {
      current = _Sheet(tableSheets == 0 ? 'Jadval' : 'Jadval ${tableSheets + 1}');
      tableSheets++;
      sheets.add(current);
      currentTable = table;
    }
    final sheet = current;
    for (final line in page.before) {
      sheet.addLine(line, page.width, table.colCount, table.fontPx);
    }
    sheet.addTable(table, skipHeader: continues, pageWidth: page.width, pageHeight: page.height);
    for (final line in page.after) {
      sheet.addLine(line, page.width, table.colCount, table.fontPx);
    }
  }
  if (sheets.isEmpty) sheets.add(_Sheet('Jadval'));

  final styles = _Styles();
  final sheetXml = [for (final s in sheets) s.toXml(styles)];

  final contentTypes = StringBuffer('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
      '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>');
  final workbook = StringBuffer('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>');
  final workbookRels = StringBuffer('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">');
  for (int i = 0; i < sheets.length; i++) {
    contentTypes.write('<Override PartName="/xl/worksheets/sheet${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>');
    workbook.write('<sheet name="${xmlEscape(sheets[i].name)}" sheetId="${i + 1}" r:id="rId${i + 1}"/>');
    workbookRels.write('<Relationship Id="rId${i + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet${i + 1}.xml"/>');
  }
  contentTypes.write('</Types>');
  workbook.write('</sheets></workbook>');
  workbookRels.write('<Relationship Id="rId${sheets.length + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>');

  const rootRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
      '</Relationships>';

  final archive = Archive()
    ..addFile(_file('[Content_Types].xml', contentTypes.toString()))
    ..addFile(_file('_rels/.rels', rootRels))
    ..addFile(_file('xl/workbook.xml', workbook.toString()))
    ..addFile(_file('xl/_rels/workbook.xml.rels', workbookRels.toString()))
    ..addFile(_file('xl/styles.xml', styles.toXml()));
  for (int i = 0; i < sheetXml.length; i++) {
    archive.addFile(_file('xl/worksheets/sheet${i + 1}.xml', sheetXml[i]));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

ArchiveFile _file(String name, String content) => ArchiveFile.bytes(name, utf8.encode(content));

/// Keyingi sahifaning sarlavhasi oldingisinikiga o'xshashmi (OCR xatolari hisobga olinadi)
bool _headerSimilar(ScanTable a, ScanTable b) {
  Set<String> tokens(ScanTable t) {
    final out = <String>{};
    for (final c in t.cells) {
      if (c.row < t.headerRows) {
        for (final w in c.text.toLowerCase().split(RegExp(r'[^a-z0-9]+'))) {
          if (w.length >= 2) out.add(w);
        }
      }
    }
    return out;
  }

  final x = tokens(a), y = tokens(b);
  if (x.isEmpty || y.isEmpty) return true; // sarlavha o'qilmagan: ustunlar soni bir xil bo'lsa, davomi deb olinadi
  final common = x.intersection(y).length;
  return common / x.union(y).length >= 0.4;
}

class _Cell {
  final String text;
  final String style;
  final bool numeric;
  const _Cell(this.text, this.style, this.numeric);
}

class _Merge {
  final int r0, c0, r1, c1;
  const _Merge(this.r0, this.c0, this.r1, this.c1);
}

class _Sheet {
  _Sheet(this.name);

  final String name;
  final Map<int, Map<int, _Cell>> _cells = {};
  final List<_Merge> _merges = [];
  final Map<int, double> _rowHeights = {};
  List<double> colWidths = [];
  int _row = 0; // keyingi bo'sh qator (0 dan)
  int _maxCol = 1;


  /// Jadvaldan tashqaridagi matn qatori: ustunlar bo'ylab birlashtiriladi
  void addLine(ScanLine line, int pageWidth, int cols, double bodyFontPx) {
    final center = (line.left + line.right) / 2;
    String align = 'left';
    if ((center - pageWidth / 2).abs() < pageWidth * 0.06) {
      align = 'center';
    } else if (line.left > pageWidth * 0.55) {
      align = 'right';
    }
    final bold = line.fontPx >= bodyFontPx * 1.12;
    final key = _StyleKey(border: false, bold: bold, align: align, wrap: false, rotation: 0);
    _cells.putIfAbsent(_row, () => {})[0] = _Cell(line.text, _StyleKey.register(key), false);
    if (cols > 1) _merges.add(_Merge(_row, 0, _row, cols - 1));
    _maxCol = math.max(_maxCol, cols);
    _row++;
  }

  void addTable(ScanTable table, {required bool skipHeader, required int pageWidth, required int pageHeight}) {
    final cols = table.colCount;
    _maxCol = math.max(_maxCol, cols);
    if (colWidths.length < cols) {
      // ustun enlari: jadvalning umumiy eni ~140 belgi
      final total = table.width;
      colWidths = [for (final w in table.colWidths) (w / total * 140).clamp(4.0, 60.0)];
    }
    final header = table.headerRows;
    final first = skipHeader ? header : 0;
    final base = _row;
    final ptPerPx = 595.0 / pageWidth;
    for (final c in table.cells) {
      if (c.row < first) continue;
      final r = base + c.row - first;
      final isHeader = c.row < header;
      final align = 'center';
      final key = _StyleKey(
        border: true,
        bold: isHeader,
        align: align,
        wrap: true,
        // pastdan yuqoriga: 90, yuqoridan pastga (soat mili bo'yicha 90): 180
        rotation: c.rotation == 90 ? 90 : (c.rotation == 270 ? 180 : 0),
      );
      final style = _StyleKey.register(key);
      final numeric = !isHeader && RegExp(r'^[1-9][0-9]{0,8}$').hasMatch(c.text);
      _cells.putIfAbsent(r, () => {})[c.col] = _Cell(c.text, style, numeric);
      // birlashgan katakning qolgan qismlari ham chiziqli bo'lishi uchun
      for (int rr = 0; rr < c.rowSpan; rr++) {
        for (int cc = 0; cc < c.colSpan; cc++) {
          if (rr == 0 && cc == 0) continue;
          if (c.row + rr < first) continue;
          _cells.putIfAbsent(base + c.row + rr - first, () => {}).putIfAbsent(c.col + cc, () => _Cell('', style, false));
        }
      }
      if (c.rowSpan > 1 || c.colSpan > 1) {
        final r1 = base + c.row + c.rowSpan - 1 - first;
        _merges.add(_Merge(r, c.col, r1, c.col + c.colSpan - 1));
      }
      if (c.rotation != 0) {
        final h = table.rowHeights[c.row] / c.rowSpan * ptPerPx;
        _rowHeights[r] = math.max(_rowHeights[r] ?? 0, h);
      }
    }
    _row = base + table.rowCount - first;
  }

  String toXml(_Styles styles) {
    final b = StringBuffer('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">');
    if (colWidths.isNotEmpty) {
      b.write('<cols>');
      for (int i = 0; i < colWidths.length; i++) {
        b.write('<col min="${i + 1}" max="${i + 1}" width="${colWidths[i].toStringAsFixed(2)}" customWidth="1"/>');
      }
      b.write('</cols>');
    }
    b.write('<sheetData>');
    final rows = _cells.keys.toList()..sort();
    for (final r in rows) {
      final ht = _rowHeights[r];
      b.write('<row r="${r + 1}"${ht != null ? ' ht="${ht.toStringAsFixed(1)}" customHeight="1"' : ''}>');
      final cols = _cells[r]!.keys.toList()..sort();
      for (final c in cols) {
        final cell = _cells[r]![c]!;
        final ref = '${_columnName(c)}${r + 1}';
        final s = styles.indexFor(cell.style);
        if (cell.text.isEmpty) {
          b.write('<c r="$ref" s="$s"/>');
        } else if (cell.numeric) {
          b.write('<c r="$ref" s="$s"><v>${cell.text}</v></c>');
        } else {
          b.write('<c r="$ref" s="$s" t="inlineStr"><is><t xml:space="preserve">${xmlEscape(cell.text)}</t></is></c>');
        }
      }
      b.write('</row>');
    }
    b.write('</sheetData>');
    if (_merges.isNotEmpty) {
      b.write('<mergeCells count="${_merges.length}">');
      for (final m in _merges) {
        b.write('<mergeCell ref="${_columnName(m.c0)}${m.r0 + 1}:${_columnName(m.c1)}${m.r1 + 1}"/>');
      }
      b.write('</mergeCells>');
    }
    b.write('<pageMargins left="0.5" right="0.5" top="0.6" bottom="0.6" header="0.3" footer="0.3"/>');
    b.write('<pageSetup paperSize="9" orientation="landscape" fitToHeight="0"/>');
    b.write('</worksheet>');
    return b.toString();
  }
}

String _columnName(int index) {
  var n = index + 1;
  final out = StringBuffer();
  final letters = <String>[];
  while (n > 0) {
    final rem = (n - 1) % 26;
    letters.add(String.fromCharCode(65 + rem));
    n = (n - 1) ~/ 26;
  }
  for (final l in letters.reversed) {
    out.write(l);
  }
  return out.toString();
}

/// Katak uslubining kaliti (bir xil uslublar bir marta yoziladi)
class _StyleKey {
  final bool border, bold, wrap;
  final String align;
  final int rotation;
  const _StyleKey({required this.border, required this.bold, required this.align, required this.wrap, required this.rotation});

  String get id => '${border ? 1 : 0}${bold ? 1 : 0}${wrap ? 1 : 0}$align$rotation';

  static final Map<String, _StyleKey> _all = {};
  static String register(_StyleKey key) {
    _all[key.id] = key;
    return key.id;
  }
}

class _Styles {
  /// Uslub kaliti -> cellXfs tartib raqami (0 - oddiy uslub)
  final Map<String, int> _index = {};

  int indexFor(String id) => _index.putIfAbsent(id, () => _index.length + 1);

  String toXml() {
    final b = StringBuffer('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<fonts count="2">'
        '<font><sz val="10"/><name val="Times New Roman"/></font>'
        '<font><b/><sz val="10"/><name val="Times New Roman"/></font>'
        '</fonts>'
        '<fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>'
        '<borders count="2">'
        '<border><left/><right/><top/><bottom/><diagonal/></border>'
        '<border><left style="thin"><color auto="1"/></left><right style="thin"><color auto="1"/></right>'
        '<top style="thin"><color auto="1"/></top><bottom style="thin"><color auto="1"/></bottom><diagonal/></border>'
        '</borders>'
        '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
        '<cellXfs count="${_index.length + 1}">'
        '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>');
    final ordered = _index.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
    for (final e in ordered) {
      final k = _StyleKey._all[e.key]!;
      b.write('<xf numFmtId="0" fontId="${k.bold ? 1 : 0}" fillId="0" borderId="${k.border ? 1 : 0}" xfId="0" '
          'applyFont="1" applyBorder="1" applyAlignment="1">'
          '<alignment horizontal="${k.align}" vertical="center"${k.wrap ? ' wrapText="1"' : ''}${k.rotation != 0 ? ' textRotation="${k.rotation}"' : ''}/>'
          '</xf>');
    }
    b.write('</cellXfs>'
        '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
        '</styleSheet>');
    return b.toString();
  }
}
