import 'dart:io';

import 'package:any_to_any/app_theme.dart';
import 'package:any_to_any/screens/media_library.dart';
import 'package:any_to_any/services/gallery.dart';
import 'package:any_to_any/services/native_bridge.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fake_native.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeNativeBridge bridge;
  late Directory dir;

  setUp(() async {
    bridge = FakeNativeBridge();
    setNativeBridge(bridge);
    dir = await Directory.systemTemp.createTemp('a2a_gallery');
  });

  tearDown(() async {
    setNativeBridge(null);
    debugDefaultTargetPlatformOverride = null;
    await dir.delete(recursive: true);
  });

  File make(String name, {int bytes = 100}) => File('${dir.path}/$name')..writeAsBytesSync(List.filled(bytes, 7));

  group('Android: MediaStore', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);

    test('the video moves into the gallery and the app copy is removed', () async {
      final f = make('kino.mp4');
      final before = libraryRevision.value;
      final r = await publishToGallery(f.path, GalleryKind.video, name: 'kino.mp4');
      expect(r.inGallery, isTrue);
      expect(r.path, '/storage/emulated/0/Movies/CORE/kino.mp4');
      expect(bridge.gallerySaves.single, {'path': f.path, 'kind': 'video', 'name': 'kino.mp4'});
      expect(f.existsSync(), isFalse, reason: 'no double storage');
      expect(libraryRevision.value, before + 1, reason: 'the Video / Audio lists reload');
    });

    test('audio and images use their own kind', () async {
      await publishToGallery(make('a.mp3').path, GalleryKind.audio);
      await publishToGallery(make('r.png').path, GalleryKind.image);
      expect(bridge.gallerySaves.map((e) => e['kind']), ['audio', 'image']);
    });

    test('if the gallery refuses, the file is kept and the user is told where it is', () async {
      bridge.galleryResult = (_) => null;
      final f = make('kino.mp4');
      final before = libraryRevision.value;
      final r = await publishToGallery(f.path, GalleryKind.video);
      expect(r.inGallery, isFalse);
      expect(r.path, f.path);
      expect(r.note, contains(f.path));
      expect(f.existsSync(), isTrue, reason: 'nothing is lost');
      expect(libraryRevision.value, before);
    });
  });

  test('iPhone: without the Photos plugin it degrades to a note, the file stays', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final f = make('kino.mp4');
    final r = await publishToGallery(f.path, GalleryKind.video);
    expect(r.inGallery, isFalse);
    expect(r.note, isNotNull);
    expect(f.existsSync(), isTrue);
  });

  test('desktop: the file stays where it is', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final f = make('kino.mp4');
    final r = await publishToGallery(f.path, GalleryKind.video);
    expect(r.inGallery, isFalse);
    expect(r.path, f.path);
    expect(bridge.gallerySaves, isEmpty);
  });

  test('kind by file name', () {
    expect(galleryKindOf('a.MP4'), GalleryKind.video);
    expect(galleryKindOf('a.mp3'), GalleryKind.audio);
    expect(galleryKindOf('a.png'), GalleryKind.image);
    expect(galleryKindOf('a.pdf'), isNull);
  });

  testWidgets('the Video list reloads by itself when a new video is published', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    tester.view.physicalSize = const Size(1080, 2000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    Future<void> real() async {
      for (var i = 0; i < 12; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
        await tester.pump();
      }
    }

    make('birinchi.mp4', bytes: 2048);
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(appThemes.first),
      home: Scaffold(body: MediaLibraryTab(kind: MediaKind.video, desktopRoots: [dir])),
    ));
    await real();
    expect(find.text('birinchi.mp4'), findsOneWidget);
    expect(find.text('ikkinchi.mp4'), findsNothing);

    make('ikkinchi.mp4', bytes: 2048);
    libraryRevision.value++;
    await real();
    expect(find.text('ikkinchi.mp4'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });
}
