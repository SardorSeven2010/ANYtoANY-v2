import 'dart:async';

import 'package:anytoany_core/anytoany_core.dart';
import 'package:flutter/material.dart';

import 'auth_screen.dart';
import 'repository.dart';

/// "14.11.2026 09:30" ko'rinishidagi sana va vaqt
String formatDateTime(DateTime date) {
  final d = date.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return "${formatDate(d)} ${two(d.hour)}:${two(d.minute)}";
}

DateTime? _date(Object? value) => DateTime.tryParse((value ?? "").toString());

String _email(Map<String, dynamic> user) => (user['email'] ?? "Email yo'q").toString();

String proStatus(Map<String, dynamic> user) {
  if (!isProActive(user)) return "Bepul tarif";
  final until = _date(user['pro_until']);
  return until == null ? "PRO (muddatsiz)" : "PRO: ${formatDate(until)} gacha";
}

// ================= ADMIN ASOSIY OYNA =================
class AdminHome extends StatefulWidget {
  final AdminRepository repository;

  /// Avtomatik yangilanish oralig'i (sinovlarda o'chiriladi)
  final Duration? refreshEvery;
  const AdminHome({super.key, required this.repository, this.refreshEvery = const Duration(seconds: 30)});

  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> with WidgetsBindingObserver {
  List<Map<String, dynamic>> _users = [];
  bool _loading = true;
  String? _error;
  int _tab = 0;
  Set<String>? _knownRequests;
  Timer? _timer;

  AdminRepository get _repo => widget.repository;

  List<Map<String, dynamic>> get _requests => _users.where((u) => u['payment_requested'] == true).toList();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    final every = widget.refreshEvery;
    if (every != null) _timer = Timer.periodic(every, (_) => _load(silent: true));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load(silent: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  void _show(String text, {SnackBarAction? action}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), action: action, duration: const Duration(seconds: 5)));
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final users = await _repo.fetchProfiles();
      if (!mounted) return;
      final requestIds = {for (final u in users) if (u['payment_requested'] == true) u['id'].toString()};
      final known = _knownRequests;
      final fresh = known == null ? <String>{} : requestIds.difference(known);
      setState(() {
        _users = users;
        _error = null;
        _loading = false;
        _knownRequests = requestIds;
      });
      if (fresh.isNotEmpty) {
        final user = users.firstWhere((u) => fresh.contains(u['id'].toString()));
        _show(
          fresh.length == 1 ? "Yangi to'lov so'rovi: ${_email(user)}" : "${fresh.length} ta yangi to'lov so'rovi",
          action: SnackBarAction(label: "Ko'rish", onPressed: () => setState(() => _tab = 0)),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = "Ma'lumotlarni yuklab bo'lmadi. Internetni tekshiring.";
      });
    }
  }

  /// Profilni yangilaydi; muvaffaqiyatli bo'lsa "Qaytarish" tugmasi bilan xabar chiqaradi
  Future<void> _apply(Map<String, dynamic> user, Map<String, dynamic> values, String done) async {
    final id = user['id'].toString();
    final previous = {for (final key in values.keys) key: user[key]};
    try {
      final ok = await _repo.updateProfile(id, values);
      if (!ok) {
        _show("O'zgartirib bo'lmadi: admin huquqi yo'q");
        return;
      }
    } catch (_) {
      _show("O'zgartirib bo'lmadi. Internetni tekshiring.");
      return;
    }
    await _load(silent: true);
    _show(
      done,
      action: SnackBarAction(
        label: "Qaytarish",
        onPressed: () async {
          try {
            await _repo.updateProfile(id, previous);
          } catch (_) {}
          await _load(silent: true);
        },
      ),
    );
  }

  Future<void> grant(Map<String, dynamic> user, ProPlan plan) {
    final values = grantProValues(user, plan.months);
    return _apply(
      user,
      values,
      "${_email(user)}: PRO ${formatDate(DateTime.parse(values['pro_until']))} gacha yoqildi",
    );
  }

  Future<void> revoke(Map<String, dynamic> user, {bool reject = false}) {
    return _apply(
      user,
      reject ? const {'payment_requested': false} : revokeProValues,
      reject ? "${_email(user)}: so'rov rad etildi" : "${_email(user)}: PRO o'chirildi",
    );
  }

  Future<void> _signOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Chiqish"),
        content: const Text("Admin paneldan chiqmoqchimisiz?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("Bekor qilish")),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text("Chiqish")),
        ],
      ),
    );
    if (ok != true) return;
    await _repo.signOut();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => AdminAuthScreen(repository: _repo)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final requests = _requests;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
              child: Image.asset("assets/logo.png", height: 28, errorBuilder: (_, _, _) => const SizedBox()),
            ),
            const SizedBox(width: 10),
            const Text("Admin", style: TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
        actions: [
          IconButton(tooltip: "Yangilash", onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
          IconButton(tooltip: "Chiqish", onPressed: _signOut, icon: const Icon(Icons.logout_rounded)),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(
            icon: Badge(
              isLabelVisible: requests.isNotEmpty,
              label: Text("${requests.length}"),
              child: const Icon(Icons.payments_outlined),
            ),
            selectedIcon: const Icon(Icons.payments_rounded),
            label: "So'rovlar",
          ),
          const NavigationDestination(
            icon: Icon(Icons.people_outline_rounded),
            selectedIcon: Icon(Icons.people_rounded),
            label: "Foydalanuvchilar",
          ),
          const NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights_rounded),
            label: "Statistika",
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _errorView()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: switch (_tab) {
                    0 => _RequestsTab(requests: requests, home: this),
                    1 => _UsersTab(users: _users, home: this),
                    _ => _StatsTab(users: _users, home: this),
                  },
                ),
    );
  }

  Widget _errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 56),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text("Qayta urinish")),
          ],
        ),
      ),
    );
  }

  /// Foydalanuvchi haqida to'liq ma'lumot va boshqarish tugmalari
  void openUser(Map<String, dynamic> user) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) {
        final created = _date(user['created_at']);
        final updated = _date(user['updated_at']);
        final plan = planById(user['payment_plan'] as String?);
        final minutes = ((user['total_seconds'] as num?)?.toInt() ?? 0) ~/ 60;
        Widget row(String label, String value) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 130, child: Text(label, style: const TextStyle(color: Colors.white60))),
                  Expanded(child: SelectableText(value)),
                ],
              ),
            );
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_email(user), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                row("Holati", proStatus(user)),
                row("Qurilma", (user['android_id'] ?? "-").toString()),
                row("Ishlatgan", "$minutes daqiqa"),
                if (created != null) row("Ro'yxatdan o'tgan", formatDateTime(created)),
                if (updated != null) row("Oxirgi faollik", formatDateTime(updated)),
                if (plan != null) row("Tanlagan tarif", "${plan.title} (${plan.priceLabel})"),
                if ((user['payment_info'] ?? "").toString().isNotEmpty)
                  row("To'lov ma'lumoti", user['payment_info'].toString()),
                if (user['is_admin'] == true) row("Huquq", "Admin"),
                const SizedBox(height: 16),
                const Text("PRO yoqish / uzaytirish:", style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final p in proPlans)
                      FilledButton.tonal(
                        onPressed: () {
                          Navigator.pop(sheet);
                          grant(user, p);
                        },
                        child: Text("+${p.title}"),
                      ),
                  ],
                ),
                if (isProActive(user)) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                    onPressed: () {
                      Navigator.pop(sheet);
                      revoke(user);
                    },
                    icon: const Icon(Icons.block_rounded),
                    label: const Text("PRO ni o'chirish"),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

