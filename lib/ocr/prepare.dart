import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'preprocess.dart';
import 'scan_page.dart';
import 'table_detector.dart';

/// OCR uchun tayyor sahifa: to'g'rilangan, jadval chiziqlari o'chirilgan kulrang rasm va uning geometriyasi.
/// Rasm to'g'rilangani uchun [geometry] dagi koordinatalar to'g'ridan-to'g'ri rasm koordinatalari bilan mos keladi.
class PreparedPage {
  final img.Image image;
  final PageGeometry geometry;
  const PreparedPage(this.image, this.geometry);
}

/// Rangli sahifa rasmini OCR uchun tayyorlaydi:
///  1) kulrang qilinadi, muhr / rangli dog'lar va katak foni oqartiriladi ([cleanForOcr])
///  2) biroz qiyshiq skanerlangan bo'lsa, to'g'rilanadi
///  3) jadval topilsa, uning chiziqlari o'chiriladi (OCR chiziqlarni harf bilan adashtirmaydi)
PreparedPage prepareForOcr(img.Image source) {
  final clean = cleanForOcr(source);
  final w = clean.width, h = clean.height;
  final mask0 = DarkMask.fromImage(clean);
  final deskew = estimateDeskew(mask0);
  var gray = Uint8List.fromList(clean.getBytes());
  if (!deskew.isIdentity) gray = _rotateGray(gray, w, h, deskew);
  final mask = deskew.isIdentity ? mask0 : deskew.apply(mask0);
  final grid = detectTable(mask);

  final ink = <bool>[];
  if (grid != null) {
    for (final g in grid.cells) {
      ink.add(hasInk(mask, grid.xs[g.col], grid.ys[g.row], grid.xs[g.col + g.colSpan], grid.ys[g.row + g.rowSpan]));
    }
    _eraseLines(gray, w, h, mask, grid);
  }
  final image = img.Image.fromBytes(width: w, height: h, bytes: gray.buffer, numChannels: 1);
  return PreparedPage(image, PageGeometry(Deskew(0, w / 2, h / 2), grid, ink));
}

/// Kulrang rasmni [deskew] bo'yicha buradi (bilinear), bo'sh joylar oq bo'ladi
Uint8List _rotateGray(Uint8List src, int w, int h, Deskew deskew) {
  final out = Uint8List(w * h)..fillRange(0, w * h, 255);
  final c = math.cos(deskew.phi), s = math.sin(deskew.phi);
  for (int y = 0; y < h; y++) {
    final v = y - deskew.cy;
    for (int x = 0; x < w; x++) {
      final u = x - deskew.cx;
      final sx = u * c - v * s + deskew.cx;
      final sy = u * s + v * c + deskew.cy;
      if (sx < 0 || sy < 0 || sx >= w - 1 || sy >= h - 1) continue;
      final x0 = sx.floor(), y0 = sy.floor();
      final fx = sx - x0, fy = sy - y0;
      final i = y0 * w + x0;
      final top = src[i] * (1 - fx) + src[i + 1] * fx;
      final bottom = src[i + w] * (1 - fx) + src[i + w + 1] * fx;
      out[y * w + x] = (top * (1 - fy) + bottom * fy).round();
    }
  }
  return out;
}

/// Jadval chiziqlarini oqqa bo'yaydi: faqat uzun qora bo'laklar (harf shtrixlari qisqa, tegilmaydi)
void _eraseLines(Uint8List bytes, int w, int h, DarkMask mask, TableGrid grid) {
  const band = 3, minRun = 40;

  void paint(int x, int y) {
    if (x >= 0 && x < w && y >= 0 && y < h) bytes[y * w + x] = 255;
  }

  bool dark(int x, int y) => x >= 0 && x < w && y >= 0 && y < h && mask.dark[y * w + x] == 1;

  // vertikal chiziqlar
  for (final cx in grid.xs) {
    final x = cx.round();
    final y0 = math.max(0, grid.top.round() - 6), y1 = math.min(h - 1, grid.bottom.round() + 6);
    int start = -1, last = -1;
    void flush() {
      if (start >= 0 && last - start + 1 >= minRun) {
        for (int y = start - 1; y <= last + 1; y++) {
          for (int d = -band; d <= band; d++) {
            paint(x + d, y);
          }
        }
      }
      start = -1;
    }

    for (int y = y0; y <= y1; y++) {
      bool any = false;
      for (int d = -band; d <= band && !any; d++) {
        any = dark(x + d, y);
      }
      if (any) {
        if (start < 0) start = y;
        last = y;
      } else if (start >= 0 && y - last > 2) {
        flush();
      }
    }
    flush();
  }

  // gorizontal chiziqlar
  for (final cy in grid.ys) {
    final y = cy.round();
    final x0 = math.max(0, grid.left.round() - 6), x1 = math.min(w - 1, grid.right.round() + 6);
    int start = -1, last = -1;
    void flush() {
      if (start >= 0 && last - start + 1 >= minRun) {
        for (int x = start - 1; x <= last + 1; x++) {
          for (int d = -band; d <= band; d++) {
            paint(x, y + d);
          }
        }
      }
      start = -1;
    }

    for (int x = x0; x <= x1; x++) {
      bool any = false;
      for (int d = -band; d <= band && !any; d++) {
        any = dark(x, y + d);
      }
      if (any) {
        if (start < 0) start = x;
        last = x;
      } else if (start >= 0 && x - last > 2) {
        flush();
      }
    }
    flush();
  }
}
