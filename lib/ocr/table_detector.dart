import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Rasmning qora / och piksellari (1 = qora). Jadval chiziqlarini topish shu ustida ishlaydi.
class DarkMask {
  DarkMask(this.width, this.height, this.dark);

  final int width;
  final int height;
  final Uint8List dark;

  /// Rasmni qora-oq qiladi. Chegara Otsu usuli bilan topiladi va chiziqlar uchun mos oraliqda ushlanadi.
  factory DarkMask.fromImage(img.Image image) {
    final w = image.width, h = image.height;
    final rgb = image.convert(numChannels: 3).getBytes(order: img.ChannelOrder.rgb);
    final gray = Uint8List(w * h);
    final hist = List<int>.filled(256, 0);
    for (int i = 0, j = 0; i < gray.length; i++, j += 3) {
      final v = (rgb[j] * 299 + rgb[j + 1] * 587 + rgb[j + 2] * 114) ~/ 1000;
      gray[i] = v;
      hist[v]++;
    }
    final t = _otsu(hist, gray.length).clamp(100, 175);
    final dark = Uint8List(w * h);
    for (int i = 0; i < gray.length; i++) {
      if (gray[i] < t) dark[i] = 1;
    }
    return DarkMask(w, h, dark);
  }

  static int _otsu(List<int> hist, int total) {
    double sum = 0;
    for (int i = 0; i < 256; i++) {
      sum += i * hist[i];
    }
    double sumB = 0, best = -1;
    int wB = 0, threshold = 128;
    for (int t = 0; t < 256; t++) {
      wB += hist[t];
      if (wB == 0) continue;
      final wF = total - wB;
      if (wF == 0) break;
      sumB += t * hist[t];
      final mB = sumB / wB, mF = (sum - sumB) / wF;
      final between = wB.toDouble() * wF * (mB - mF) * (mB - mF);
      if (between > best) {
        best = between;
        threshold = t;
      }
    }
    return threshold;
  }
}

/// Sahifaning biroz qiyshiq skanerlanganini to'g'rilash: kichik burchak ([phi], radianlarda) va aylanish markazi.
/// Faqat qora-oq niqob aylantiriladi; OCR so'zlarining joylari [forward] bilan shu koordinatalarga o'tkaziladi.
class Deskew {
  const Deskew(this.phi, this.cx, this.cy);

  /// Sahifa shu burchakka burilgan (soat miliga qarshi musbat emas: ichki kelishuv, [forward] bilan mos)
  final double phi;
  final double cx, cy;

  bool get isIdentity => phi == 0;

  /// Asl rasm koordinatasidan to'g'rilangan koordinataga
  (double, double) forward(double x, double y) {
    if (isIdentity) return (x, y);
    final u = x - cx, v = y - cy;
    final c = math.cos(phi), s = math.sin(phi);
    return (u * c + v * s + cx, -u * s + v * c + cy);
  }

  /// To'g'rilangan niqob: har bir yangi piksel uchun asl niqobdan nusxa olinadi
  DarkMask apply(DarkMask m) {
    if (isIdentity) return m;
    final w = m.width, h = m.height;
    final out = Uint8List(w * h);
    final c = math.cos(phi), s = math.sin(phi);
    for (int y = 0; y < h; y++) {
      final v = y - cy;
      for (int x = 0; x < w; x++) {
        final u = x - cx;
        final sx = (u * c - v * s + cx).round();
        final sy = (u * s + v * c + cy).round();
        if (sx >= 0 && sx < w && sy >= 0 && sy < h && m.dark[sy * w + sx] == 1) out[y * w + x] = 1;
      }
    }
    return DarkMask(w, h, out);
  }
}

