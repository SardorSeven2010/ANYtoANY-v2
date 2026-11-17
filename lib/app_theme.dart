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

/// Ko'rinish uslubi: oddiy Android (Material) yoki Liquid Glass (shisha).
enum UiStyle { material, glass }

/// Joriy uslubni ThemeData ichida olib yuradi: shunda uni o'qigan vidjetlar
/// uslub almashganda (const bo'lsa ham) o'zi qayta chiziladi.
class UiStyleExtension extends ThemeExtension<UiStyleExtension> {
  final UiStyle style;
  const UiStyleExtension(this.style);

  @override
  UiStyleExtension copyWith({UiStyle? style}) => UiStyleExtension(style ?? this.style);

  @override
  UiStyleExtension lerp(ThemeExtension<UiStyleExtension>? other, double t) =>
      other is UiStyleExtension && t >= 0.5 ? other : this;
}

/// Berilgan kontekstdagi ko'rinish uslubi
UiStyle uiStyleOf(BuildContext context) => Theme.of(context).extension<UiStyleExtension>()?.style ?? UiStyle.material;

/// Tanlangan mavzu va uslubni saqlaydi, o'zgarganda ilovani qayta chizadi.
class ThemeController extends ChangeNotifier {
  static const String _prefKey = "theme_id";
  static const String _styleKey = "ui_style";

  AppThemeSpec _current = appThemes.first;
  AppThemeSpec get current => _current;

  UiStyle _style = UiStyle.material;
  UiStyle get style => _style;

  // Saqlangan sozlamalar o'qilmaguncha so'ralmaydi (testlar va yuklanish paytida)
  bool _styleChosen = true;

  /// Foydalanuvchi uslubni hali tanlamagan bo'lsa true (kirgandan keyin tanlash oynasi chiqadi)
  bool get needsStyleChoice => !_styleChosen;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString(_prefKey);
      _current = appThemes.firstWhere((t) => t.id == id, orElse: () => appThemes.first);
      final styleName = prefs.getString(_styleKey);
      _styleChosen = styleName != null;
      _style = styleName == UiStyle.glass.name ? UiStyle.glass : UiStyle.material;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> selectStyle(UiStyle style) async {
    _styleChosen = true;
    if (style != _style) {
      _style = style;
    }
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_styleKey, style.name);
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

ThemeData buildAppTheme(AppThemeSpec spec, {UiStyle style = UiStyle.material}) {
  final scheme = ColorScheme.fromSeed(seedColor: spec.seed, brightness: spec.brightness);
  if (style == UiStyle.glass) return _buildGlassTheme(scheme);
  final glass = scheme.surface.withValues(alpha: 0.72);
  return ThemeData(
    useMaterial3: true,
    extensions: const [UiStyleExtension(UiStyle.material)],
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

/// Liquid Glass uslubi: shaffof sirtlar, yumaloq shakllar, yorug' chegaralar.
/// Kartalar va pastki panel [GlassPanel] bilan chiziladi (lib/widgets/glass.dart).
ThemeData _buildGlassTheme(ColorScheme scheme) {
  final bool dark = scheme.brightness == Brightness.dark;
  final Color edge = Colors.white.withValues(alpha: dark ? 0.30 : 0.75);
  final fieldFill = Colors.white.withValues(alpha: dark ? 0.10 : 0.40);
  OutlineInputBorder border(Color c, [double w = 1]) =>
      OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: c, width: w));
  final sheetColor = scheme.surface.withValues(alpha: dark ? 0.78 : 0.86);
  return ThemeData(
    useMaterial3: true,
    extensions: const [UiStyleExtension(UiStyle.glass)],
    colorScheme: scheme,
    scaffoldBackgroundColor: Colors.transparent,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
    ),
    cardTheme: CardThemeData(
      color: Colors.white.withValues(alpha: dark ? 0.10 : 0.45),
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26), side: BorderSide(color: edge)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: fieldFill,
      border: border(edge),
      enabledBorder: border(edge),
      focusedBorder: border(scheme.primary, 1.6),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: const StadiumBorder(),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(shape: const StadiumBorder(), side: BorderSide(color: edge)),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(shape: const StadiumBorder())),
    chipTheme: ChipThemeData(
      shape: const StadiumBorder(),
      side: BorderSide(color: edge),
      backgroundColor: fieldFill,
    ),
    // Pastki panel GlassPanel ichida chiziladi, shuning uchun o'zi shaffof
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Colors.white.withValues(alpha: dark ? 0.22 : 0.65),
      elevation: 0,
      height: 66,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: sheetColor,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32), side: BorderSide(color: edge)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: sheetColor,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: sheetColor,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: BorderSide(color: edge)),
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: sheetColor,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.horizontal(right: Radius.circular(32))),
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
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
    final bool glass = uiStyleOf(context) == UiStyle.glass;
    // Shisha uslubida rasm ko'proq ko'rinadi, ustiga yumshoq rangli nur tushadi
    final double veil = (scrim ?? spec.scrim) * (glass ? 0.6 : 1.0);
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
        if (glass) ...[
          Positioned(top: -120, left: -90, child: glow(scheme.primary.withValues(alpha: 0.38), 340)),
          Positioned(bottom: -140, right: -110, child: glow(scheme.tertiary.withValues(alpha: 0.32), 380)),
        ],
        child,
      ],
    );
  }

  static Widget glow(Color color, double size) => IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
          ),
        ),
      );
}

/// Mazmunning eng katta kengligi (kompyuterdagi keng oyna uchun)
const double maxContentWidth = 640;

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
        body: SafeArea(
          // Keng oynada (kompyuter) mazmun o'rtada, telefon kengligida turadi
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth <= maxContentWidth) return body;
              return Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: maxContentWidth),
                  child: body,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
