import 'package:any_to_any/app_theme.dart';
import 'package:any_to_any/main.dart';
import 'package:any_to_any/screens/home_screen.dart';
import 'package:any_to_any/screens/style_screen.dart';
import 'package:any_to_any/screens/theme_screen.dart';
import 'package:any_to_any/widgets/glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2200);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> freshPrefs([Map<String, Object> values = const {}]) async {
    SharedPreferences.setMockInitialValues({'user_email': 'ali@example.com', ...values});
    await themeController.load();
  }

  tearDown(() async {
    await freshPrefs({'ui_style': 'material', 'theme_id': 'classic'});
  });

  group('style is remembered', () {
    test('first launch: nothing chosen yet -> chooser needed; then it is stored', () async {
      await freshPrefs();
      expect(themeController.style, UiStyle.material);
      expect(themeController.needsStyleChoice, isTrue);
      await themeController.selectStyle(UiStyle.glass);
      expect(themeController.needsStyleChoice, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('ui_style'), 'glass');
      // keyingi ishga tushirish
      await themeController.load();
      expect(themeController.style, UiStyle.glass);
      expect(themeController.needsStyleChoice, isFalse);
    });

    test('an unknown stored value falls back to Material', () async {
      await freshPrefs({'ui_style': 'nonsense'});
      expect(themeController.style, UiStyle.material);
      expect(themeController.needsStyleChoice, isFalse);
    });
  });

  test('glass theme is translucent and rounded, material theme is untouched', () {
    final spec = appThemes.first;
    final glass = buildAppTheme(spec, style: UiStyle.glass);
    final material = buildAppTheme(spec);
    expect(glass.scaffoldBackgroundColor.a, 0);
    expect(glass.navigationBarTheme.backgroundColor!.a, 0);
    expect(glass.filledButtonTheme.style!.shape!.resolve({}), isA<StadiumBorder>());
    expect(material.scaffoldBackgroundColor.a, 1);
    expect(material.navigationBarTheme.backgroundColor!.a, lessThan(1));
    for (final t in appThemes) {
      expect(() => buildAppTheme(t, style: UiStyle.glass), returnsNormally, reason: t.id);
    }
  });

  testWidgets('after login the user is asked: plain Android or Liquid Glass', (tester) async {
    phone(tester);
    await freshPrefs();
    await tester.pumpWidget(const CoreApp(isLoggedIn: true));
    await settle(tester);
    expect(find.byType(StyleChooserScreen), findsOneWidget);
    expect(find.text('Oddiy Android'), findsOneWidget);
    expect(find.text('Liquid Glass'), findsOneWidget);
    final next = find.byKey(const Key('styleContinue'));
    expect(tester.widget<FilledButton>(next).onPressed, isNull, reason: 'must pick one first');

    await tester.tap(find.byKey(const Key('style_glass')));
    await settle(tester);
    expect(themeController.style, UiStyle.glass);
    expect(tester.widget<FilledButton>(next).onPressed, isNotNull);
    await tester.tap(next);
    await settle(tester);
    expect(find.byType(HomeScreen), findsOneWidget);
    // Liquid Glass: pastki panel va kartalar shisha
    expect(find.byType(GlassPanel), findsWidgets);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationDestination), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('choosing plain Android keeps ordinary cards', (tester) async {
    phone(tester);
    await freshPrefs();
    await tester.pumpWidget(const CoreApp(isLoggedIn: true));
    await settle(tester);
    await tester.tap(find.byKey(const Key('style_material')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('styleContinue')));
    await settle(tester);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(Card), findsWidgets);
    expect(find.byType(GlassPanel), findsNothing);
  });

  testWidgets('a user who already chose goes straight to the home screen', (tester) async {
    phone(tester);
    await freshPrefs({'ui_style': 'glass'});
    await tester.pumpWidget(const CoreApp(isLoggedIn: true));
    await settle(tester);
    expect(find.byType(StyleChooserScreen), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(GlassPanel), findsWidgets);
  });

  testWidgets('settings: the style can be switched later and the screen follows', (tester) async {
    phone(tester);
    await freshPrefs({'ui_style': 'material'});
    await tester.pumpWidget(ListenableBuilder(
      listenable: themeController,
      builder: (context, _) => MaterialApp(
        theme: buildAppTheme(themeController.current, style: themeController.style),
        home: const ThemeScreen(),
      ),
    ));
    await settle(tester);
    expect(find.text("Ko'rinish uslubi"), findsOneWidget);
    expect(find.text('Rang va fon'), findsOneWidget);
    expect(uiStyleOf(tester.element(find.byType(ThemeScreen))), UiStyle.material);
    await tester.tap(find.byKey(const Key('style_glass')));
    await settle(tester);
    expect(themeController.style, UiStyle.glass);
    expect(uiStyleOf(tester.element(find.byType(ThemeScreen))), UiStyle.glass, reason: 'the whole screen switched');
    await tester.tap(find.byKey(const Key('style_material')));
    await settle(tester);
    expect(themeController.style, UiStyle.material);
    expect(uiStyleOf(tester.element(find.byType(ThemeScreen))), UiStyle.material);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AppCard follows the active style', (tester) async {
    Future<void> show(UiStyle style) async {
      await freshPrefs({'ui_style': style.name});
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(appThemes.first, style: style),
        home: const Scaffold(body: Center(child: AppCard(child: Text('salom')))),
      ));
      await tester.pumpAndSettle(); // MaterialApp mavzuni 200 ms davomida silliq almashtiradi
    }

    await show(UiStyle.material);
    expect(find.byType(Card), findsOneWidget);
    expect(find.byType(GlassPanel), findsNothing);
    await show(UiStyle.glass);
    expect(find.byType(GlassPanel), findsOneWidget);
    expect(find.byType(Card), findsNothing);
    expect(find.text('salom'), findsOneWidget);
  });
}
