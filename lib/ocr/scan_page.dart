import 'dart:math' as math;

import 'package:image/image.dart' as img;

import 'ocr_types.dart';
import 'table_detector.dart';

/// Jadvaldan tashqaridagi matn qatori (sarlavha, izoh...)
class ScanLine {
  final String text;
  final double left, right, top, bottom;

  /// Taxminiy shrift o'lchami (piksel)
  final double fontPx;
  const ScanLine(this.text, this.left, this.right, this.top, this.bottom, this.fontPx);
}

/// Jadval katakchasi. [rotation]: matn burilgan bo'lsa 90 (pastdan yuqoriga o'qiladi) yoki 270 (yuqoridan pastga).
class ScanCell {
  final int row, col, rowSpan, colSpan;
  final String text;
  final int rotation;
  const ScanCell(this.row, this.col, this.rowSpan, this.colSpan, this.text, {this.rotation = 0});
}

class ScanTable {
  /// Ustun enlari va qator balandliklari (piksel)
  final List<double> colWidths, rowHeights;
  final List<ScanCell> cells;

  /// Jadval matnining taxminiy shrift o'lchami (piksel)
  final double fontPx;
  const ScanTable(this.colWidths, this.rowHeights, this.cells, this.fontPx);

  int get colCount => colWidths.length;
  int get rowCount => rowHeights.length;
  double get width => colWidths.fold(0, (a, b) => a + b);
  double get height => rowHeights.fold(0, (a, b) => a + b);

  /// Sarlavha qatorlari soni: birinchi qatordan boshlangan eng baland birlashgan katak bo'yicha
  int get headerRows {
    int n = 1;
    for (final c in cells) {
      if (c.row == 0 && c.rowSpan > n) n = c.rowSpan;
    }
    return math.min(n, rowCount);
  }

  /// Katakning matnini qaytaradi (birlashgan katakning boshlanish joyida)
  String textAt(int row, int col) {
    for (final c in cells) {
      if (c.row == row && c.col == col) return c.text;
    }
    return '';
  }
}

/// Bitta skaner qilingan sahifa: jadvaldan oldingi matn, jadval, jadvaldan keyingi matn.
class ScanPage {
  final int width, height;
  final List<ScanLine> before, after;
  final ScanTable? table;
  const ScanPage(this.width, this.height, this.before, this.table, this.after);

  bool get isEmpty => before.isEmpty && after.isEmpty && table == null;
}

/// Kesilgan (kerak bo'lsa burilgan) rasm bo'lagidagi so'zlarni tanish
typedef CropRecognizer = Future<List<OcrWord>> Function(img.Image crop, {bool lineMode});

/// Sahifa geometriyasi: qiyshiqlik, jadval to'ri va har bir katakda siyoh bor-yo'qligi.
/// Og'ir hisob-kitob, shuning uchun alohida oqimda ([Isolate.run]) bajarilishi mumkin: natija oddiy ma'lumotlardan iborat.
class PageGeometry {
  final Deskew deskew;
  final TableGrid? grid;

  /// [grid] kataklari tartibida: katak ichida (chekkasidan tashqari) qora piksellar bormi
  final List<bool> cellInk;
  const PageGeometry(this.deskew, this.grid, this.cellInk);
}

PageGeometry analyzeGeometry(img.Image image) {
  final mask = DarkMask.fromImage(image);
  final deskew = estimateDeskew(mask);
  final straight = deskew.apply(mask);
  final grid = detectTable(straight);
  final ink = <bool>[];
  if (grid != null) {
    for (final g in grid.cells) {
      ink.add(hasInk(straight, grid.xs[g.col], grid.ys[g.row], grid.xs[g.col + g.colSpan], grid.ys[g.row + g.rowSpan]));
    }
  }
  return PageGeometry(deskew, grid, ink);
}

