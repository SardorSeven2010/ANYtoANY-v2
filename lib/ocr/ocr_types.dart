import 'dart:io';

/// Rasmdan tanilgan bitta so'z va uning rasmdagi joyi (piksellarda).
class OcrWord {
  final String text;
  final double left, top, right, bottom;

  /// 0..1; noma'lum bo'lsa 1
  final double confidence;

  const OcrWord(this.text, this.left, this.top, this.right, this.bottom, {this.confidence = 1});

  double get width => right - left;
  double get height => bottom - top;
  double get cx => (left + right) / 2;
  double get cy => (top + bottom) / 2;

  @override
  String toString() => 'OcrWord($text @ ${left.round()},${top.round()} ${right.round()},${bottom.round()})';
}

/// Matn tanish dvigateli. Ilovada Android'dagi ML Kit, Linux'da o'rnatilgan Tesseract, testlarda soxta ob'ekt.
abstract class OcrEngine {
  /// Shu qurilmada matn tanish mumkinmi
  Future<bool> isAvailable();

  /// So'z qutisining balandligidan shrift o'lchamini topish koeffitsiyenti (dvigatelga qarab qutilar turlicha tor / keng)
  double get fontFactor => 1.0;

  /// Rasm fayldagi so'zlarni qaytaradi (joylashuvi bilan).
  /// [lineMode]: rasmda faqat bitta qisqa matn bor (masalan, bitta katak): shunga moslab o'qiladi.
  Future<List<OcrWord>> recognize(String imagePath, {bool lineMode = false});
}

class OcrException implements Exception {
  final String message;
  const OcrException(this.message);

  @override
  String toString() => message;
}

/// Linux'da o'rnatilgan Tesseract dasturi orqali tanish. Faqat Linux'da (va sinovda) ishlatiladi.
class TesseractOcrEngine implements OcrEngine {
  TesseractOcrEngine({this.languages = const ['uzb', 'eng'], this.executable = 'tesseract'});

  final List<String> languages;
  final String executable;
  String? _lang;

  /// Tesseract so'zning o'zigacha (harflar balandligida) tor quti beradi
  @override
  double get fontFactor => 1.5;

  Future<String?> _resolveLanguage() async {
    if (_lang != null) return _lang;
    try {
      final r = await Process.run(executable, ['--list-langs']);
      if (r.exitCode != 0) return null;
      final installed = r.stdout.toString().split('\n').map((e) => e.trim()).toSet();
      final usable = languages.where(installed.contains).toList();
      if (usable.isEmpty) return null;
      return _lang = usable.join('+');
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> isAvailable() async => await _resolveLanguage() != null;

  @override
  Future<List<OcrWord>> recognize(String imagePath, {bool lineMode = false}) async {
    final lang = await _resolveLanguage();
    if (lang == null) throw const OcrException("Tesseract topilmadi");
    final r = await Process.run(executable, [imagePath, 'stdout', '-l', lang, '--psm', lineMode ? '7' : '11', 'tsv']);
    if (r.exitCode != 0) throw OcrException("Tesseract xatosi: ${r.stderr}");
    return parseTesseractTsv(r.stdout.toString());
  }
}

/// Tesseract TSV chiqishidan so'zlarni oladi (5-daraja qatorlari)
List<OcrWord> parseTesseractTsv(String tsv) {
  final words = <OcrWord>[];
  for (final line in tsv.split('\n')) {
    final p = line.split('\t');
    if (p.length < 12 || p[0] != '5') continue;
    final text = p.sublist(11).join('\t').trim();
    if (text.isEmpty) continue;
    final left = double.tryParse(p[6]);
    final top = double.tryParse(p[7]);
    final width = double.tryParse(p[8]);
    final height = double.tryParse(p[9]);
    final conf = double.tryParse(p[10]) ?? -1;
    if (left == null || top == null || width == null || height == null) continue;
    words.add(OcrWord(text, left, top, left + width, top + height, confidence: conf < 0 ? 1 : conf / 100));
  }
  return words;
}
