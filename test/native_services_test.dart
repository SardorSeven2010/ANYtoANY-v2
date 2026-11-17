import 'package:any_to_any/services/reminders.dart';
import 'package:any_to_any/services/background.dart';
import 'package:any_to_any/services/native_bridge.dart';
import 'package:any_to_any/services/profile_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fake_native.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('subscription reminders', () {
    final now = DateTime(2026, 11, 14, 10);

    test('schedules 3 days, 1 day and expiry; cancels the old ones first', () async {
      final bridge = FakeNativeBridge();
      final p = ProfileService()
        ..isPro = true
        ..proUntil = now.add(const Duration(days: 20));
      final times = await syncRemindersForTest(p, bridge, now);
      expect(times, [
        now.add(const Duration(days: 17)),
        now.add(const Duration(days: 19)),
        now.add(const Duration(days: 20)),
      ]);
      expect(bridge.calls.take(3), ['cancel:9001', 'cancel:9002', 'cancel:9003']);
      expect(bridge.reminders.keys.toSet(), {9001, 9002, 9003});
    });

    test('past reminder times are skipped; expired / free users get none', () async {
      final bridge = FakeNativeBridge();
      final soon = ProfileService()
        ..isPro = true
        ..proUntil = now.add(const Duration(days: 2));
      final times = await syncRemindersForTest(soon, bridge, now);
      expect(times.length, 2, reason: '3-day reminder is already in the past');
      expect(bridge.reminders.containsKey(9001), isFalse);

      final expired = ProfileService()
        ..isPro = true
        ..proUntil = now.subtract(const Duration(days: 1));
      expect(await syncRemindersForTest(expired, bridge, now), isEmpty);
      expect(bridge.reminders, isEmpty, reason: 'old reminders were cancelled');
      expect(await syncRemindersForTest(ProfileService(), bridge, now), isEmpty);
    });

    test('unsupported platform schedules nothing', () async {
      final bridge = FakeNativeBridge(supported: false);
      final p = ProfileService()
        ..isPro = true
        ..proUntil = now.add(const Duration(days: 20));
      expect(await syncRemindersForTest(p, bridge, now), isEmpty);
      expect(bridge.reminders, isEmpty);
    });
  });

  group('background service coordinator', () {
    test('media wins over downloads; stops when both are gone', () async {
      final bridge = FakeNativeBridge();
      final bg = BackgroundCoordinator(bridge);
      bg.setDownloads(const DownloadSummary(active: 2, progress: 40, title: 'film.mp4'));
      await Future<void>.delayed(Duration.zero);
      expect(bridge.foregrounds.last['kind'], 'download');
      expect(bridge.foregrounds.last['title'], 'Yuklanmoqda: 2 ta');
      expect(bridge.foregrounds.last['progress'], 40);

      bg.setMedia(const MediaInfo(title: 'Qo\'shiq', subtitle: '1 / 3', playing: true));
      await Future<void>.delayed(Duration.zero);
      expect(bridge.foregrounds.last['kind'], 'media');
      expect(bridge.foregrounds.last['playing'], true);
      expect(bg.running, isTrue);

      bg.setMedia(null);
      await Future<void>.delayed(Duration.zero);
      expect(bridge.foregrounds.last['kind'], 'download', reason: 'back to the download notification');

      bg.setDownloads(null);
      await Future<void>.delayed(Duration.zero);
      expect(bridge.calls.last, 'stopForeground');
      expect(bg.running, isFalse);
    });

    test('identical updates are not re-sent', () async {
      final bridge = FakeNativeBridge();
      final bg = BackgroundCoordinator(bridge);
      const d = DownloadSummary(active: 1, progress: 10, title: 'a.mp4');
      bg.setDownloads(d);
      bg.setDownloads(d);
      await Future<void>.delayed(Duration.zero);
      expect(bridge.foregrounds.length, 1);
      bg.setDownloads(const DownloadSummary(active: 1, progress: 11, title: 'a.mp4'));
      await Future<void>.delayed(Duration.zero);
      expect(bridge.foregrounds.length, 2);
    });
  });

  test('without native support the bridge does nothing and never throws', () async {
    final noop = NoopNativeBridge();
    expect(noop.supported, isFalse);
    expect(await noop.showForeground(kind: 'media', title: 'a', text: 'b'), isFalse);
    expect(await noop.enterPip(), isFalse);
    expect(await noop.pinShortcut('X'), isFalse);
    await noop.stopForeground();
  });
}

// reminders.dart dagi funksiya (import takrorlanmasligi uchun)
Future<List<DateTime>> syncRemindersForTest(ProfileService p, NativeBridge b, DateTime now) =>
    syncReminders(p, b, now: now);
