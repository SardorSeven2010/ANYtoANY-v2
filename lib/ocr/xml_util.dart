/// XML matniga yaroqsiz belgilarni olib tashlaydi va maxsus belgilarni almashtiradi.
String xmlEscape(String text) {
  final buf = StringBuffer();
  for (final r in text.runes) {
    // XML 1.0 da ruxsat etilmagan boshqaruv belgilari
    if (r < 0x20 && r != 0x09 && r != 0x0A && r != 0x0D) continue;
    if (r == 0xFFFE || r == 0xFFFF) continue;
    switch (r) {
      case 0x26:
        buf.write('&amp;');
      case 0x3C:
        buf.write('&lt;');
      case 0x3E:
        buf.write('&gt;');
      case 0x22:
        buf.write('&quot;');
      default:
        buf.writeCharCode(r);
    }
  }
  return buf.toString();
}
