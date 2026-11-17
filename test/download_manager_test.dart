import 'dart:async';
import 'dart:io';

import 'package:any_to_any/config.dart';
import 'package:any_to_any/downloader/common.dart';
import 'package:any_to_any/downloader/job_runner.dart';
import 'package:any_to_any/downloader/manager.dart';
import 'package:any_to_any/services/background.dart';
import 'package:any_to_any/services/gallery.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fake_native.dart';

/// Xotiradagi jurnal (server o'rniga)
class MemoryLog implements DownloadLog {
  final List<DateTime> starts = [];
  final List<String> hosts = [];
  @override
  Future<List<DateTime>> recent() async => List.of(starts);
  @override
  Future<void> record({required String host, required String kind}) async {
    starts.add(DateTime.now());
    hosts.add(host);
  }
}

/// Har bir yuklash tugashini testdan boshqarish mumkin bo'lgan soxta yuklovchi
class FakeRunner {
  final List<Completer<JobResult>> pending = [];
  final List<DownloadRequest> started = [];
  final List<CancelToken> tokens = [];
  JobCallbacks? lastCallbacks;
  Object? failWith;

  Future<JobResult> call(DownloadRequest r, Directory out, Set<String> used, JobCallbacks cb) {
    started.add(r);
    tokens.add(cb.cancel);
    lastCallbacks = cb;
    final c = Completer<JobResult>();
    pending.add(c);
    cb.cancel.onCancel(() {
      if (!c.isCompleted) c.completeError(const DownloadCancelled());
    });
    if (failWith != null) {
      final e = failWith!;
      scheduleMicrotask(() => c.completeError(e));
    }
    return c.future;
  }

  void finish(int index, String path, {int bytes = 1000}) => pending[index].complete(JobResult(path, bytes, 6));
}

Future<void> pump() => Future<void>.delayed(const Duration(milliseconds: 20));

DownloadRequest req(String name, {int segments = 6, OutputCodec codec = OutputCodec.original}) =>
    DownloadRequest(url: Uri.parse('https://cdn.example.com/$name.mp4'), title: name, segments: segments, codec: codec);