/// Rasm va uning so'zlaridan sahifa tuzadi: jadval chiziqlari bo'yicha so'zlar kataklarga joylanadi.
/// Jadval topilmasa, faqat matn qatorlari qaytadi. [geometry] ni [analyzeGeometry] beradi.
Future<ScanPage> buildScanPage({
  required img.Image image,
  required PageGeometry geometry,
  required List<OcrWord> words,
  required CropRecognizer recognizeCrop,
  double fontFactor = 1.0,
}) async {
  final deskew = geometry.deskew;
  final grid = geometry.grid;

  // so'zlar to'g'rilangan koordinatalarga o'tkaziladi, keraksiz belgilar tashlanadi
  final mapped = <OcrWord>[];
  for (final w in words) {
    if (!_worthKeeping(w)) continue;
    final (cx, cy) = deskew.forward(w.cx, w.cy);
    mapped.add(OcrWord(w.text, cx - w.width / 2, cy - w.height / 2, cx + w.width / 2, cy + w.height / 2,
        confidence: w.confidence));
  }

  if (grid == null) {
    return ScanPage(image.width, image.height, _toLines([for (final w in mapped) if (w.confidence >= 0.5) w], fontFactor), null, const []);
  }

  final inside = <int, List<OcrWord>>{}; // GridCell indeksi -> so'zlar
  final outsideBefore = <OcrWord>[], outsideAfter = <OcrWord>[];
  final cellIndex = <GridCell, int>{
    for (int i = 0; i < grid.cells.length; i++) grid.cells[i]: i,
  };
  for (final w in mapped) {
    final col = grid.colOf(w.cx), row = grid.rowOf(w.cy);
    final cell = (col < 0 || row < 0) ? null : grid.cellAt(row, col);
    if (cell == null) {
      // jadvaldan tashqarida ishonchsiz so'zlar (muhr, dog') tashlanadi
      if (w.confidence < 0.5) continue;
      (w.cy < grid.top ? outsideBefore : outsideAfter).add(w);
    } else {
      inside.putIfAbsent(cellIndex[cell]!, () => []).add(w);
    }
  }

  final count = grid.cells.length;
  final texts = <String>[for (int i = 0; i < count; i++) _joinWords(inside[i] ?? const <OcrWord>[])];
  final rotations = List<int>.filled(count, 0);
  final heights = <double>[
    for (final list in inside.values)
      for (final w in list) w.height,
  ];
  double left(GridCell g) => grid.xs[g.col];
  double right(GridCell g) => grid.xs[g.col + g.colSpan];
  double top(GridCell g) => grid.ys[g.row];
  double bottom(GridCell g) => grid.ys[g.row + g.rowSpan];

  int headerRows = 1;
  for (final g in grid.cells) {
    if (g.row == 0 && g.rowSpan > headerRows) headerRows = g.rowSpan;
  }

  // Tanilmagan, lekin ichida siyoh bor kataklar: OCR umumiy sahifada yakka raqam, qisqa so'z yoki burilgan matnni
  // o'tkazib yuborgan. Ular alohida kesib, kerak bo'lsa burib qayta o'qiladi.
  final needsRecovery = <int>[];
  for (int i = 0; i < count; i++) {
    final weak = _score(texts[i]) < 2 || _looksRotated(inside[i] ?? const []);
    if (weak && geometry.cellInk[i]) needsRecovery.add(i);
  }

  final rotatedRows = <int>{};
  // [force]: mavjud matn zaif bo'lmasa ham, yangi o'qish ancha yaxshi chiqsa almashtiriladi
  Future<void> recover(int i, List<int> angles) async {
    final g = grid.cells[i];
    final current = _quality(texts[i], inside[i] ?? const []);
    final result = await _readCrop(image, deskew, left(g), top(g), right(g), bottom(g), angles, recognizeCrop);
    if (result == null || result.$3 <= current) return;
    texts[i] = result.$1;
    rotations[i] = result.$2;
    if (result.$2 != 0) rotatedRows.add(g.row);
  }

  for (final i in needsRecovery) {
    final g = grid.cells[i];
    final tall = (bottom(g) - top(g)) >= (right(g) - left(g)) * 1.3;
    await recover(i, (tall || g.row < headerRows) ? const [0, 90, 270] : const [0]);
  }
  // shu qatordagi boshqa kataklar ham xuddi shunday burilgan bo'lishi mumkin (kengroq katak bo'lgani uchun
  // yuqoridagi shart ularni o'tkazib yuborgan yoki OCR u yerda tasodifiy harf topgan bo'lishi mumkin)
  for (int i = 0; i < count; i++) {
    final g = grid.cells[i];
    if (rotations[i] != 0 || g.rowSpan > 1 && g.row == 0 || !rotatedRows.contains(g.row) || !geometry.cellInk[i]) continue;
    if (_score(texts[i]) >= 6) continue; // oddiy uzun matn: burilgan sana emas
    await recover(i, const [90, 270]);
  }

  // OCR qoldirgan shovqin: harfsiz katak bo'sh, kam to'ldirilgan ustunda ishonchsiz qisqa belgilar tashlanadi
  for (int i = 0; i < count; i++) {
    if (_score(texts[i]) == 0) texts[i] = '';
  }
  for (int col = 0; col < grid.colCount; col++) {
    final column = <int>[
      for (int i = 0; i < count; i++)
        if (grid.cells[i].col == col && grid.cells[i].colSpan == 1 && grid.cells[i].row >= headerRows) i,
    ];
    if (column.length < 6) continue;
    final filled = column.where((i) => texts[i].isNotEmpty).length;
    if (filled > column.length * 0.2) continue;
    for (final i in column) {
      final words = inside[i] ?? const <OcrWord>[];
      final confidence = words.isEmpty ? 1.0 : words.fold<double>(0, (a, w) => a + w.confidence) / words.length;
      if (texts[i].isNotEmpty && rotations[i] == 0 && _score(texts[i]) <= 3 && confidence < 0.8) texts[i] = '';
    }
  }

  final cells = <ScanCell>[
    for (int i = 0; i < count; i++)
      ScanCell(grid.cells[i].row, grid.cells[i].col, grid.cells[i].rowSpan, grid.cells[i].colSpan, texts[i],
          rotation: rotations[i]),
  ];
  final colWidths = [for (int i = 0; i < grid.colCount; i++) grid.xs[i + 1] - grid.xs[i]];
  final rowHeights = [for (int i = 0; i < grid.rowCount; i++) grid.ys[i + 1] - grid.ys[i]];
  final table = ScanTable(colWidths, rowHeights, cells, _median(heights, fallback: 20) * fontFactor);
  return ScanPage(image.width, image.height, _toLines(outsideBefore, fontFactor), table, _toLines(outsideAfter, fontFactor));
}

