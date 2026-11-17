import 'package:image/image.dart' as img;

/// Rasmni matn tanish uchun tayyorlaydi: oq-qora (kulrang) qilinadi va rangli muhr / siyoh dog'lari oqartiriladi.
///
/// Skanerlangan hujjatlarda ko'pincha ko'k yoki qizil muhr matn ustiga tushadi va OCR ni chalg'itadi.
/// Qora matn kulrang bo'lgani uchun, rangi aniq (to'yingan) piksellar oqartirilsa, muhr yo'qoladi, matn qoladi.
/// Hujjatning katta qismi rangli bo'lsa (rangli matn, rasm), rang olib tashlanmaydi.
img.Image cleanForOcr(img.Image source) {
  final w = source.width, h = source.height;
  final rgb = source.convert(numChannels: 3).getBytes(order: img.ChannelOrder.rgb);
  final out = img.Image(width: w, height: h, numChannels: 1);
  final gray = List<int>.filled(w * h, 255);
  int ink = 0, colored = 0;
  final isColored = List<bool>.filled(w * h, false);
  for (int i = 0, j = 0; i < w * h; i++, j += 3) {
    final r = rgb[j], g = rgb[j + 1], b = rgb[j + 2];
    final lum = (r * 299 + g * 587 + b * 114) ~/ 1000;
    gray[i] = lum;
    if (lum < 200) {
      ink++;
      final mx = r > g ? (r > b ? r : b) : (g > b ? g : b);
      final mn = r < g ? (r < b ? r : b) : (g < b ? g : b);
      if (mx - mn > 55) {
        colored++;
        isColored[i] = true;
      }
    }
  }
  final suppress = ink > 0 && colored / ink < 0.3;
  // Daraja tuzatish: och soyalar (pushti / kulrang katak foni) oqqa aylanadi, qora matn qora qoladi.
  // Fon tekis oq bo'lsa, OCR sahifa tuzilishini va harflarni yaxshiroq ajratadi.
  const black = 60, white = 215;
  final levels = List<int>.generate(256, (v) => v <= black ? 0 : (v >= white ? 255 : ((v - black) * 255 ~/ (white - black))));
  int k = 0;
  for (final px in out) {
    px.r = (suppress && isColored[k]) ? 255 : levels[gray[k]];
    k++;
  }
  return out;
}
