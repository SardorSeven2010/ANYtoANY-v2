import 'package:any_to_any/app_theme.dart';
import 'package:any_to_any/main.dart';
import 'package:any_to_any/screens/home_screen.dart';
import 'package:any_to_any/screens/subscription_screen.dart';
import 'package:any_to_any/services/app_name.dart';
import 'package:any_to_any/services/background.dart';
import 'package:any_to_any/services/native_bridge.dart';
import 'package:any_to_any/services/profile_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fake_native.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeNativeBridge bridge;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'user_email': 'ali@example.com', 'ui_style': 'material'});
    await themeController.load();
    bridge = FakeNativeBridge();
    setNativeBridge(bridge);
    setBackgroundService(BackgroundCoordinator(bridge));
    profile
      ..isPro = false
      ..proUntil = null
      ..trialStartedAt = null;
    await appNameService.reset();
  });

  tearDown(() async {
    setNativeBridge(null);
    setBackgroundService(null);
    profile
      ..isPro = false
      ..proUntil = null;
    await appNameService.reset();
  });

  group('rename service', () {
    test('validation', () {
      expect(AppNameService.validate('Mening ilovam'), isNull);
      expect(AppNameService.validate('   '), isNotNull);
      expect(AppNameService.validate('a' * 25), contains('24'));
      expect(AppNameService.validate('a\nb'), isNotNull);
    });

    test('free users cannot rename', () async {
      final s = AppNameService(profileService: profile, bridge: bridge);
      final r = await s.rename('Yangi');
      expect(r.ok, isFalse);
      expect(r.needsPro, isTrue);
      expect(s.displayName, 'CORE');
      expect(bridge.pinned, isNull);
    });

    test('PRO: the name changes, is remembered and a home-screen shortcut is requested', () async {
      profile
        ..isPro = true
        ..proUntil = DateTime.now().add(const Duration(days: 30));
      final s = AppNameService(profileService: profile, bridge: bridge);
      final r = await s.rename('  Mening kinom  ');
      expect(r.ok, isTrue);
      expect(r.shortcutRequested, isTrue);
      expect(s.displayName, 'Mening kinom');
      expect(bridge.pinned, 'Mening kinom');
      // keyingi ishga tushirishda
      final again = AppNameService(profileService: profile, bridge: bridge);
      await again.load();
      expect(again.displayName, 'Mening kinom');
    });

    test('invalid names are refused and nothing is saved', () async {
      profile
        ..isPro = true
        ..proUntil = DateTime.now().add(const Duration(days: 30));
      final s = AppNameService(profileService: profile, bridge: bridge);
      final r = await s.rename('');
      expect(r.ok, isFalse);
      expect(r.problem, isNotNull);
      expect(s.displayName, 'CORE');
    });

    test('when PRO ends the name goes back to CORE; it returns with a new subscription', () async {
      profile
        ..isPro = true
        ..proUntil = DateTime.now().add(const Duration(days: 30));
      final s = AppNameService(profileService: profile, bridge: bridge);
      await s.rename('Mening kinom');
      profile.proUntil = DateTime.now().subtract(const Duration(days: 1));
      expect(s.displayName, 'CORE');
      expect(s.customName, 'Mening kinom', reason: 'kept for later');
      profile.proUntil = DateTime.now().add(const Duration(days: 30));
      expect(s.displayName, 'Mening kinom');
    });

    test('typing the original name resets it and asks for no shortcut', () async {
      profile
        ..isPro = true
        ..proUntil = DateTime.now().add(const Duration(days: 30));
      final s = AppNameService(profileService: profile, bridge: bridge);
      await s.rename('Boshqa');
      bridge.pinned = null;
      final r = await s.rename('CORE');
      expect(r.ok, isTrue);
      expect(r.shortcutRequested, isFalse);
      expect(s.customName, isNull);
      expect(bridge.pinned, isNull);
    });

    test('where shortcuts are unsupported the in-app name still changes', () async {
      profile
        ..isPro = true
        ..proUntil = DateTime.now().add(const Duration(days: 30));
      final s = AppNameService(profileService: profile, bridge: FakeNativeBridge(supported: false)..pinned = null);
      final noop = AppNameService(profileService: profile, bridge: NoopNativeBridge());
      final r = await noop.rename('Kompyuter nomi');
      expect(r.ok, isTrue);
      expect(r.shortcutRequested, isFalse);
      expect(noop.displayName, 'Kompyuter nomi');
      expect(s.displayName, 'CORE');
    });
  });

  group('screens', () {
    void phone(WidgetTester tester) {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
    }

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('drawer: free user is sent to PRO; PRO user renames and the title changes', (tester) async {
      phone(tester);
      await tester.pumpWidget(const CoreApp(isLoggedIn: true));
      await settle(tester);
      // bildirishnoma so'rovi: Android native qatlami bor, ruxsat berilmagan
      bridge.permissionGranted = false;
      await tester.pump(const Duration(milliseconds: 300));
      if (find.byKey(const Key('allowNotifications')).evaluate().isNotEmpty) {
        await tester.tap(find.text('Keyinroq'));
        await settle(tester);
      }
      expect(find.text('CORE'), findsWidgets);

      // 1) bepul
      await tester.tap(find.byIcon(Icons.menu));
      await settle(tester);
      expect(find.text('Faqat PRO obunachilar uchun'), findsWidgets);
      await tester.tap(find.byKey(const Key('renameApp')));
      await settle(tester);
      expect(find.textContaining('faqat PRO obunachilar uchun'), findsOneWidget);
      await tester.tap(find.text('PRO olish'));
      await settle(tester);
      expect(find.byType(SubscriptionScreen), findsOneWidget);
      await tester.pageBack();
      await settle(tester);
      await tester.pump(const Duration(seconds: 5)); // snackbar yo'qolsin

      // 2) PRO
      profile
        ..isPro = true
        ..proUntil = DateTime.now().add(const Duration(days: 30))
        ..notifyListeners();
      await settle(tester);
      await tester.tap(find.byIcon(Icons.menu));
      await settle(tester);
      await tester.tap(find.byKey(const Key('renameApp')));
      await settle(tester);
      expect(find.text('Ilova nomi'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('appNameField')), 'Mening kinom');
      await tester.tap(find.byKey(const Key('appNameSave')));
      await settle(tester);
      expect(find.text('Mening kinom'), findsWidgets, reason: 'the home title shows the new name');
      expect(bridge.pinned, 'Mening kinom');
      expect(find.textContaining('yorliq'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('notifications on the home screen', () {
    void phone(WidgetTester tester) {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
    }

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('the permission is asked once, with an explanation', (tester) async {
      phone(tester);
      bridge.permissionGranted = false;
      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      await settle(tester);
      expect(find.text('Bildirishnomalar'), findsOneWidget);
      await tester.tap(find.byKey(const Key('allowNotifications')));
      await settle(tester);
      expect(bridge.calls, contains('requestNotificationPermission'));
      await tester.pumpWidget(const SizedBox());

      // ikkinchi marta so'ralmaydi
      bridge.calls.clear();
      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      await settle(tester);
      expect(find.text('Bildirishnomalar'), findsNothing);
      expect(bridge.calls, isNot(contains('requestNotificationPermission')));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('no question where the system has no native layer (desktop / iPhone)', (tester) async {
      phone(tester);
      setNativeBridge(FakeNativeBridge(supported: false));
      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      await settle(tester);
      expect(find.text('Bildirishnomalar'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('subscription reminders are scheduled when PRO is active', (tester) async {
      phone(tester);
      bridge.permissionGranted = true;
      profile
        ..isPro = true
        ..proUntil = DateTime.now().add(const Duration(days: 20));
      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      await settle(tester);
      profile.notifyListeners();
      await settle(tester);
      expect(bridge.reminders.keys.toSet(), {9001, 9002, 9003});
      await tester.pumpWidget(const SizedBox());
    });
  });
}
