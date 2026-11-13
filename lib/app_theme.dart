import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ilova mavzusi: rang, yorug'lik va orqa fon rasmi.
class AppThemeSpec {
  final String id;
  final String name;
  final Color seed;
  final Brightness brightness;
  final String background;

  /// Matn o'qilishi uchun fon rasmi ustiga tushadigan parda qalinligi (0..1)
  final double scrim;

  const AppThemeSpec({
    required this.id,
    required this.name,
    required this.seed,
    required this.brightness,
    required this.background,
    required this.scrim,
  });
}

const List<AppThemeSpec> appThemes = [
  AppThemeSpec(
    id: "classic",
    name: "Klassik",
    seed: Color(0xFF1DE9B6),
    brightness: Brightness.dark,
    background: "assets/backgrounds/classic.jpg",
    scrim: 0.35,
  ),
  AppThemeSpec(
    id: "galaxy",
    name: "Tungi osmon",
    seed: Color(0xFF8C6BFF),
    brightness: Brightness.dark,
    background: "assets/backgrounds/galaxy.jpg",
    scrim: 0.45,
  ),
  AppThemeSpec(
    id: "aurora",
    name: "Shimol yog'dusi",
    seed: Color(0xFF2EE6C8),
    brightness: Brightness.dark,
    background: "assets/backgrounds/aurora.jpg",
    scrim: 0.50,
  ),
  AppThemeSpec(
    id: "sunset",
    name: "Quyosh botishi",
    seed: Color(0xFFFF7A59),
    brightness: Brightness.dark,
    background: "assets/backgrounds/sunset.jpg",
    scrim: 0.52,
  ),
  AppThemeSpec(
    id: "ocean",
    name: "Okean",
    seed: Color(0xFF29B6F6),
    brightness: Brightness.dark,
    background: "assets/backgrounds/ocean.jpg",
    scrim: 0.48,
  ),
  AppThemeSpec(
    id: "neon",
    name: "Neon",
    seed: Color(0xFFFF2E88),
    brightness: Brightness.dark,
    background: "assets/backgrounds/neon.jpg",
    scrim: 0.62,
  ),
  AppThemeSpec(
    id: "desert",
    name: "Sahro",
    seed: Color(0xFFFFA24C),
    brightness: Brightness.dark,
    background: "assets/backgrounds/desert.jpg",
    scrim: 0.58,
  ),
  AppThemeSpec(
    id: "forest",
    name: "O'rmon",
    seed: Color(0xFF2E7D5B),
    brightness: Brightness.light,
    background: "assets/backgrounds/forest.jpg",
    scrim: 0.55,
  ),
  AppThemeSpec(
    id: "sakura",
    name: "Sakura",
    seed: Color(0xFFD81B60),
    brightness: Brightness.light,
    background: "assets/backgrounds/sakura.jpg",
    scrim: 0.45,
  ),
  AppThemeSpec(
    id: "snow",
    name: "Qor",
    seed: Color(0xFF2F6FD0),
    brightness: Brightness.light,
    background: "assets/backgrounds/snow.jpg",
    scrim: 0.50,
  ),
];

/// Tanlangan mavzuni saqlaydi va o'zgarganda ilovani qayta chizadi.
class ThemeController extends ChangeNotifier {
  static const String _prefKey = "theme_id";

  AppThemeSpec _current = appThemes.first;
  AppThemeSpec get current => _current;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString(_prefKey);
      _current = appThemes.firstWhere((t) => t.id == id, orElse: () => appThemes.first);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> select(AppThemeSpec theme) async {
    if (theme.id == _current.id) return;
    _current = theme;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, theme.id);
    } catch (_) {}
  }
}

final ThemeController themeController = ThemeController();

ThemeData buildAppTheme(AppThemeSpec spec) {
  final scheme = ColorScheme.fromSeed(seedColor: spec.seed, brightness: spec.brightness);
  final glass = scheme.surface.withValues(alpha: 0.72);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: glass,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.45)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surface.withValues(alpha: 0.55),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface.withValues(alpha: 0.82),
      indicatorColor: scheme.primaryContainer,
      elevation: 0,
      height: 68,
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

/// Sahifa orqasiga mavzu rasmini qo'yadi va ustidan matn o'qiladigan parda tortadi.
class ThemedBackground extends StatelessWidget {
  final Widget child;
  final String? image;
  final double? scrim;
  const ThemedBackground({super.key, required this.child, this.image, this.scrim});

  @override
  Widget build(BuildContext context) {
    final spec = themeController.current;
    final scheme = Theme.of(context).colorScheme;
    final double veil = scrim ?? spec.scrim;
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: scheme.surface),
        Image.asset(
          image ?? spec.background,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                scheme.surface.withValues(alpha: veil * 0.75),
                scheme.surface.withValues(alpha: veil),
                scheme.surface.withValues(alpha: (veil + 0.18).clamp(0.0, 1.0)),
              ],
            ),
          ),
        ),
        child,
      ],
    );
  }
}

/// Fon rasmli tayyor sahifa qolipi.
class AppScaffold extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? drawer;
  final Widget? bottomNavigationBar;
  const AppScaffold({super.key, this.appBar, required this.body, this.drawer, this.bottomNavigationBar});

  @override
  Widget build(BuildContext context) {
    return ThemedBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: appBar,
        drawer: drawer,
        bottomNavigationBar: bottomNavigationBar,
        body: SafeArea(child: body),
      ),
    );
  }
}
