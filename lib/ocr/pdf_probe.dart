import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// PDF faylda haqiqiy matn (tanlab olinadigan harflar) bormi?
///
/// Skanerlangan hujjatlarda (CamScanner va shunga o'xshash ilovalar) sahifa faqat rasm bo'ladi: matn buyruqlari
/// (BT ... Tj / TJ ... ET) yo'q. Sahifa tarkibi oqimlari ochilib, shu buyruqlar qidiriladi.
/// Aniq javob berib bo'lmasa (masalan, fayl o'qilmasa) true qaytadi: bunday fayl oddiy PDF kabi qayta ishlanadi.
Future<bool> pdfHasText(String path) async {
  try {
    final file = File(path);
    if (await file.length() > 120 * 1024 * 1024) return true;
    return pdfBytesHaveText(await file.readAsBytes());
  } catch (_) {
    return true;
  }
}

/// [pdfHasText] ning xotiradagi baytlar uchun varianti
bool pdfBytesHaveText(Uint8List bytes) {
  final raw = latin1.decode(bytes, allowInvalid: true);
  final streams = RegExp(r'stream\r?\n').allMatches(raw);
  int checked = 0;
  for (final m in streams) {
    if (checked >= 400) break;
    final start = m.end;
    final end = raw.indexOf('endstream', start);
    if (end < 0) continue;
    final dictStart = raw.lastIndexOf('obj', m.start);
    final dict = dictStart < 0 ? '' : raw.substring(dictStart, m.start);
    // rasm, shrift, rang profili va boshqa matn bo'lmagan oqimlar o'tkazib yuboriladi
    if (dict.contains('/Image') ||
        dict.contains('/FontFile') ||
        dict.contains('/Length1') ||
        dict.contains('/XRef') ||
        dict.contains('/ObjStm') ||
        dict.contains('/ICCBased') ||
        dict.contains('/Metadata')) {
      continue;
    }
    checked++;
    Uint8List data = Uint8List.sublistView(bytes, start, end);
    if (dict.contains('/FlateDecode')) {
      try {
        data = Uint8List.fromList(zlib.decode(data));
      } catch (_) {
        continue;
      }
    } else if (dict.contains('/Filter')) {
      continue; // boshqa siqish: ochilmaydi
    }
    // juda katta oqimlarning boshi yetarli
    final text = latin1.decode(data.length > 400000 ? Uint8List.sublistView(data, 0, 400000) : data, allowInvalid: true);
    if (_textOperators.hasMatch(text)) return true;
  }
  return false;
}

final RegExp _textOperators = RegExp(r'\bBT\b[\s\S]{0,4000}?\b(Tj|TJ)\b');
