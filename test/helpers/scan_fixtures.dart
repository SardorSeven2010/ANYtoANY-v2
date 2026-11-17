import 'package:image/image.dart' as img;

/// Skanerlangan jadval sahifasini taqlid qiladi: oq fon, qora chiziqlar. Chiziqlar biroz qiyshiq (haqiqiy skanerdagidek).
///
///   ustunlar: 100 | 220 | 520 | 720 | 900
///   qatorlar: 300 | 420 | 520 | 620 | 720
///   1-ustun 1-2 qatorga birlashgan; 3-4 ustunlarning birinchi qatori birlashgan (sarlavha).
img.Image tablePage({double vSlope = 0.004, double hSlope = 0.006, bool rotatedHeaderInk = false}) {
  final image = img.Image(width: 1000, height: 1100, numChannels: 3);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  final black = img.ColorRgb8(0, 0, 0);
  const xs = [100, 220, 520, 720, 900];
  const ys = [300, 420, 520, 620, 720];

  void v(int x, int y0, int y1) => img.drawLine(image,
      x1: (x + vSlope * y0).round(), y1: y0, x2: (x + vSlope * y1).round(), y2: y1, color: black, thickness: 3);
  void h(int y, int x0, int x1) => img.drawLine(image,
      x1: x0, y1: (y + hSlope * x0).round(), x2: x1, y2: (y + hSlope * x1).round(), color: black, thickness: 3);

  // tashqi ramka
  h(ys.first, xs.first, xs.last);
  h(ys.last, xs.first, xs.last);
  v(xs.first, ys.first, ys.last);
  v(xs.last, ys.first, ys.last);
  // ichki gorizontal chiziqlar
  h(ys[1], xs[1], xs.last); // 1-ustun 1-2 qatorda birlashgan: chiziq yo'q
  h(ys[2], xs.first, xs.last);
  h(ys[3], xs.first, xs.last);
  // ichki vertikal chiziqlar
  v(xs[1], ys.first, ys.last);
  v(xs[2], ys.first, ys.last);
  v(xs[3], ys[1], ys.last); // 3 va 4 ustun birinchi qatorda birlashgan: chiziq faqat 2-qatordan pastda
  if (rotatedHeaderInk) {
    // 1-ustun sarlavhasida (2 qatorga birlashgan, tor va baland katak) burilgan matnga o'xshash qora izlar
    for (int i = 0; i < 8; i++) {
      img.fillRect(image, x1: 130 + i * 8, y1: 340, x2: 133 + i * 8, y2: 450, color: black);
    }
  }
  return image;
}
