import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../config.dart';
import '../widgets/glass.dart';
import 'home_screen.dart';

/// Kirgandan keyin ko'rsatiladigan oyna: uslub tanlangan bo'lsa asosiy oyna, aks holda tanlash oynasi.
Widget postLoginScreen() => themeController.needsStyleChoice ? const StyleChooserScreen() : const HomeScreen();

// ================= KO'RINISH USLUBINI TANLASH =================
class StyleChooserScreen extends StatefulWidget {
  const StyleChooserScreen({super.key});

  @override
  State<StyleChooserScreen> createState() => _StyleChooserScreenState();
}

class _StyleChooserScreenState extends State<StyleChooserScreen> {
  UiStyle? _picked;

  void _continue() {
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: themeController,
      builder: (context, _) => ThemedBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "$appName ko'rinishini tanlang",
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: scheme.onSurface),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Keyinroq menyudagi \"Ilova mavzusi\" bo'limidan o'zgartirishingiz mumkin.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 22),
                      StyleOptions(selected: _picked, onSelect: (s) {
                        setState(() => _picked = s);
                        themeController.selectStyle(s);
                      }),
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          key: const Key("styleContinue"),
                          onPressed: _picked == null ? null : _continue,
                          child: const Text("Davom etish"),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Ikki variant yonma-yon: oddiy Android va Liquid Glass (kichik namuna bilan)
class StyleOptions extends StatelessWidget {
  final UiStyle? selected;
  final ValueChanged<UiStyle> onSelect;
  const StyleOptions({super.key, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _StyleTile(
            style: UiStyle.material,
            title: "Oddiy Android",
            caption: "Tekis, tanish Material ko'rinishi",
            selected: selected == UiStyle.material,
            onTap: () => onSelect(UiStyle.material),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _StyleTile(
            style: UiStyle.glass,
            title: "Liquid Glass",
            caption: "Shaffof shisha, xira fon va yumaloq shakllar",
            selected: selected == UiStyle.glass,
            onTap: () => onSelect(UiStyle.glass),
          ),
        ),
      ],
    );
  }
}

class _StyleTile extends StatelessWidget {
  final UiStyle style;
  final String title;
  final String caption;
  final bool selected;
  final VoidCallback onTap;
  const _StyleTile({
    required this.style,
    required this.title,
    required this.caption,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: title,
      child: GestureDetector(
        key: Key("style_${style.name}"),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: selected ? scheme.primary : Colors.transparent, width: 3),
          ),
          child: Column(
            children: [
              AspectRatio(aspectRatio: 0.62, child: ClipRRect(borderRadius: BorderRadius.circular(22), child: _MiniPhone(style: style))),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (selected) Icon(Icons.check_circle_rounded, size: 20, color: scheme.primary),
                  if (selected) const SizedBox(width: 4),
                  Flexible(
                    child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(caption, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Uslubning kichik namunasi: joriy mavzu rasmi ustida ikkita karta va pastki panel
class _MiniPhone extends StatelessWidget {
  final UiStyle style;
  const _MiniPhone({required this.style});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final spec = themeController.current;
    final glass = style == UiStyle.glass;

    Widget card(double height) {
      final radius = BorderRadius.circular(glass ? 16 : 10);
      if (glass) {
        return SizedBox(height: height, child: GlassPanel(radius: radius, blur: 10, child: const SizedBox.expand()));
      }
      return Container(
        height: height,
        decoration: BoxDecoration(color: scheme.surface.withValues(alpha: 0.9), borderRadius: radius),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: scheme.surface),
        Image.asset(spec.background, fit: BoxFit.cover, cacheWidth: 400, errorBuilder: (_, _, _) => const SizedBox.shrink()),
        ColoredBox(color: scheme.surface.withValues(alpha: glass ? 0.12 : 0.45)),
        if (glass) ...[
          Positioned(top: -30, left: -30, child: ThemedBackground.glow(scheme.primary.withValues(alpha: 0.5), 130)),
          Positioned(bottom: -40, right: -30, child: ThemedBackground.glow(scheme.tertiary.withValues(alpha: 0.45), 150)),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
          child: Column(
            children: [
              Container(
                height: 8,
                width: 54,
                decoration: BoxDecoration(color: scheme.onSurface.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(4)),
              ),
              const SizedBox(height: 12),
              card(44),
              const SizedBox(height: 8),
              card(44),
              const SizedBox(height: 8),
              card(30),
              const Spacer(),
              glass
                  ? SizedBox(
                      height: 34,
                      child: GlassPanel(
                        radius: BorderRadius.circular(18),
                        blur: 10,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [for (var i = 0; i < 3; i++) _dot(scheme, i == 0)],
                        ),
                      ),
                    )
                  : Container(
                      height: 34,
                      decoration: BoxDecoration(color: scheme.surface.withValues(alpha: 0.95), borderRadius: BorderRadius.circular(6)),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [for (var i = 0; i < 3; i++) _dot(scheme, i == 0)],
                      ),
                    ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _dot(ColorScheme scheme, bool active) => Container(
        width: active ? 22 : 12,
        height: 12,
        decoration: BoxDecoration(
          color: active ? scheme.primary : scheme.onSurface.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(6),
        ),
      );
}
