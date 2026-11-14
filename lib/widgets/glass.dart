import 'dart:ui';

import 'package:flutter/material.dart';

import '../app_theme.dart';

/// Liquid Glass uslubidagi shaffof, xiralashtirilgan panel:
/// orqadagi rasm xira ko'rinib turadi, chetida yorug' chiziq va yumshoq soya bor.
class GlassPanel extends StatelessWidget {
  final Widget child;
  final BorderRadius radius;
  final EdgeInsetsGeometry? padding;
  final double blur;

  /// Panelga rang berish (masalan, tanlangan tarif uchun). Shaffoflikda ishlatiladi.
  final Color? tint;

  const GlassPanel({
    super.key,
    required this.child,
    this.radius = const BorderRadius.all(Radius.circular(26)),
    this.padding,
    this.blur = 22,
    this.tint,
  });

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final Color base = Colors.white;
    Widget content = child;
    if (padding != null) content = Padding(padding: padding!, child: content);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: dark ? 0.32 : 0.14), blurRadius: 26, offset: const Offset(0, 10)),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  base.withValues(alpha: dark ? 0.20 : 0.58),
                  base.withValues(alpha: dark ? 0.06 : 0.26),
                ],
              ),
              border: Border.all(color: base.withValues(alpha: dark ? 0.30 : 0.75), width: 1.1),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: radius,
                color: tint,
                // yuqori chetdagi yorug'lik: shisha ustiga tushgan nur
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: const Alignment(0, -0.55),
                  colors: [base.withValues(alpha: dark ? 0.13 : 0.35), base.withValues(alpha: 0)],
                ),
              ),
              child: Material(type: MaterialType.transparency, child: content),
            ),
          ),
        ),
      ),
    );
  }
}

/// `Card` o'rniga ishlatiladi: oddiy uslubda Material kartasi, Liquid Glass uslubida shisha panel.
class AppCard extends StatelessWidget {
  final Widget child;
  final Color? color;
  final EdgeInsetsGeometry? margin;
  final ShapeBorder? shape;
  final Clip? clipBehavior;
  final double? elevation;

  const AppCard({super.key, required this.child, this.color, this.margin, this.shape, this.clipBehavior, this.elevation});

  @override
  Widget build(BuildContext context) {
    if (uiStyleOf(context) != UiStyle.glass) {
      return Card(color: color, margin: margin, shape: shape, clipBehavior: clipBehavior, elevation: elevation, child: child);
    }
    BorderRadius radius = BorderRadius.circular(26);
    final s = shape;
    if (s is RoundedRectangleBorder && s.borderRadius is BorderRadius) radius = s.borderRadius as BorderRadius;
    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: GlassPanel(
        radius: radius,
        // Oddiy kartalar uchun berilgan rang shisha ustiga yengil bo'yoq bo'lib tushadi
        tint: color?.withValues(alpha: 0.22),
        child: child,
      ),
    );
  }
}

/// Pastki bo'limlar paneli. Liquid Glass uslubida suzuvchi shisha tabletka shaklida.
class AppNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<NavigationDestination> destinations;

  const AppNavBar({super.key, required this.selectedIndex, required this.onSelected, required this.destinations});

  @override
  Widget build(BuildContext context) {
    final bar = NavigationBar(selectedIndex: selectedIndex, onDestinationSelected: onSelected, destinations: destinations);
    if (uiStyleOf(context) != UiStyle.glass) return bar;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: GlassPanel(radius: BorderRadius.circular(32), blur: 26, child: bar),
      ),
    );
  }
}
