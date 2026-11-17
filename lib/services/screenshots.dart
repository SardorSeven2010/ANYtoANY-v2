import 'dart:io';
import 'dart:typed_data';

import 'package:photo_manager/photo_manager.dart';

import '../platform.dart';
import 'media_tools.dart';

/// Pleyerdan olingan kadrni saqlaydi. Natija: saqlangan joy tavsifi (xato bo'lsa null).
/// Testlarda [screenshotSaver] almashtiriladi.
typedef ScreenshotSaver = Future<String?> Function(Uint8List png, String baseName);

ScreenshotSaver screenshotSaver = saveScreenshotToDevice;

String screenshotFileName(String baseName, DateTime at) {
  String two(int v) => v.toString().padLeft(2, '0');
  final stamp = "${at.year}${two(at.month)}${two(at.day)}_${two(at.hour)}${two(at.minute)}${two(at.second)}";
  final clean = baseName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  return "CORE_${clean.isEmpty ? "kadr" : clean}_$stamp";
}

/// Telefonda: galereyaga (Pictures/CORE); kompyuterda: Yuklanmalar papkasiga
Future<String?> saveScreenshotToDevice(Uint8List png, String baseName) async {
  final name = screenshotFileName(baseName, DateTime.now());
  if (isAndroidApp || isIOSApp) {
    try {
      await PhotoManager.editor.saveImage(png, filename: "$name.png", title: name, relativePath: "Pictures/CORE");
      return "Galereya (CORE)";
    } catch (_) {
      // galereyaga yozib bo'lmasa, oddiy papkaga saqlanadi
    }
  }
  try {
    final dir = await resolveOutputDir();
    final path = uniquePath(dir, name, "png", <String>{});
    await File(path).writeAsBytes(png, flush: true);
    return outputDirLabel(dir);
  } catch (_) {
    return null;
  }
}