/// Vertikal chiziqlarning qiyshayishini topadi: to'g'ri sahifada chiziqlar bir ustunga tushadi.
/// Aniq chiziq topilmasa yoki sahifa deyarli to'g'ri bo'lsa, o'zgarishsiz ([Deskew.isIdentity]) qaytadi.
Deskew estimateDeskew(DarkMask m) {
  final w = m.width, h = m.height;
  final cx = w / 2, cy = h / 2;
  final dark = m.dark;
  // vertikal chiziq bo'lagiga o'xshash piksellar: yuqorisi va pastidagi qo'shnilari ham qora
  final xsList = <int>[], ysList = <int>[];
  for (int y = 2; y < h - 2; y += 2) {
    final row = y * w;
    for (int x = 0; x < w; x++) {
      if (dark[row + x] == 1 && dark[row - 2 * w + x] == 1 && dark[row + 2 * w + x] == 1) {
        xsList.add(x);
        ysList.add(y);
      }
    }
  }
  if (xsList.length < 2000) return Deskew(0, cx, cy);

  final hist = List<int>.filled(w + 2 * 200, 0);
  double score(double t) {
    hist.fillRange(0, hist.length, 0);
    for (int i = 0; i < xsList.length; i++) {
      final x = (xsList[i] - t * (ysList[i] - cy)).round() + 200;
      if (x >= 0 && x < hist.length) hist[x]++;
    }
    double sum = 0;
    for (final v in hist) {
      sum += v.toDouble() * v;
    }
    return sum;
  }

  double best = 0, bestScore = score(0);
  final base = bestScore;
  // qo'pol qidiruv, so'ng aniqlashtirish
  for (double t = -0.03; t <= 0.03; t += 0.001) {
    final sc = score(t);
    if (sc > bestScore) {
      bestScore = sc;
      best = t;
    }
  }
  final center = best;
  for (double t = center - 0.001; t <= center + 0.001; t += 0.0001) {
    final sc = score(t);
    if (sc > bestScore) {
      bestScore = sc;
      best = t;
    }
  }
  if (best.abs() < 0.0006 || bestScore < base * 1.1) return Deskew(0, cx, cy);
  return Deskew(-math.atan(best), cx, cy);
}

/// Jadvalning birlashgan katakchasi: [row], [col] - chap yuqori burchagi, [rowSpan] / [colSpan] - nechta katak egallaydi.
class GridCell {
  final int row, col, rowSpan, colSpan;
  const GridCell(this.row, this.col, this.rowSpan, this.colSpan);

  @override
  String toString() => 'GridCell($row,$col ${rowSpan}x$colSpan)';
}

/// Topilgan jadval: ustun / qator chiziqlarining piksel joylari va birlashgan kataklar.
class TableGrid {
  /// Ustun chegaralari (chapdan o'ngga), [colCount] + 1 ta
  final List<double> xs;

  /// Qator chegaralari (yuqoridan pastga), [rowCount] + 1 ta
  final List<double> ys;
  final List<GridCell> cells;
  const TableGrid(this.xs, this.ys, this.cells);

  int get colCount => xs.length - 1;
  int get rowCount => ys.length - 1;
  double get left => xs.first;
  double get right => xs.last;
  double get top => ys.first;
  double get bottom => ys.last;

  /// (satr, ustun) joyi qaysi katakka tegishli
  GridCell? cellAt(int row, int col) {
    for (final c in cells) {
      if (row >= c.row && row < c.row + c.rowSpan && col >= c.col && col < c.col + c.colSpan) return c;
    }
    return null;
  }

  int colOf(double x) => _slot(xs, x);
  int rowOf(double y) => _slot(ys, y);

  static int _slot(List<double> edges, double v) {
    if (v < edges.first || v > edges.last) return -1;
    for (int i = 0; i < edges.length - 1; i++) {
      if (v < edges[i + 1]) return i;
    }
    return edges.length - 2;
  }
}

class _Band {
  final int start, end;
  final double center;
  const _Band(this.start, this.end, this.center);
  int get thickness => end - start + 1;
}

