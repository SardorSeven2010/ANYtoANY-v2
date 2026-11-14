import 'package:any_to_any/app_theme.dart';
import 'package:any_to_any/services/device_id.dart';
import 'package:any_to_any/services/profile_service.dart';
import 'package:any_to_any/widgets/trial_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProfileService fresh() => ProfileService();
  final now = DateTime(2026, 11, 14, 12);

  group('free trial in the profile', () {
    test('active trial: PRO with trial_started_at', () {
      final p = fresh()
        ..isPro = true
        ..trialStartedAt = DateTime.now().subtract(const Duration(days: 2))
        ..proUntil = DateTime.now().add(const Duration(days: 28, hours: 1));
      expect(p.proActive, isTrue);
      expect(p.trialActive, isTrue);
      expect(p.trialDaysLeft, inInclusiveRange(28, 29));
      expect(p.proLabel, startsWith('Bepul sinov:'));
      expect(p.expiringSoon, isFalse);
    });

    test('paid PRO is not shown as a trial', () {
      final p = fresh()
        ..isPro = true
        ..proUntil = DateTime.now().add(const Duration(days: 90));
      expect(p.trialActive, isFalse);
      expect(p.trialDaysLeft, 0);
      expect(p.proLabel, contains('gacha'));
    });

    test('ended trial = free tariff, remembered as used', () {
      final p = fresh()
        ..isPro = true
        ..trialStartedAt = DateTime.now().subtract(const Duration(days: 40))
        ..proUntil = DateTime.now().subtract(const Duration(days: 10));
      expect(p.proActive, isFalse);
      expect(p.trialActive, isFalse);
      expect(p.proLabel, 'Bepul tarif');
    });

    test('subscription ending in 3 days or less is flagged', () {
      final p = fresh()
        ..isPro = true
        ..proUntil = DateTime.now().add(const Duration(days: 2, hours: 5));
      expect(p.expiringSoon, isTrue);
      p.proUntil = DateTime.now().add(const Duration(days: 20));
      expect(p.expiringSoon, isFalse);
    });
  });

  group('trial banner text', () {
    test('trial running / expiring / ended / nothing', () {
      final trial = fresh()
        ..isPro = true
        ..trialStartedAt = now.subtract(const Duration(days: 5))
        ..proUntil = now.add(const Duration(days: 25));
      // proActive uses the real clock, so build dates around DateTime.now() for it
      trial
        ..trialStartedAt = DateTime.now().subtract(const Duration(days: 5))
        ..proUntil = DateTime.now().add(const Duration(days: 25, hours: 1));
      expect(TrialBanner.messageFor(trial), allOf(contains('Bepul sinov'), contains("12 000 so'm")));

      final expiring = fresh()
        ..isPro = true
        ..proUntil = DateTime.now().add(const Duration(days: 2, hours: 3));
      expect(TrialBanner.messageFor(expiring), contains('tugaydi'));

      final ended = fresh()
        ..isPro = true
        ..trialStartedAt = DateTime.now().subtract(const Duration(days: 40))
        ..proUntil = DateTime.now().subtract(const Duration(days: 9));
      expect(TrialBanner.messageFor(ended), contains('Bepul sinov tugadi'));

      expect(TrialBanner.messageFor(fresh()), isNull, reason: 'a new free user with no trial sees nothing');
      final paid = fresh()
        ..isPro = true
        ..proUntil = DateTime.now().add(const Duration(days: 100));
      expect(TrialBanner.messageFor(paid), isNull);
    });
  });

  group('PRO follows the e-mail on every device', () {
    test('another device loads PRO and the trial from the cached/server row', () async {
      // Server qatori: PRO va sinov akkauntga bog'liq, qurilmaga emas.
      final until = DateTime.now().add(const Duration(days: 20));
      final started = DateTime.now().subtract(const Duration(days: 10));
      SharedPreferences.setMockInitialValues({
        'user_email': 'ali@example.com',
        'is_pro': true,
        'pro_until': until.toIso8601String(),
        'trial_started_at': started.toIso8601String(),
      });
      deviceIdLoader = () async => 'second-phone';
      final p = fresh();
      await p.load();
      expect(p.deviceId, 'second-phone');
      expect(p.email, 'ali@example.com');
      expect(p.proActive, isTrue);
      expect(p.trialActive, isTrue);
    });

    test('signing out clears PRO and trial from this device', () async {
      SharedPreferences.setMockInitialValues({'is_pro': true, 'trial_started_at': DateTime.now().toIso8601String()});
      deviceIdLoader = () async => 'phone';
      final p = fresh();
      await p.load();
      expect(p.isPro, isTrue);
      await p.signOut();
      expect(p.isPro, isFalse);
      expect(p.trialStartedAt, isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('is_pro'), isNull);
      expect(prefs.getString('trial_started_at'), isNull);
    });
  });

  testWidgets('banner is tappable and hidden when there is nothing to say', (tester) async {
    // global `profile` ni ishlatadi
    profile
      ..isPro = true
      ..trialStartedAt = DateTime.now().subtract(const Duration(days: 1))
      ..proUntil = DateTime.now().add(const Duration(days: 29, hours: 1));
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(appThemes.first),
      home: Scaffold(body: TrialBanner(onTap: () => taps++)),
    ));
    expect(find.textContaining('Bepul sinov'), findsOneWidget);
    await tester.tap(find.byKey(const Key('trialBanner')));
    expect(taps, 1);

    profile
      ..isPro = false
      ..trialStartedAt = null
      ..proUntil = null;
    profile.notifyListeners();
    await tester.pump();
    expect(find.byKey(const Key('trialBanner')), findsNothing);
  });

  test('generic device names never look like a real device', () {
    expect(unknownDevice, 'unknown_device');
  });
}
