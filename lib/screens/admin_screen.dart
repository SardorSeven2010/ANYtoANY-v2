import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_theme.dart';
import '../config.dart';
import '../services/profile_service.dart';
import '../widgets/glass.dart';

// ================= ADMIN PANEL (PUL TASHLAGANLARGA PRO YOQISH) =================
// Bu oyna faqat Supabase'da is_admin = true qilingan akkauntga ko'rinadi.
// Boshqa foydalanuvchilar serverdagi qoidalar (RLS) tufayli hech narsani o'zgartira olmaydi.
class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  List<Map<String, dynamic>> _users = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  void _show(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _loadUsers() async {
    setState(() => _loading = true);
    try {
      final data = await Supabase.instance.client
          .from('user_profiles')
          .select()
          .order('payment_requested', ascending: false)
          .order('updated_at', ascending: false);
      if (mounted) setState(() => _users = List<Map<String, dynamic>>.from(data));
    } catch (e) {
      _show("Ro'yxatni yuklab bo'lmadi: $e");
    }
    if (mounted) setState(() => _loading = false);
  }

  bool _isActive(Map<String, dynamic> user) => isProActive(user);

  Future<void> _update(Map<String, dynamic> user, Map<String, dynamic> values, String done) async {
    try {
      final updated = await Supabase.instance.client
          .from('user_profiles')
          .update(values)
          .eq('id', user['id'].toString())
          .select('id');
      if (updated.isEmpty) {
        _show("O'zgartirib bo'lmadi: admin huquqi yo'q.");
        return;
      }
      _show(done);
    } catch (e) {
      _show("O'zgartirib bo'lmadi: $e");
      return;
    }
    await _loadUsers();
  }

  /// PRO ni [months] oyga yoqadi. Obuna hali faol bo'lsa, muddat uning ustiga qo'shiladi.
  Future<void> _grant(Map<String, dynamic> user, int months) async {
    final values = grantProValues(user, months);
    await _update(user, values, "PRO ${formatDate(DateTime.parse(values['pro_until']))} gacha yoqildi.");
  }

  Future<void> _revoke(Map<String, dynamic> user) async {
    await _update(user, revokeProValues, "PRO o'chirildi.");
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      appBar: AppBar(
        title: const Text("Admin: foydalanuvchilar"),
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _loadUsers),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _users.isEmpty
              ? const Center(child: Text("Foydalanuvchilar topilmadi"))
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _users.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) => _userCard(_users[i]),
                ),
    );
  }

  Widget _userCard(Map<String, dynamic> user) {
    final scheme = Theme.of(context).colorScheme;
    final bool active = _isActive(user);
    final bool requested = user['payment_requested'] == true;
    final until = DateTime.tryParse((user['pro_until'] ?? "").toString());
    final requestedPlan = planById(user['payment_plan'] as String?);
    final int minutes = ((user['total_seconds'] as num?)?.toInt() ?? 0) ~/ 60;

    return AppCard(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: requested ? Colors.orange : scheme.outlineVariant.withValues(alpha: 0.45),
          width: requested ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    (user['email'] ?? "Noma'lum email").toString(),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  Icons.workspace_premium_rounded,
                  color: active ? Colors.amber.shade600 : scheme.onSurfaceVariant.withValues(alpha: 0.4),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              active
                  ? (until == null ? "PRO faol" : "PRO: ${formatDate(until)} gacha")
                  : "Bepul tarif",
            ),
            Text("Qurilma: ${user['android_id'] ?? '-'} • Ishlatgan: $minutes daqiqa",
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            if (requested) ...[
              const SizedBox(height: 6),
              Text(
                "To'lov so'rovi: ${requestedPlan == null ? "tarif ko'rsatilmagan" : "${requestedPlan.title} (${requestedPlan.priceLabel})"}"
                "\nMa'lumot: ${user['payment_info'] ?? '-'}",
                style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.w600),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final plan in proPlans)
                  plan.id == requestedPlan?.id && requested
                      ? FilledButton(
                          onPressed: () => _grant(user, plan.months),
                          child: Text("+${plan.title}"),
                        )
                      : OutlinedButton(
                          onPressed: () => _grant(user, plan.months),
                          child: Text("+${plan.title}"),
                        ),
                if (active || requested)
                  TextButton(
                    onPressed: () => _revoke(user),
                    child: Text(active ? "PRO o'chirish" : "So'rovni rad etish"),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Admin panel faqat admin akkauntga ko'rinadi
bool get adminPanelAvailable => profile.isAdmin;