/// Sahifadagi jadvalni chiziqlari bo'yicha topadi. Jadval topilmasa null.
///
/// Usul: uzun gorizontal va vertikal qora chiziqlar topiladi, ular kesishgan to'r hosil qilinadi,
/// so'ng har bir chegarada chiziq haqiqatan bormi tekshiriladi. Chiziq yo'q joydagi kataklar birlashtiriladi
/// (masalan, ikki ustunga yoyilgan sarlavha).
TableGrid? detectTable(DarkMask m) {
  final w = m.width, h = m.height;
  if (w < 200 || h < 200) return null;
  final dark = m.dark;

  // ---- gorizontal chiziqlar
  final minRunH = math.max(30, (w * 0.025).round());
  final hAcc = List<int>.filled(h, 0);
  final hStart = List<int>.filled(h, w);
  final hEnd = List<int>.filled(h, -1);
  const gap = 2;
  for (int y = 0; y < h; y++) {
    final row = y * w;
    int start = -1, last = -1;
    void close() {
      if (start >= 0 && last - start + 1 >= minRunH) {
        hAcc[y] += last - start + 1;
        if (start < hStart[y]) hStart[y] = start;
        if (last > hEnd[y]) hEnd[y] = last;
      }
      start = -1;
    }

    for (int x = 0; x < w; x++) {
      if (dark[row + x] == 1) {
        if (start < 0) start = x;
        last = x;
      } else if (start >= 0 && x - last > gap) {
        close();
      }
    }
    close();
  }
  final maxH = hAcc.fold<int>(0, math.max);
  if (maxH < w * 0.2) return null;
  final thrH = math.max(w * 0.15, maxH * 0.25);
  final hBands = _bands(hAcc, thrH.round(), maxThickness: 16);
  if (hBands.length < 2) return null;

  // jadvalning eni: eng uzun chiziqlar bo'yicha
  int x0 = w, x1 = 0;
  for (final b in hBands) {
    for (int y = b.start; y <= b.end; y++) {
      if (hAcc[y] >= maxH * 0.5) {
        if (hStart[y] < x0) x0 = hStart[y];
        if (hEnd[y] > x1) x1 = hEnd[y];
      }
    }
  }
  if (x1 - x0 < w * 0.2) return null;
  // jadval doirasidan tashqaridagi chiziqlar (masalan, imzo chizig'i) tashlanadi
  final bands = <_Band>[];
  for (final b in hBands) {
    int inside = 0;
    for (int y = b.start; y <= b.end; y++) {
      if (hEnd[y] >= 0 && hEnd[y] >= x0 && hStart[y] <= x1) inside++;
    }
    if (inside > 0) bands.add(b);
  }
  if (bands.length < 2) return null;
  final yTop = bands.first.center, yBottom = bands.last.center;
  final tableH = yBottom - yTop;
  if (tableH < h * 0.05) return null;

  // ---- vertikal chiziqlar (faqat jadval ichida)
  final minRunV = math.max(40, (h * 0.012).round());
  final vAcc = List<int>.filled(w, 0);
  final xa = math.max(0, x0 - 8), xb = math.min(w - 1, x1 + 8);
  final ya = math.max(0, yTop.round() - 4), yb = math.min(h - 1, yBottom.round() + 4);
  for (int x = xa; x <= xb; x++) {
    int start = -1, last = -1;
    void close() {
      if (start >= 0 && last - start + 1 >= minRunV) vAcc[x] += last - start + 1;
      start = -1;
    }

    for (int y = ya; y <= yb; y++) {
      if (dark[y * w + x] == 1) {
        if (start < 0) start = y;
        last = y;
      } else if (start >= 0 && y - last > gap) {
        close();
      }
    }
    close();
  }
  final thrV = math.max(tableH * 0.08, 120.0);
  final vBands = _bands(vAcc, thrV.round(), maxThickness: 16);
  if (vBands.length < 2) return null;

  // ---- chegaralar ro'yxati
  final xs = _edges([for (final b in vBands) b.center], x0.toDouble(), x1.toDouble(), w * 0.012);
  final ys = _edges([for (final b in bands) b.center], yTop, yBottom, h * 0.004);
  if (xs.length < 3 || ys.length < 3) return null;
  final cols = xs.length - 1, rows = ys.length - 1;

  // ---- devor bormi: har bir kataklararo chegara bo'ylab qora piksellar ulushi.
  // Skanerlangan chiziqlar biroz qiyshiq bo'ladi, shuning uchun chiziq kichik bo'laklarga bo'linadi va
  // har bir bo'lak uchun chiziqning o'z joyi (±8 piksel ichida) qidiriladi.
  double cover(bool vertical, double pos, double a0, double a1) {
    const piece = 20, reach = 8;
    final from = (a0 + 3).round(), to = (a1 - 3).round();
    if (to <= from) return 1;
    final p0 = pos.round();
    int total = 0, hit = 0;
    for (int s0 = from; s0 < to; s0 += piece) {
      final s1 = math.min(s0 + piece, to);
      int best = 0;
      for (int off = -reach; off <= reach; off++) {
        int count = 0;
        for (int a = s0; a < s1; a++) {
          bool any = false;
          for (int d = -1; d <= 1 && !any; d++) {
            final q = p0 + off + d;
            final x = vertical ? q : a, y = vertical ? a : q;
            if (x >= 0 && x < w && y >= 0 && y < h && dark[y * w + x] == 1) any = true;
          }
          if (any) count++;
        }
        if (count > best) best = count;
        if (best == s1 - s0) break;
      }
      total += s1 - s0;
      hit += best;
    }
    return total == 0 ? 1 : hit / total;
  }

  const wall = 0.6;
  // vWall[r][c] - r-qatorning c-chegarasida (chap tomon) devor bormi (c: 1..cols-1)
  final vWall = [
    for (int r = 0; r < rows; r++)
      [for (int c = 0; c <= cols; c++) (c == 0 || c == cols) ? true : cover(true, xs[c], ys[r], ys[r + 1]) >= wall],
  ];
  final hWall = [
    for (int r = 0; r <= rows; r++)
      [for (int c = 0; c < cols; c++) (r == 0 || r == rows) ? true : cover(false, ys[r], xs[c], xs[c + 1]) >= wall],
  ];

  // ---- devor bo'lmagan joylarni birlashtirish
  final parent = List<int>.generate(rows * cols, (i) => i);
  int find(int a) {
    while (parent[a] != a) {
      parent[a] = parent[parent[a]];
      a = parent[a];
    }
    return a;
  }

  void union(int a, int b) {
    final ra = find(a), rb = find(b);
    if (ra != rb) parent[rb] = ra;
  }

  for (int r = 0; r < rows; r++) {
    for (int c = 0; c < cols; c++) {
      if (c + 1 < cols && !vWall[r][c + 1]) union(r * cols + c, r * cols + c + 1);
      if (r + 1 < rows && !hWall[r + 1][c]) union(r * cols + c, (r + 1) * cols + c);
    }
  }
  final groups = <int, List<int>>{};
  for (int i = 0; i < rows * cols; i++) {
    groups.putIfAbsent(find(i), () => []).add(i);
  }
  final cells = <GridCell>[];
  for (final members in groups.values) {
    int r0 = rows, r1 = -1, c0 = cols, c1 = -1;
    for (final i in members) {
      final r = i ~/ cols, c = i % cols;
      r0 = math.min(r0, r);
      r1 = math.max(r1, r);
      c0 = math.min(c0, c);
      c1 = math.max(c1, c);
    }
    final rect = (r1 - r0 + 1) * (c1 - c0 + 1);
    if (rect == members.length) {
      cells.add(GridCell(r0, c0, r1 - r0 + 1, c1 - c0 + 1));
    } else {
      // to'rtburchak bo'lmagan birlashma: har bir katak alohida qoladi
      for (final i in members) {
        cells.add(GridCell(i ~/ cols, i % cols, 1, 1));
      }
    }
  }
  cells.sort((a, b) => a.row != b.row ? a.row.compareTo(b.row) : a.col.compareTo(b.col));
  return TableGrid(xs, ys, cells);
}