void main() {
  late FakeRunner runner;
  late MemoryLog log;
  late FakeNativeBridge bridge;
  late BackgroundCoordinator bg;
  late DownloadManager m;
  late Directory dir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    runner = FakeRunner();
    log = MemoryLog();
    bridge = FakeNativeBridge();
    bg = BackgroundCoordinator(bridge);
    dir = await Directory.systemTemp.createTemp('a2a_mgr');
    m = DownloadManager(runner: runner.call, log: log, bridge: bridge, background: bg, outDir: () async => dir);
  });

  tearDown(() async {
    m.dispose();
    await dir.delete(recursive: true);
  });

  group('queue', () {
    test('two at a time, the rest wait and start as slots free up', () async {
      for (final n in ['a', 'b', 'c']) {
        expect((await m.start(req(n), pro: true)).ok, isTrue);
      }
      await pump();
      expect(runner.started.map((r) => r.title), ['a', 'b'], reason: 'oldest first, max 2');
      expect(m.runningCount, 2);
      expect(m.jobs.where((j) => j.status == JobStatus.queued).single.title, 'c');
      runner.finish(0, '${dir.path}/a.mp4');
      await pump();
      expect(runner.started.map((r) => r.title), ['a', 'b', 'c']);
      expect(m.jobs.firstWhere((j) => j.title == 'a').status, JobStatus.done);
      expect(m.jobs.firstWhere((j) => j.title == 'a').outputPath, endsWith('a.mp4'));
    });

    test('progress, speed and ETA are tracked', () async {
      final o = await m.start(req('film'), pro: true);
      await pump();
      final job = o.job!;
      runner.lastCallbacks!.onProgress!(0, 1000000, 6);
      await Future<void>.delayed(const Duration(milliseconds: 800));
      runner.lastCallbacks!.onProgress!(400000, 1000000, 6);
      expect(job.received, 400000);
      expect(job.fraction, closeTo(0.4, 1e-9));
      expect(job.activeSegments, 6);
      expect(job.speed, greaterThan(100000), reason: '400 KB in ~0.8 s');
      expect(job.eta, isNotNull);
      expect(job.eta!.inSeconds, inInclusiveRange(1, 5));
    });

    test('cancel a running job and a queued job', () async {
      await m.start(req('a'), pro: true);
      await m.start(req('b'), pro: true);
      await m.start(req('c'), pro: true);
      await pump();
      final c = m.jobs.firstWhere((j) => j.title == 'c');
      m.cancel(c.id);
      expect(c.status, JobStatus.canceled);
      final a = m.jobs.firstWhere((j) => j.title == 'a');
      m.cancel(a.id);
      await pump();
      expect(a.status, JobStatus.canceled);
      expect(runner.tokens[0].isCancelled, isTrue);
      expect(runner.started.length, 2, reason: 'a cancelled queued job never starts');
    });

    test('failure shows the message and a notification; retry runs it again', () async {
      runner.failWith = const DownloadException('Sayt yuklashga ruxsat bermadi (403).');
      final job = (await m.start(req('x'), pro: true)).job!;
      await pump();
      expect(job.status, JobStatus.failed);
      expect(job.error, contains('403'));
      expect(bridge.notifications.last['title'], "Yuklab bo'lmadi");
      runner.failWith = null;
      m.retry(job.id);
      await pump();
      expect(job.status, JobStatus.running);
      expect(runner.started.length, 2);
      runner.finish(1, '${dir.path}/x.mp4');
      await pump();
      expect(job.status, JobStatus.done);
    });

    test('an unexpected error becomes a friendly message', () async {
      runner.failWith = StateError('boom');
      final job = (await m.start(req('y'), pro: true)).job!;
      await pump();
      expect(job.error, "Yuklab bo'lmadi");
    });
  });

  group('weekly limit and PRO', () {
    test('free: 10 per week, then blocked with the date and a PRO hint', () async {
      m = DownloadManager(runner: runner.call, log: log, bridge: bridge, background: bg, outDir: () async => dir, maxParallel: 20);
      final now = DateTime.now();
      for (var i = 0; i < 9; i++) {
        log.starts.add(now.subtract(Duration(days: 6, hours: 23 - i)));
      }
      expect(await m.remainingThisWeek(false), 1);
      expect((await m.start(req('last'), pro: false)).ok, isTrue);
      expect(await m.remainingThisWeek(false), 0, reason: 'the running job already counts');
      final blocked = await m.start(req('over'), pro: false);
      expect(blocked.ok, isFalse);
      expect(blocked.blocked, contains('10 ta'));
      expect(blocked.blocked, contains('PRO'));
    });

    test('when the week is used up the message tells when the next slot opens', () async {
      final first = DateTime.now().subtract(const Duration(days: 6));
      for (var i = 0; i < 10; i++) {
        log.starts.add(first.add(Duration(hours: i)));
      }
      final blocked = await m.start(req('over'), pro: false);
      expect(blocked.ok, isFalse);
      expect(blocked.blocked, contains('dan ochiladi'));
      expect(blocked.blocked, contains(formatDate(first.add(const Duration(days: 7)))));
    });

    test('old downloads fall out of the 7-day window', () async {
      for (var i = 0; i < 10; i++) {
        log.starts.add(DateTime.now().subtract(const Duration(days: 8)));
      }
      expect(await m.remainingThisWeek(false), 10);
      expect((await m.start(req('fresh'), pro: false)).ok, isTrue);
    });

    test('a successful download is recorded for the weekly count; a failed one is not', () async {
      final ok = (await m.start(req('good'), pro: false)).job!;
      await pump();
      runner.finish(0, '${dir.path}/good.mp4');
      await pump();
      expect(ok.status, JobStatus.done);
      expect(log.starts.length, 1);
      expect(log.hosts.single, 'cdn.example.com');
      runner.failWith = const DownloadException('x');
      await m.start(req('bad'), pro: false);
      await pump();
      expect(log.starts.length, 1, reason: 'failures do not use up the week');
    });

    test('PRO has no weekly limit', () async {
      for (var i = 0; i < 25; i++) {
        log.starts.add(DateTime.now());
      }
      expect(await m.remainingThisWeek(true), isNull);
      expect((await m.start(req('pro'), pro: true)).ok, isTrue);
    });

    test('free users: at most 6 parts and no codec choice; PRO: up to 18 and codec kept', () async {
      await m.start(req('f', segments: 18, codec: OutputCodec.h265), pro: false);
      await m.start(req('p', segments: 18, codec: OutputCodec.h265), pro: true);
      await m.start(req('p2', segments: 40), pro: true);
      await pump();
      final byTitle = {for (final r in runner.started) r.title: r};
      expect(byTitle['f']!.segments, 6);
      expect(byTitle['f']!.codec, OutputCodec.original);
      expect(byTitle['p']!.segments, 18);
      expect(byTitle['p']!.codec, OutputCodec.h265);
      expect(m.jobs.firstWhere((j) => j.title == 'p2').request.segments, 18, reason: 'capped');
    });

    test('segment choices and the label', () {
      expect(segmentChoices(false), [6]);
      expect(segmentChoices(true).first, 6);
      expect(segmentChoices(true).last, 18);
      expect(quotaLabel(false, 7), 'Bu hafta qoldi: 7 / 10');
      expect(quotaLabel(true, null), contains('cheklovsiz'));
    });
  });

  group('notifications and background service', () {
    test('finished download notifies; the foreground service follows the active jobs', () async {
      final job = (await m.start(req('movie'), pro: true)).job!;
      await pump();
      expect(bridge.foregrounds.last['kind'], 'download');
      expect(bridge.foregrounds.last['text'], 'movie');
      runner.finish(0, '${dir.path}/movie.mp4');
      await pump();
      expect(job.status, JobStatus.done);
      expect(bridge.notifications.last['title'], 'Yuklandi');
      expect(bridge.notifications.last['body'], 'movie');
      expect(bridge.calls.last, 'stopForeground', reason: 'nothing left to download: the service stops');
    });
  });

  group('gallery', () {
    tearDown(() => galleryPublisher = publishToGallery);

    test('an old video that is not in the gallery can be added later; the job then points at the gallery copy', () async {
      final f = File('${dir.path}/eski.mp4')..writeAsBytesSync([1, 2, 3]);
      final job = (await m.start(req('eski'), pro: true)).job!;
      await pump();
      runner.finish(0, f.path, bytes: 3);
      await pump();
      expect(job.inGallery, isFalse);
      final calls = <String>[];
      // Galereyadagi nusxa: haqiqiy fayl (restartdan keyin tarixda faqat mavjud fayllar qoladi)
      final copy = File('${dir.path}/Movies/CORE/eski.mp4')
        ..createSync(recursive: true)
        ..writeAsBytesSync([1, 2, 3]);
      galleryPublisher = (path, kind, {name}) async {
        calls.add('${kind.name}:$name');
        return GalleryResult(copy.path, inGallery: true);
      };
      expect(await m.addToGallery(job.id), "Galereyaga qo'shildi");
      expect(calls, ['video:eski.mp4']);
      expect(job.inGallery, isTrue);
      expect(job.outputPath, copy.path);
      // restartdan keyin ham saqlanadi
      final again = DownloadManager(runner: runner.call, log: log, bridge: bridge, background: bg, outDir: () async => dir);
      await again.load();
      final restored = again.jobs.firstWhere((j) => j.title == 'eski');
      expect(restored.inGallery, isTrue);
      expect(restored.outputPath, copy.path);
      again.dispose();
    });

    test('when the gallery refuses, the job keeps its file and the reason is shown', () async {
      final f = File('${dir.path}/x.mp4')..writeAsBytesSync([1]);
      final job = (await m.start(req('x'), pro: true)).job!;
      await pump();
      runner.finish(0, f.path, bytes: 1);
      await pump();
      galleryPublisher = (path, kind, {name}) async => GalleryResult(path, inGallery: false, note: "Galereyaga qo'shib bo'lmadi. Fayl: $path");
      expect(await m.addToGallery(job.id), contains("qo'shib bo'lmadi"));
      expect(job.inGallery, isFalse);
      expect(job.outputPath, f.path);
    });

    test('missing file, unknown job and unfinished jobs give a clear answer', () async {
      expect(await m.addToGallery('yoq'), 'Fayl topilmadi');
      final job = (await m.start(req('y'), pro: true)).job!;
      await pump();
      expect(await m.addToGallery(job.id), 'Fayl topilmadi', reason: 'still downloading');
      runner.finish(0, '${dir.path}/never_created.mp4');
      await pump();
      expect(await m.addToGallery(job.id), contains("o'chirilgan"));
    });

    test('a finished download reports where it is saved and a warning (for example H.265 fallback)', () async {
      final f = File('${dir.path}/h.mp4')..writeAsBytesSync([1]);
      final job = (await m.start(req('h'), pro: true)).job!;
      await pump();
      runner.pending[0].complete(JobResult(f.path, 1, 6, inGallery: true, note: "H.265 kodlash muvaffaqiyatsiz bo'ldi: video H.264 formatida saqlandi"));
      await pump();
      expect(job.inGallery, isTrue);
      expect(job.note, contains('H.264'));
    });
  });

  group('history', () {
    test('finished downloads are remembered after a restart; deleted files are not', () async {
      File('${dir.path}/kept.mp4').writeAsBytesSync([1, 2, 3]);
      await m.start(req('kept'), pro: true);
      await m.start(req('gone'), pro: true);
      await pump();
      runner.finish(0, '${dir.path}/kept.mp4', bytes: 3);
      runner.finish(1, '${dir.path}/gone.mp4');
      await pump();
      runner.failWith = const DownloadException('xato');
      await m.start(req('broken'), pro: true);
      await pump();

      final again = DownloadManager(runner: runner.call, log: log, bridge: bridge, background: bg, outDir: () async => dir);
      await again.load();
      final titles = again.jobs.map((j) => j.title).toList();
      expect(titles, containsAll(['kept', 'broken']));
      expect(titles, isNot(contains('gone')), reason: 'its file no longer exists');
      expect(again.jobs.firstWhere((j) => j.title == 'kept').status, JobStatus.done);
      expect(again.jobs.firstWhere((j) => j.title == 'broken').error, 'xato');
      again.dispose();
    });

    test('remove can delete the file, clearFinished empties the list', () async {
      final f = File('${dir.path}/v.mp4')..writeAsBytesSync([9]);
      final job = (await m.start(req('v'), pro: true)).job!;
      await pump();
      runner.finish(0, f.path, bytes: 1);
      await pump();
      await m.remove(job.id, deleteFile: true);
      expect(f.existsSync(), isFalse);
      expect(m.jobs, isEmpty);
      await m.start(req('w'), pro: true);
      await pump();
      runner.finish(1, '${dir.path}/w.mp4');
      await pump();
      await m.clearFinished();
      expect(m.jobs, isEmpty);
    });
  });
}
