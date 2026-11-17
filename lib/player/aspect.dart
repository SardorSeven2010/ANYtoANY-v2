import 'package:flutter/widgets.dart';

/// Video ekranga qanday sig'dirilishi: asl, to'ldirish yoki tayyor o'lcham (16:9, 19.5:9 ...)
enum AspectMode {
  original("Asl o'lcham", null, BoxFit.contain),
  fill("To'ldirish (cho'zish)", null, BoxFit.fill),
  cover("Kesib to'ldirish", null, BoxFit.cover),
  r16x9("16:9", 16 / 9, BoxFit.fill),
  r19_5x9("19.5:9", 19.5 / 9, BoxFit.fill),
  r18x9("18:9", 18 / 9, BoxFit.fill),
  r20x9("20:9", 20 / 9, BoxFit.fill),
  r21x9("21:9", 21 / 9, BoxFit.fill),
  r4x3("4:3", 4 / 3, BoxFit.fill),
  r3x2("3:2", 3 / 2, BoxFit.fill),
  r1x1("1:1", 1, BoxFit.fill),
  r9x16("9:16", 9 / 16, BoxFit.fill);

  final String label;

  /// Tayyor nisbat (eni / bo'yi); asl, to'ldirish va kesish rejimlarida null
  final double? ratio;
  final BoxFit fit;
  const AspectMode(this.label, this.ratio, this.fit);

  /// Qisqa yozuv (tugmada ko'rsatish uchun)
  String get shortLabel => ratio != null ? label : switch (this) { AspectMode.original => "Asl", AspectMode.fill => "Cho'zish", _ => "Kesish" };
}