// ================= 1. TO'LOV SO'ROVLARI =================
class _RequestsTab extends StatelessWidget {
  final List<Map<String, dynamic>> requests;
  final _AdminHomeState home;
  const _RequestsTab({required this.requests, required this.home});

  @override
  Widget build(BuildContext context) {
    if (requests.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 120),
          Icon(Icons.check_circle_outline_rounded, size: 64, color: Colors.white38),
          SizedBox(height: 12),
          Center(child: Text("Yangi to'lov so'rovlari yo'q", style: TextStyle(fontSize: 16))),
          SizedBox(height: 6),
          Center(child: Text("Ro'yxat har 30 soniyada yangilanadi", style: TextStyle(color: Colors.white54))),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: requests.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) => _requestCard(context, requests[i]),
    );
  }

  Widget _requestCard(BuildContext context, Map<String, dynamic> user) {
    final scheme = Theme.of(context).colorScheme;
    final plan = planById(user['payment_plan'] as String?);
    final sent = _date(user['updated_at']);
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.primary.withValues(alpha: 0.6)),
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
                    _email(user),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                if (sent != null)
                  Text(formatDateTime(sent), style: const TextStyle(fontSize: 12, color: Colors.white54)),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                plan == null ? "Tarif ko'rsatilmagan" : "${plan.title} — ${plan.priceLabel}",
                style: TextStyle(color: scheme.primary, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 8),
            Text("To'lov ma'lumoti: ${(user['payment_info'] ?? '-')}"),
            Text("Hozir: ${proStatus(user)}", style: const TextStyle(color: Colors.white60)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (plan != null)
                  FilledButton.icon(
                    onPressed: () => home.grant(user, plan),
                    icon: const Icon(Icons.check_rounded),
                    label: Text("Tasdiqlash (+${plan.title})"),
                  ),
                OutlinedButton(
                  onPressed: () => home.openUser(user),
                  child: Text(plan == null ? "Muddat tanlash" : "Boshqa muddat"),
                ),
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                  onPressed: () => home.revoke(user, reject: true),
                  child: const Text("Rad etish"),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ================= 2. FOYDALANUVCHILAR =================
enum _UserFilter { all, pro, free, requested }

class _UsersTab extends StatefulWidget {
  final List<Map<String, dynamic>> users;
  final _AdminHomeState home;
  const _UsersTab({required this.users, required this.home});

  @override
  State<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<_UsersTab> {
  String _query = "";
  _UserFilter _filter = _UserFilter.all;

  List<Map<String, dynamic>> get _visible {
    final q = _query.trim().toLowerCase();
    return widget.users.where((u) {
      final matchesQuery = q.isEmpty ||
          _email(u).toLowerCase().contains(q) ||
          (u['android_id'] ?? "").toString().toLowerCase().contains(q);
      final matchesFilter = switch (_filter) {
        _UserFilter.all => true,
        _UserFilter.pro => isProActive(u),
        _UserFilter.free => !isProActive(u),
        _UserFilter.requested => u['payment_requested'] == true,
      };
      return matchesQuery && matchesFilter;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        TextField(
          decoration: const InputDecoration(
            hintText: "Email yoki qurilma bo'yicha qidirish",
            prefixIcon: Icon(Icons.search_rounded),
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          children: [
            for (final (f, label) in [
              (_UserFilter.all, "Hammasi"),
              (_UserFilter.pro, "PRO"),
              (_UserFilter.free, "Bepul"),
              (_UserFilter.requested, "So'rov"),
            ])
              ChoiceChip(
                label: Text(label),
                selected: _filter == f,
                onSelected: (_) => setState(() => _filter = f),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text("${visible.length} ta foydalanuvchi", style: const TextStyle(color: Colors.white54)),
        const SizedBox(height: 6),
        for (final u in visible)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Card(
              child: ListTile(
                onTap: () => widget.home.openUser(u),
                leading: CircleAvatar(
                  backgroundColor: isProActive(u) ? Colors.amber.shade600 : Colors.white12,
                  child: Icon(
                    u['is_admin'] == true ? Icons.shield_rounded : Icons.workspace_premium_rounded,
                    color: isProActive(u) ? Colors.black : Colors.white54,
                  ),
                ),
                title: Text(_email(u), maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  "${proStatus(u)} • ${((u['total_seconds'] as num?)?.toInt() ?? 0) ~/ 60} daqiqa",
                ),
                trailing: u['payment_requested'] == true
                    ? const Icon(Icons.payments_rounded, color: Colors.orangeAccent)
                    : const Icon(Icons.chevron_right_rounded),
              ),
            ),
          ),
      ],
    );
  }
}

// ================= 3. STATISTIKA =================
class _StatsTab extends StatelessWidget {
  final List<Map<String, dynamic>> users;
  final _AdminHomeState home;
  const _StatsTab({required this.users, required this.home});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final active = users.where((u) => isProActive(u, now: now)).toList();
    final requests = users.where((u) => u['payment_requested'] == true).length;
    final newWeek = users.where((u) {
      final created = _date(u['created_at']);
      return created != null && now.difference(created).inDays < 7;
    }).length;
    final expiring = active.where((u) {
      final until = _date(u['pro_until']);
      return until != null && until.difference(now).inDays < 7;
    }).toList()
      ..sort((a, b) => _date(a['pro_until'])!.compareTo(_date(b['pro_until'])!));
    final hours = users.fold<int>(0, (sum, u) => sum + ((u['total_seconds'] as num?)?.toInt() ?? 0)) ~/ 3600;

    final cards = [
      ("Jami foydalanuvchilar", "${users.length}", Icons.people_rounded),
      ("Faol PRO", "${active.length}", Icons.workspace_premium_rounded),
      ("Kutilayotgan so'rovlar", "$requests", Icons.payments_rounded),
      ("7 kunda yangi", "$newWeek", Icons.person_add_alt_1_rounded),
      ("7 kunda tugaydi", "${expiring.length}", Icons.timer_outlined),
      ("Jami foydalanish", "$hours soat", Icons.schedule_rounded),
    ];

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.3,
          children: [
            for (final (label, value, icon) in cards)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(icon, color: Theme.of(context).colorScheme.primary),
                      const Spacer(),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                      ),
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white60, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        const Text("Faol PRO — tariflar bo'yicha", style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              for (final plan in proPlans)
                ListTile(
                  dense: true,
                  title: Text("${plan.title} (${plan.priceLabel})"),
                  trailing: Text(
                    "${active.where((u) => u['payment_plan'] == plan.id).length}",
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ListTile(
                dense: true,
                title: const Text("Tarifsiz berilgan"),
                trailing: Text(
                  "${active.where((u) => planById(u['payment_plan'] as String?) == null).length}",
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text("Obunasi 7 kun ichida tugaydiganlar", style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (expiring.isEmpty)
          const Card(child: ListTile(title: Text("Hozircha yo'q")))
        else
          for (final u in expiring)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                child: ListTile(
                  onTap: () => home.openUser(u),
                  title: Text(_email(u), maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(proStatus(u)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                ),
              ),
            ),
      ],
    );
  }
}