/// [acc] da [threshold] dan baland ketma-ket joylar: bitta chiziq (qalinligi [maxThickness] dan oshmasa)
List<_Band> _bands(List<int> acc, int threshold, {int maxThickness = 16, int mergeGap = 3}) {
  final bands = <_Band>[];
  int start = -1, last = -1;
  void close() {
    if (start < 0) return;
    if (last - start + 1 <= maxThickness) {
      double sum = 0, weighted = 0;
      for (int i = start; i <= last; i++) {
        sum += acc[i];
        weighted += acc[i] * i.toDouble();
      }
      bands.add(_Band(start, last, sum == 0 ? (start + last) / 2 : weighted / sum));
    }
    start = -1;
  }

  for (int i = 0; i < acc.length; i++) {
    if (acc[i] >= threshold) {
      if (start < 0) start = i;
      last = i;
    } else if (start >= 0 && i - last > mergeGap) {
      close();
    }
  }
  close();
  return bands;
}

/// Chiziq markazlaridan chegaralar ro'yxati: yaqin chiziqlar birlashadi, jadval chetlari qo'shiladi.
List<double> _edges(List<double> centers, double first, double last, double minGap) {
  final all = [...centers]..sort();
  final out = <double>[];
  for (final c in all) {
    if (c < first - minGap * 3 || c > last + minGap * 3) continue;
    if (out.isNotEmpty && c - out.last < minGap) {
      out[out.length - 1] = (out.last + c) / 2;
    } else {
      out.add(c);
    }
  }
  if (out.isEmpty || out.first - first > minGap * 1.5) out.insert(0, first);
  if (last - out.last > minGap * 1.5) out.add(last);
  return out;
}