/// OCR ba'zan chiziqlarni "|" yoki yakka nuqta deb o'qiydi: bunday belgilar tashlanadi
bool _worthKeeping(OcrWord w) {
  final t = w.text.trim();
  if (t.isEmpty) return false;
  if (t == '-' || t == '–') return w.confidence > 0.5;
  return !RegExp(r'^[|_\[\]{}~`\\/\-–—.,:;·•]{1,3}$').hasMatch(t);
}

/// Katak ichida (chekkasidan biroz ichkarida) qora piksellar bormi
bool hasInk(DarkMask m, double left, double top, double right, double bottom) {
  const inset = 6;
  final x0 = (left + inset).round(), x1 = (right - inset).round();
  final y0 = (top + inset).round(), y1 = (bottom - inset).round();
  if (x1 <= x0 || y1 <= y0) return false;
  int dark = 0;
  for (int y = math.max(0, y0); y < math.min(m.height, y1); y++) {
    for (int x = math.max(0, x0); x < math.min(m.width, x1); x++) {
      if (m.dark[y * m.width + x] == 1) dark++;
    }
  }
  final area = (x1 - x0) * (y1 - y0);
  return dark >= 25 && dark >= area * 0.003;
}

bool _looksRotated(List<OcrWord> words) {
  if (words.isEmpty) return false;
  int tall = 0;
  for (final w in words) {
    if (w.text.length >= 3 && w.height > w.width * 1.2) tall++;
  }
  return tall * 2 >= words.length;
}

