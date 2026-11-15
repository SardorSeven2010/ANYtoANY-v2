import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';

import '../platform.dart';
import 'media_tools.dart';
import 'native_bridge.dart';

/// Galereyaga qo'shiladigan fayl turi
enum GalleryKind { video, audio, image }

/// Galereya o'zgargani haqida bildiradi: Video / Audio ro'yxati qayta yuklanadi
final ValueNotifier<int> libraryRevision = ValueNotifier<int>(0);

class GalleryResult {
  /// Fayl endi turgan yo'l (galereyaga ko'chirilgan bo'lsa, yangi yo'l)
  final String path;

  /// Galereyada ko'rinadimi
  final bool inGallery;

  /// Foydalanuvchiga ko'rsatiladigan izoh (xato yoki ruxsat haqida)
  final String? note;
  const GalleryResult(this.path, {required this.inGallery, this.note});
}

/// Testlarda almashtiriladi
Future<GalleryResult> Function(String path, GalleryKind kind, {String? name}) galleryPublisher = publishToGallery;

/// Android: fayl MediaStore'ga (Movies / Music / Pictures ichidagi CORE papkasiga) ko'chiriladi va
/// asl nusxa o'chiriladi (xotira ikki baravar band bo'lmasin).
/// iPhone: fayl "Rasmlar" kutubxonasiga qo'shiladi; ilovaning o'z nusxasi ijro uchun qoladi.
/// Kompyuter: fayl o'z joyida qoladi.
Future<GalleryResult> publishToGallery(String path, GalleryKind kind, {String? name}) async {
  final file = File(path);
  if (isAndroidApp) {
    final saved = await nativeBridge.saveToGallery(path: path, kind: kind.name, name: name ?? lastSegment(path));
    if (saved == null || saved.isEmpty) {
      return GalleryResult(path, inGallery: false, note: "Galereyaga qo'shib bo'lmadi. Fayl: $path");
    }
    await deleteQuietly(path);
    libraryRevision.value++;
    return GalleryResult(saved, inGallery: true);
  }
  if (isIOSApp) {
    try {
      final state = await PhotoManager.requestPermissionExtend(
        requestOption: const PermissionRequestOption(iosAccessLevel: IosAccessLevel.addOnly),
      );
      if (!state.hasAccess && state != PermissionState.limited) {
        return GalleryResult(path, inGallery: false, note: "Galereyaga qo'shish uchun Sozlamalardan ruxsat bering");
      }
      final title = name ?? lastSegment(path);
      switch (kind) {
        case GalleryKind.video:
          await PhotoManager.editor.saveVideo(file, title: title);
        case GalleryKind.image:
          await PhotoManager.editor.saveImageWithPath(path, title: title);
        case GalleryKind.audio:
          return GalleryResult(path, inGallery: false); // musiqa "Rasmlar"ga qo'shilmaydi
      }
      libraryRevision.value++;
      return GalleryResult(path, inGallery: true);
    } catch (_) {
      return GalleryResult(path, inGallery: false, note: "Galereyaga qo'shib bo'lmadi");
    }
  }
  return GalleryResult(path, inGallery: false);
}

GalleryKind? galleryKindOf(String fileName) {
  if (isVideoFile(fileName)) return GalleryKind.video;
  if (isAudioFile(fileName)) return GalleryKind.audio;
  if (isImageFile(fileName)) return GalleryKind.image;
  return null;
}
