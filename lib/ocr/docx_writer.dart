import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'scan_page.dart';
import 'xml_util.dart';

/// Skanerlangan sahifalardan Word (.docx) hujjati yaratadi: jadval haqiqiy Word jadvali bo'ladi
/// (birlashgan kataklar, ustun enlari, qator balandliklari saqlanadi), qolgan matn oddiy xatboshilar.
Uint8List buildDocx(List<ScanPage> pages) {
  final body = StringBuffer();
  final landscape = pages.isNotEmpty && pages.first.width > pages.first.height;
  final pageW = landscape ? 16838 : 11906, pageH = landscape ? 11906 : 16838;
  const margin = 720;
  final contentW = pageW - 2 * margin;

  for (int p = 0; p < pages.length; p++) {
    final page = pages[p];
    final table = page.table;
    // px -> pt: jadval bo'lsa, u sahifa eniga cho'ziladi; bo'lmasa sahifaning eni o'lchov bo'ladi
    final twipsPerPx = table != null ? contentW / table.width : contentW / page.width;
    final ptPerPx = twipsPerPx / 20;
    final bodyFont = table?.fontPx ?? _median([for (final l in [...page.before, ...page.after]) l.fontPx], 22);

    for (final line in page.before) {
      body.write(_paragraph(line, page.width, bodyFont, ptPerPx));
    }
    if (table != null) {
      body.write(_table(table, twipsPerPx, ptPerPx));
    }
    for (final line in page.after) {
      body.write(_paragraph(line, page.width, bodyFont, ptPerPx));
    }
    // jadvaldan keyin Word xatboshi talab qiladi; sahifalar orasida u sahifa uzilishini ham tashiydi
    final isLast = p == pages.length - 1;
    body.write(
      '<w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="20" w:lineRule="exact"/>'
      '<w:rPr><w:sz w:val="2"/></w:rPr></w:pPr>${isLast ? '' : '<w:r><w:br w:type="page"/></w:r>'}</w:p>',
    );
  }
  if (pages.isEmpty) body.write('<w:p/>');

  final document = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
      '<w:body>$body'
      '<w:sectPr><w:pgSz w:w="$pageW" w:h="$pageH"${landscape ? ' w:orient="landscape"' : ''}/>'
      '<w:pgMar w:top="$margin" w:right="$margin" w:bottom="$margin" w:left="$margin" w:header="360" w:footer="360" w:gutter="0"/>'
      '</w:sectPr></w:body></w:document>';

  const contentTypes = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
      '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
      '</Types>';
  const rootRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
      '</Relationships>';
  const docRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
      '</Relationships>';
  const styles = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
      '<w:docDefaults><w:rPrDefault><w:rPr>'
      '<w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:eastAsia="Times New Roman" w:cs="Times New Roman"/>'
      '<w:sz w:val="20"/><w:szCs w:val="20"/><w:lang w:val="uz-Latn-UZ"/></w:rPr></w:rPrDefault>'
      '<w:pPrDefault><w:pPr><w:spacing w:after="0" w:line="240" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults>'
      '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style>'
      '</w:styles>';

  final archive = Archive()
    ..addFile(_file('[Content_Types].xml', contentTypes))
    ..addFile(_file('_rels/.rels', rootRels))
    ..addFile(_file('word/document.xml', document))
    ..addFile(_file('word/_rels/document.xml.rels', docRels))
    ..addFile(_file('word/styles.xml', styles));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

ArchiveFile _file(String name, String content) => ArchiveFile.bytes(name, utf8.encode(content));

double _median(List<double> v, double fallback) {
  if (v.isEmpty) return fallback;
  final s = [...v]..sort();
  return s[s.length ~/ 2];
}

/// Shrift o'lchami (yarim punkt birligida), o'qiladigan oraliqda ushlanadi
int _halfPoints(double fontPx, double ptPerPx, {double min = 7, double max = 12}) {
  final pt = (fontPx * ptPerPx).clamp(min, max);
  return (pt * 2).round();
}

/// Matn qatorlarga o'ralganda balandligi asl qator balandligidan oshmaydigan eng katta shrift (yarim punkt).
/// OCR shrift o'lchamini aniq bilmaydi, shuning uchun taxminiy qiymatdan boshlab, jadval asl sahifaga
/// sig'maguncha kichraytiriladi.
int _fitFont(ScanTable table, List<int> widths, double twipsPerPx, double ptPerPx) {
  var pt = (table.fontPx * 0.92 * ptPerPx).clamp(6.5, 11.0).toDouble();
  final headerRows = table.headerRows;
  final dataRows = table.rowCount - headerRows;
  if (dataRows <= 0) return (pt * 2).round();
  for (; pt > 6.0; pt -= 0.25) {
    final tooTall = <int>{};
    for (final c in table.cells) {
      if (c.row < headerRows || c.rowSpan != 1 || c.rotation != 0 || c.text.isEmpty) continue;
      double widthTwips = 0;
      for (int i = c.col; i < c.col + c.colSpan && i < widths.length; i++) {
        widthTwips += widths[i];
      }
      final lines = _estimateLines(c.text, (widthTwips - 110) / 20, pt);
      final need = lines * pt * 1.17 + 2;
      final have = table.rowHeights[c.row] * twipsPerPx / 20;
      if (need > have * 1.04) tooTall.add(c.row);
    }
    if (tooTall.length <= math.max(1, (dataRows * 0.03).floor())) break;
  }
  return (pt * 2).round();
}

/// Matn [widthPt] kenglikda, [pt] o'lchamli shriftda nechta qatorga o'raladi (taxminan)
int _estimateLines(String text, double widthPt, double pt) {
  if (widthPt <= 0) return 99;
  double charWidth(String ch) {
    final c = ch.codeUnitAt(0);
    if (ch == ' ') return 0.25 * pt;
    if (c >= 65 && c <= 90) return 0.70 * pt; // bosh harflar
    if (c >= 48 && c <= 57) return 0.50 * pt;
    if (ch == 'i' || ch == 'l' || ch == 'j' || ch == 't' || ch == 'f' || ch == '.' || ch == ',' || ch == "'" || ch == '"') {
      return 0.30 * pt;
    }
    return 0.48 * pt;
  }

  int lines = 1;
  double used = 0;
  for (final word in text.split(' ')) {
    double w = 0;
    for (final ch in word.split('')) {
      w += charWidth(ch);
    }
    final space = used == 0 ? 0 : 0.25 * pt;
    if (used + space + w <= widthPt) {
      used += space + w;
    } else if (used == 0) {
      // bitta so'z qatorga sig'masa, qismlarga bo'linadi
      lines += (w / widthPt).floor();
      used = w % widthPt;
    } else {
      lines++;
      used = w;
      if (w > widthPt) {
        lines += (w / widthPt).floor();
        used = w % widthPt;
      }
    }
  }
  return lines;
}

String _paragraph(ScanLine line, int pageWidth, double bodyFontPx, double ptPerPx) {
  final center = (line.left + line.right) / 2;
  String align = 'left';
  if ((center - pageWidth / 2).abs() < pageWidth * 0.06) {
    align = 'center';
  } else if (line.left > pageWidth * 0.55) {
    align = 'right';
  }
  final bold = line.fontPx >= bodyFontPx * 1.12;
  final sz = _halfPoints(line.fontPx, ptPerPx, min: 8, max: 20);
  return '<w:p><w:pPr><w:spacing w:before="0" w:after="60"/><w:jc w:val="$align"/></w:pPr>'
      '<w:r><w:rPr>${bold ? '<w:b/><w:bCs/>' : ''}<w:sz w:val="$sz"/><w:szCs w:val="$sz"/></w:rPr>'
      '<w:t xml:space="preserve">${xmlEscape(line.text)}</w:t></w:r></w:p>';
}

String _table(ScanTable table, double twipsPerPx, double ptPerPx) {
  final cols = table.colCount, rows = table.rowCount;
  final widths = [for (final w in table.colWidths) math.max(200, (w * twipsPerPx).round())];
  final total = widths.fold<int>(0, (a, b) => a + b);
  final headerRows = table.headerRows;
  final sz = _fitFont(table, widths, twipsPerPx, ptPerPx);

  // har bir (qator, ustun) qaysi katakka tegishli
  final owner = List<List<ScanCell?>>.generate(rows, (_) => List<ScanCell?>.filled(cols, null));
  for (final c in table.cells) {
    for (int r = c.row; r < c.row + c.rowSpan && r < rows; r++) {
      for (int k = c.col; k < c.col + c.colSpan && k < cols; k++) {
        owner[r][k] = c;
      }
    }
  }

  final b = StringBuffer();
  b.write('<w:tbl><w:tblPr><w:tblW w:w="$total" w:type="dxa"/><w:jc w:val="center"/>'
      '<w:tblBorders>${['top', 'left', 'bottom', 'right', 'insideH', 'insideV'].map((e) => '<w:$e w:val="single" w:sz="4" w:space="0" w:color="000000"/>').join()}</w:tblBorders>'
      '<w:tblLayout w:type="fixed"/>'
      '<w:tblCellMar><w:top w:w="20" w:type="dxa"/><w:left w:w="50" w:type="dxa"/><w:bottom w:w="20" w:type="dxa"/><w:right w:w="50" w:type="dxa"/></w:tblCellMar>'
      '</w:tblPr><w:tblGrid>${widths.map((w) => '<w:gridCol w:w="$w"/>').join()}</w:tblGrid>');

  for (int r = 0; r < rows; r++) {
    final height = math.max(240, (table.rowHeights[r] * twipsPerPx).round());
    b.write('<w:tr><w:trPr><w:cantSplit/><w:trHeight w:val="$height" w:hRule="atLeast"/>${r < headerRows ? '<w:tblHeader/>' : ''}</w:trPr>');
    int k = 0;
    while (k < cols) {
      final cell = owner[r][k];
      if (cell == null) {
        // chiziqlar orasida katak topilmagan bo'shliq (kamdan-kam): bo'sh katak
        b.write('<w:tc><w:tcPr><w:tcW w:w="${widths[k]}" w:type="dxa"/></w:tcPr><w:p/></w:tc>');
        k++;
        continue;
      }
      final span = math.min(cell.colSpan, cols - cell.col);
      int width = 0;
      for (int i = cell.col; i < cell.col + span; i++) {
        width += widths[i];
      }
      final isContinuation = r > cell.row;
      final vMerge = cell.rowSpan > 1 ? (isContinuation ? '<w:vMerge/>' : '<w:vMerge w:val="restart"/>') : '';
      final direction = cell.rotation == 90 ? '<w:textDirection w:val="btLr"/>' : (cell.rotation == 270 ? '<w:textDirection w:val="tbRl"/>' : '');
      b.write('<w:tc><w:tcPr><w:tcW w:w="$width" w:type="dxa"/>${span > 1 ? '<w:gridSpan w:val="$span"/>' : ''}$vMerge$direction<w:vAlign w:val="center"/></w:tcPr>');
      final text = isContinuation ? '' : cell.text;
      final bold = r < headerRows && !isContinuation;
      if (text.isEmpty) {
        b.write('<w:p><w:pPr><w:spacing w:before="0" w:after="0"/><w:jc w:val="center"/><w:rPr><w:sz w:val="$sz"/><w:szCs w:val="$sz"/></w:rPr></w:pPr></w:p>');
      } else {
        b.write('<w:p><w:pPr><w:spacing w:before="0" w:after="0"/><w:jc w:val="center"/></w:pPr>'
            '<w:r><w:rPr>${bold ? '<w:b/><w:bCs/>' : ''}<w:sz w:val="$sz"/><w:szCs w:val="$sz"/></w:rPr>'
            '<w:t xml:space="preserve">${xmlEscape(text)}</w:t></w:r></w:p>');
      }
      b.write('</w:tc>');
      k += span;
    }
    b.write('</w:tr>');
  }
  b.write('</w:tbl>');
  return b.toString();
}