/// Katak rasmini kesib, berilgan burchaklarda (0, 90, 270) tanib ko'radi; eng yaxshi natija tanlanadi.
/// Qaytadi: (matn, burchak, baho). 90 - rasm soat mili bo'yicha burilganda o'qildi, ya'ni asl matn pastdan yuqoriga yozilgan.
Future<(String, int, double)?> _readCrop(
  img.Image image,
  Deskew deskew,
  double left,
  double top,
  double right,
  double bottom,
  List<int> angles,
  CropRecognizer recognize,
) async {
  // to'g'rilangan koordinatadan asl rasmga (taxminan) qaytish
  final inverse = Deskew(-deskew.phi, deskew.cx, deskew.cy);
  final (cx, cy) = inverse.forward((left + right) / 2, (top + bottom) / 2);
  const inset = 7.0;
  final w = (right - left - 2 * inset).round(), h = (bottom - top - 2 * inset).round();
  if (w < 10 || h < 10) return null;
  final x0 = (cx - w / 2).round().clamp(0, image.width - 1), y0 = (cy - h / 2).round().clamp(0, image.height - 1);
  final crop = img.copyCrop(image, x: x0, y: y0, width: math.min(w, image.width - x0), height: math.min(h, image.height - y0));

  String best = '';
  double bestQuality = 0;
  int bestAngle = 0;
  for (final angle in angles) {
    // (kulrang rasm uch kanalli maydonga qo'yilganda qizil bo'lib qolmasligi uchun avval 3 kanalga o'tkaziladi)
    final turned = (angle == 0 ? crop : img.copyRotate(crop, angle: angle)).convert(numChannels: 3);
    // atrofiga oq maydon qo'shiladi: OCR chetga tegib turgan matnni yomon o'qiydi
    final padded = img.Image(width: turned.width + 40, height: turned.height + 40, numChannels: 3);
    img.fill(padded, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(padded, turned, dstX: 20, dstY: 20);
    final found = [for (final f in await recognize(padded, lineMode: true)) if (_worthKeeping(f)) f];
    final text = _joinWords(found);
    // burilmagan o'qish biroz afzal: sarlavhalar ko'pincha oddiy yoziladi
    final quality = _quality(text, found) * (angle == 0 ? 1.15 : 1);
    if (quality > bestQuality) {
      best = text;
      bestQuality = quality;
      bestAngle = angle;
    }
  }
  if (_score(best) < 1 || bestQuality <= 0) return null;
  return (best, bestAngle, bestQuality);
}

int _score(String s) => RegExp(r'[A-Za-z0-9]').allMatches(s).length;

/// Variantlardan qaysi biri to'g'ri o'qilganini tanlash uchun baho: ishonchlilik ustiga, harf bilan raqam
/// aralashib ketgan bo'laklar (teskari o'qilgan matn belgisi, masalan "9ZO0Z") ayirib tashlanadi.
double _quality(String text, List<OcrWord> words) {
  if (words.isEmpty) return 0;
  final confidence = words.fold<double>(0, (a, w) => a + w.confidence) / words.length;
  double mixed = 0;
  for (final chunk in text.split(RegExp(r'[^A-Za-z0-9]+'))) {
    if (chunk.length > 1 && RegExp(r'[A-Za-z]').hasMatch(chunk) && RegExp(r'[0-9]').hasMatch(chunk)) mixed++;
  }
  return _score(text) * confidence - mixed * 4;
}

double _median(List<double> v, {required double fallback}) {
  if (v.isEmpty) return fallback;
  final s = [...v]..sort();
  return s[s.length ~/ 2];
}

/// So'zlarni qatorlarga ajratadi (yuqoridan pastga, chapdan o'ngga) va bo'shliq bilan birlashtiradi
String _joinWords(List<OcrWord> words) {
  if (words.isEmpty) return '';
  final lines = _cluster(words);
  return lines.map((l) => l.map((w) => w.text).join(' ')).join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Bir qatordagi so'zlar guruhlari (y bo'yicha)
List<List<OcrWord>> _cluster(List<OcrWord> words) {
  final sorted = [...words]..sort((a, b) => a.cy.compareTo(b.cy));
  final tolerance = _median([for (final w in words) w.height], fallback: 20) * 0.6;
  final lines = <List<OcrWord>>[];
  double lineCy = 0;
  for (final w in sorted) {
    if (lines.isNotEmpty && (w.cy - lineCy).abs() <= tolerance) {
      lines.last.add(w);
      final all = lines.last;
      lineCy = all.fold<double>(0, (a, b) => a + b.cy) / all.length;
    } else {
      lines.add([w]);
      lineCy = w.cy;
    }
  }
  for (final l in lines) {
    l.sort((a, b) => a.left.compareTo(b.left));
  }
  return lines;
}

/// Jadvaldan tashqaridagi so'zlardan qatorlar tuzadi. Orasi juda katta bo'lgan so'zlar alohida qator bo'ladi
/// (masalan, chapdagi sarlavha va o'ngdagi imzo).
List<ScanLine> _toLines(List<OcrWord> words, double fontFactor) {
  if (words.isEmpty) return const [];
  final result = <ScanLine>[];
  for (final line in _cluster(words)) {
    final h = _median([for (final w in line) w.height], fallback: 20);
    final segments = <List<OcrWord>>[[line.first]];
    for (int i = 1; i < line.length; i++) {
      if (line[i].left - line[i - 1].right > h * 3.5) {
        segments.add([line[i]]);
      } else {
        segments.last.add(line[i]);
      }
    }
    for (final seg in segments) {
      final text = seg.map((w) => w.text).join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
      if (_score(text) < 3) continue; // "i", "|-" kabi qoldiqlar
      result.add(ScanLine(
        text,
        seg.map((w) => w.left).reduce(math.min),
        seg.map((w) => w.right).reduce(math.max),
        seg.map((w) => w.top).reduce(math.min),
        seg.map((w) => w.bottom).reduce(math.max),
        _median([for (final w in seg) w.height], fallback: h) * fontFactor,
      ));
    }
  }
  return result;
}
