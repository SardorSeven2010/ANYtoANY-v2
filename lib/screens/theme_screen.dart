import 'package:flutter/material.dart';

import '../app_theme.dart';

// ================= ILOVA MAVZUSINI TANLASH =================
class ThemeScreen extends StatelessWidget {
  const ThemeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      appBar: AppBar(title: const Text("Ilova mavzusi")),
      body: ListenableBuilder(
        listenable: themeController,
        builder: (context, _) => GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            childAspectRatio: 0.72,
          ),
          itemCount: appThemes.length,
          itemBuilder: (context, i) => _ThemeTile(theme: appThemes[i]),
        ),
      ),
    );
  }
}

class _ThemeTile extends StatelessWidget {
  final AppThemeSpec theme;
  const _ThemeTile({required this.theme});

  @override
  Widget build(BuildContext context) {
    final bool selected = themeController.current.id == theme.id;
    final scheme = ColorScheme.fromSeed(seedColor: theme.seed, brightness: theme.brightness);
    return Material(
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => themeController.select(theme),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              theme.background,
              fit: BoxFit.cover,
              cacheWidth: 360,
              errorBuilder: (_, _, _) => ColoredBox(color: scheme.primaryContainer),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                color: scheme.surface.withValues(alpha: 0.82),
                child: Row(
                  children: [
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        theme.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: FontWeight.bold, color: scheme.onSurface),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (selected)
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
                  child: Icon(Icons.check_rounded, size: 20, color: scheme.onPrimary),
                ),
              ),
            if (selected)
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: scheme.primary, width: 3),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
