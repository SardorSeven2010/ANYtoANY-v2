import 'dart:io';

import 'package:flutter/foundation.dart';

// Ilova Android, iPhone (iOS), Windows va Linux'da ishlaydi.
// Platformaga bog'liq joylar shu yordamchilar orqali ajratiladi.

/// Android telefon yoki planshet
bool get isAndroidApp => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// iPhone yoki iPad
bool get isIOSApp => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

/// Windows kompyuter
bool get isWindowsApp => !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

/// Linux kompyuter
bool get isLinuxApp => !kIsWeb && defaultTargetPlatform == TargetPlatform.linux;

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
