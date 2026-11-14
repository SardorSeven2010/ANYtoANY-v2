import 'dart:io';

import 'package:flutter/foundation.dart';

// Ilova Android telefonda ham, Windows kompyuterda ham ishlaydi.
// Platformaga bog'liq joylar shu yordamchilar orqali ajratiladi.

/// Android telefon yoki planshet
bool get isAndroidApp => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Kompyuter (Windows, Linux yoki macOS)
bool get isDesktopApp =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS);

/// Papka va fayl nomini shu tizimga mos ajratgich bilan qo'shadi
String joinPath(String dir, String name) {
  if (dir.endsWith('/') || dir.endsWith(r'\')) return "$dir$name";
  return "$dir${Platform.pathSeparator}$name";
}

/// Yo'lning oxirgi qismi (fayl yoki papka nomi). Windows (\) va Android (/) yo'llari uchun
String lastSegment(String path) {
  final parts = path.split(RegExp(r'[/\\]')).where((p) => p.isNotEmpty);
  return parts.isEmpty ? path : parts.last;
}
