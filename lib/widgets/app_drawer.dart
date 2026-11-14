import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_theme.dart';
import '../config.dart';
import '../screens/admin_screen.dart';
import '../screens/auth_screen.dart';
import '../screens/subscription_screen.dart';
import '../screens/theme_screen.dart';
import '../services/app_name.dart';
import '../services/profile_service.dart';

// ================= CHAP MENYU (3 TA CHIZIQ) =================
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  void _open(BuildContext context, Widget screen) {
    Navigator.pop(context);
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  /// Telefon ilovasini qo'llab-quvvatlash raqami bilan ochadi
  Future<void> _callSupport(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    bool opened = false;
    try {
      opened = await launchUrl(Uri(scheme: 'tel', path: supportPhone));
    } catch (_) {}
    if (!opened) {
      await Clipboard.setData(const ClipboardData(text: supportPhone));
      messenger.showSnackBar(
        const SnackBar(content: Text("Telefon ilovasi ochilmadi. Raqam nusxalandi: $supportPhone")),
      );
    }
  }

  /// PRO: ilova nomini o'zgartirish
  Future<void> _rename(BuildContext context) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (!profile.proActive) {
      navigator.pop();
      messenger.showSnackBar(SnackBar(
        content: const Text("Ilova nomini o'zgartirish faqat PRO obunachilar uchun"),
        action: SnackBarAction(
          label: "PRO olish",
          onPressed: () => navigator.push(MaterialPageRoute(builder: (_) => const SubscriptionScreen())),
        ),
      ));
      return;
    }
    final controller = TextEditingController(text: appNameService.displayName);
    final String? entered = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Ilova nomi"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const Key("appNameField"),
              controller: controller,
              maxLength: AppNameService.maxLength,
              autofocus: true,
              decoration: const InputDecoration(labelText: "Yangi nom"),
            ),
            const Text(
              "Nom ilova ichida o'zgaradi. Android'da asosiy ekranga yangi nomli yorliq qo'shish so'raladi: "
              "ilovaning asl belgisi nomini tizim o'zgartirishga ruxsat bermaydi.",
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text("Bekor qilish")),
          TextButton(
            key: const Key("appNameReset"),
            onPressed: () => Navigator.pop(dialogContext, appName),
            child: const Text("Asl nom"),
          ),
          FilledButton(key: const Key("appNameSave"), onPressed: () => Navigator.pop(dialogContext, controller.text), child: const Text("Saqlash")),
        ],
      ),
    );
    if (entered == null) return;
    final result = await appNameService.rename(entered);
    navigator.pop();
    messenger.showSnackBar(SnackBar(
      content: Text(result.ok
          ? (result.shortcutRequested
              ? "Nom o'zgardi. Asosiy ekranga yorliq qo'shishni tasdiqlang."
              : "Nom o'zgardi: ${appNameService.displayName}")
          : (result.problem ?? "Nomni o'zgartirib bo'lmadi")),
    ));
  }

  Future<void> _signOut(BuildContext context) async {
    final navigator = Navigator.of(context);
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Chiqish"),
        content: const Text("Akkauntdan chiqmoqchimisiz?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text("Bekor qilish")),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text("Chiqish")),
        ],
      ),
    );
    if (confirmed != true) return;
    await profile.signOut();
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListenableBuilder(
        listenable: Listenable.merge([profile, themeController, appNameService]),
        builder: (context, _) {
          final scheme = Theme.of(context).colorScheme;
          return Column(
            children: [
              _header(context, scheme),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    ListTile(
                      leading: const Icon(Icons.palette_rounded),
                      title: const Text("Ilova mavzusi"),
                      subtitle: Text(themeController.current.name),
                      onTap: () => _open(context, const ThemeScreen()),
                    ),
                    ListTile(
                      leading: Icon(Icons.workspace_premium_rounded, color: Colors.amber.shade600),
                      title: const Text("PRO obuna"),
                      subtitle: Text(profile.proLabel),
                      onTap: () => _open(context, const SubscriptionScreen()),
                    ),
                    ListTile(
                      key: const Key("renameApp"),
                      leading: const Icon(Icons.drive_file_rename_outline_rounded),
                      title: const Text("Ilova nomini o'zgartirish"),
                      subtitle: Text(profile.proActive ? appNameService.displayName : "Faqat PRO obunachilar uchun"),
                      trailing: profile.proActive ? null : const Icon(Icons.lock_outline_rounded, size: 18),
                      onTap: () => _rename(context),
                    ),
                    ListTile(
                      leading: const Icon(Icons.support_agent_rounded),
                      title: const Text("Qo'llab-quvvatlash xizmati"),
                      subtitle: const Text(supportPhone),
                      onTap: () => _callSupport(context),
                    ),
                    if (adminPanelAvailable)
                      ListTile(
                        leading: const Icon(Icons.admin_panel_settings_rounded),
                        title: const Text("Admin panel"),
                        onTap: () => _open(context, const AdminPanelScreen()),
                      ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.logout_rounded),
                      title: const Text("Chiqish"),
                      onTap: () => _signOut(context),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  "Qurilma ID: ${profile.deviceId}",
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _header(BuildContext context, ColorScheme scheme) {
    return SizedBox(
      height: 190 + MediaQuery.of(context).padding.top,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            themeController.current.background,
            fit: BoxFit.cover,
            cacheWidth: 640,
            errorBuilder: (_, _, _) => ColoredBox(color: scheme.primaryContainer),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x33000000), Color(0xB3000000)],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 16, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                  child: Image.asset(
                    "assets/logo.png",
                    height: 64,
                    semanticLabel: appName,
                    errorBuilder: (_, _, _) => const Text(
                      appName,
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.black),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  profile.email.isEmpty ? "Mehmon" : profile.email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
