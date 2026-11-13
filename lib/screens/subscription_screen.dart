import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';
import '../config.dart';
import '../services/profile_service.dart';

// ================= PRO OBUNA =================
class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  final _infoController = TextEditingController();
  ProPlan _plan = proPlans.first;
  bool _sending = false;
  bool _refreshing = false;

  @override
  void dispose() {
    _infoController.dispose();
    super.dispose();
  }

  void _show(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _send() async {
    final info = _infoController.text.trim();
    if (info.isEmpty) {
      _show("Kartangiz oxirgi 4 raqami yoki ismingizni yozing.");
      return;
    }
    setState(() => _sending = true);
    try {
      await profile.sendPaymentRequest(_plan, info);
      _infoController.clear();
      _show("To'lov ma'lumoti yuborildi! Admin tasdiqlashi bilan PRO avtomatik yonadi.");
    } catch (e) {
      _show("Yuborib bo'lmadi. Internetni tekshirib, qayta urinib ko'ring.");
    }
    if (mounted) setState(() => _sending = false);
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    final ok = await profile.refreshFromServer();
    _show(ok ? profile.proLabel : "Serverga ulanib bo'lmadi.");
    if (mounted) setState(() => _refreshing = false);
  }

  /// Oyiga to'g'ri keladigan narx va 1 oylik tarifga nisbatan tejash
  String _planHint(ProPlan plan) {
    if (plan.months == 1) return "Har oy to'lanadi";
    final int perMonth = (plan.price / plan.months).round();
    final int saved = proPlans.first.price * plan.months - plan.price;
    return "Oyiga ${formatSom(perMonth)}\n${formatSom(saved)} tejaysiz";
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      appBar: AppBar(title: const Text("PRO obuna")),
      body: ListenableBuilder(
        listenable: profile,
        builder: (context, _) {
          final scheme = Theme.of(context).colorScheme;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _statusCard(scheme),
              const SizedBox(height: 14),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("PRO imkoniyatlari", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      _feature("Barcha video kodeklar: H.265, VP9, MPEG-4, tez ko'chirish (bepul tarifda faqat H.264)"),
                      _feature("PDF fayllarni Word, PowerPoint va Excel ga aylantirish"),
                      _feature("Bir vaqtda cheklanmagan sondagi fayl (bepul tarifda $freeFileLimit ta)"),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text("Tarifni tanlang", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              for (final plan in proPlans) ...[
                _planCard(plan, scheme),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 6),
              _paymentCard(scheme),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _refreshing ? null : _refresh,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text("PRO holatni yangilash"),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _statusCard(ColorScheme scheme) {
    final bool active = profile.proActive;
    final plan = planById(profile.paymentPlan);
    return Card(
      child: ListTile(
        leading: Icon(
          Icons.workspace_premium_rounded,
          size: 36,
          color: active ? Colors.amber.shade600 : scheme.onSurfaceVariant,
        ),
        title: Text(profile.proLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: profile.paymentRequested
            ? Text(
                "To'lov so'rovingiz tekshirilmoqda${plan == null ? "" : " (${plan.title} tarif)"}...",
                style: const TextStyle(color: Colors.orange),
              )
            : Text(active ? "Obunangiz faol" : "PRO obuna yoqilmagan"),
      ),
    );
  }

  Widget _feature(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_rounded, size: 20, color: Colors.green),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  Widget _planCard(ProPlan plan, ColorScheme scheme) {
    final bool selected = plan.id == _plan.id;
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: selected ? scheme.primary : scheme.outlineVariant.withValues(alpha: 0.45),
          width: selected ? 2 : 1,
        ),
      ),
      child: ListTile(
        onTap: () => setState(() => _plan = plan),
        leading: Icon(
          selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
          color: selected ? scheme.primary : scheme.onSurfaceVariant,
        ),
        title: Text(plan.title, style: const TextStyle(fontWeight: FontWeight.bold)),
        isThreeLine: plan.months > 1,
        subtitle: Text(_planHint(plan)),
        trailing: Text(
          plan.priceLabel,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: scheme.primary),
        ),
      ),
    );
  }

  Widget _paymentCard(ColorScheme scheme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              "To'lov: ${_plan.title} tarif — ${_plan.priceLabel}",
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text("Shu summani quyidagi kartaga o'tkazing:"),
            Row(
              children: [
                Expanded(
                  child: SelectableText(
                    cardNumber,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: scheme.primary),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy_rounded, size: 20),
                  tooltip: "Nusxalash",
                  onPressed: () {
                    Clipboard.setData(const ClipboardData(text: cardNumber));
                    _show("Karta raqam nusxalandi!");
                  },
                ),
              ],
            ),
            Text("Karta egasi: $cardOwner", style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 14),
            TextField(
              controller: _infoController,
              decoration: const InputDecoration(
                labelText: "Kartangiz oxirgi 4 raqami yoki ismingiz",
                hintText: "Masalan: 9860 / Ali",
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _sending ? null : _send,
              child: Text(_sending ? "Yuborilmoqda..." : "To'lov qildim"),
            ),
          ],
        ),
      ),
    );
  }
}
