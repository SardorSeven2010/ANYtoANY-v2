import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import 'device_id.dart';

/// Foydalanuvchi profili: PRO obuna holati, ishlatilgan vaqt va server bilan sinxronlash.
class ProfileService extends ChangeNotifier {
  String deviceId = "Aniqlanmoqda...";
  String email = "";
  int totalSeconds = 0;
  bool isPro = false;
  DateTime? proUntil;
  bool isAdmin = false;
  bool paymentRequested = false;
  String? paymentPlan;
  DateTime? trialStartedAt;

  Timer? _timer;
  int _ticks = 0;

  SupabaseClient? get _client {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  String? get userId => _client?.auth.currentUser?.id;

  /// PRO yoqilgan va muddati tugamagan bo'lsa true
  bool get proActive => isPro && (proUntil == null || proUntil!.isAfter(DateTime.now()));

  /// Bepul sinov davri hozir davom etyaptimi (1 oy, yangi foydalanuvchiga)
  bool get trialActive {
    final started = trialStartedAt;
    if (started == null) return false;
    return isTrialActive({
      'trial_started_at': started.toIso8601String(),
      'is_pro': isPro,
      'pro_until': proUntil?.toIso8601String(),
    });
  }

  /// Sinov tugaguncha qolgan kun. Sinov bo'lmasa 0.
  int get trialDaysLeft {
    final started = trialStartedAt;
    final until = proUntil;
    if (!trialActive || started == null || until == null) return 0;
    return daysLeft(until);
  }

  /// Obuna tugashiga 3 kun yoki kam qolganmi (eslatma ko'rsatish uchun)
  bool get expiringSoon {
    final until = proUntil;
    if (!proActive || until == null) return false;
    return daysLeft(until) <= 3;
  }

  String get proLabel {
    if (!proActive) return "Bepul tarif";
    final until = proUntil;
    if (trialActive && until != null) return "Bepul sinov: ${daysLeft(until)} kun qoldi";
    return until == null ? "PRO faol" : "PRO: ${formatDate(until)} gacha";
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    deviceId = await deviceIdLoader();
    email = _client?.auth.currentUser?.email ?? prefs.getString('user_email') ?? "";
    final int localSec = prefs.getInt('total_seconds') ?? 0;
    if (localSec > totalSeconds) totalSeconds = localSec;
    isPro = prefs.getBool('is_pro') ?? false;
    proUntil = DateTime.tryParse(prefs.getString('pro_until') ?? "");
    trialStartedAt = DateTime.tryParse(prefs.getString('trial_started_at') ?? "");
    notifyListeners();

    await refreshFromServer();
  }

  /// Serverdagi profilni o'qiydi. Muvaffaqiyatli bo'lsa true qaytaradi.
  Future<bool> refreshFromServer() async {
    final client = _client;
    final uid = userId;
    if (client == null || uid == null) return false;
    try {
      final row = await client.from('user_profiles').select().eq('id', uid).maybeSingle();
      if (row == null) {
        // Shu akkaunt uchun qator bo'lmasa yaratiladi
        await client.from('user_profiles').upsert({
          'id': uid,
          'email': email,
          'android_id': deviceId,
          'total_seconds': totalSeconds,
        });
        // Yangi profilga server qoidasi 1 oylik sinov berishi mumkin: qaytadan o'qiymiz
        final created = await client.from('user_profiles').select().eq('id', uid).maybeSingle();
        if (created != null) {
          _apply(created);
        } else {
          isPro = false;
          proUntil = null;
          isAdmin = false;
          paymentRequested = false;
          paymentPlan = null;
          trialStartedAt = null;
        }
      } else {
        _apply(row);
      }
      await _cache();
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  void _apply(Map<String, dynamic> row) {
    final int serverSec = (row['total_seconds'] as num?)?.toInt() ?? 0;
    if (serverSec > totalSeconds) totalSeconds = serverSec;
    isPro = row['is_pro'] == true;
    proUntil = DateTime.tryParse((row['pro_until'] ?? "").toString());
    isAdmin = row['is_admin'] == true;
    paymentRequested = row['payment_requested'] == true;
    paymentPlan = row['payment_plan'] as String?;
    trialStartedAt = DateTime.tryParse((row['trial_started_at'] ?? "").toString());
  }

  Future<void> _cache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('total_seconds', totalSeconds);
    await prefs.setBool('is_pro', isPro);
    final until = proUntil;
    if (until == null) {
      await prefs.remove('pro_until');
    } else {
      await prefs.setString('pro_until', until.toIso8601String());
    }
    final trial = trialStartedAt;
    if (trial == null) {
      await prefs.remove('trial_started_at');
    } else {
      await prefs.setString('trial_started_at', trial.toIso8601String());
    }
  }

  void startTimer() {
    _timer ??= Timer.periodic(const Duration(seconds: 10), (_) async {
      totalSeconds += 10;
      _ticks++;
      notifyListeners();
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('total_seconds', totalSeconds);
      } catch (_) {}
      // Har 1 daqiqada serverga sinxronlanadi
      if (_ticks % 6 == 0) await syncToServer();
    });
  }

  void stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> syncToServer() async {
    final client = _client;
    final uid = userId;
    if (client == null || uid == null) return;
    try {
      final row = await client
          .from('user_profiles')
          .update({'total_seconds': totalSeconds, 'android_id': deviceId})
          .eq('id', uid)
          .select()
          .maybeSingle();
      if (row != null) {
        _apply(row);
        await _cache();
        notifyListeners();
      }
    } catch (_) {}
  }

  /// Mijoz kartaga pul o'tkazgach yuboradigan so'rov. Xato bo'lsa exception tashlaydi.
  Future<void> sendPaymentRequest(ProPlan plan, String info) async {
    final client = _client;
    final uid = userId;
    if (client == null || uid == null) {
      throw Exception("Avval ilovaga qaytadan kiring");
    }
    final request = {
      'payment_requested': true,
      'payment_info': info,
      'payment_plan': plan.id,
    };
    final updated = await client.from('user_profiles').update(request).eq('id', uid).select('id');
    if (updated.isEmpty) {
      await client.from('user_profiles').upsert({
        'id': uid,
        'email': email,
        'android_id': deviceId,
        'total_seconds': totalSeconds,
        ...request,
      });
    }
    paymentRequested = true;
    paymentPlan = plan.id;
    notifyListeners();
  }

  Future<void> signOut() async {
    stopTimer();
    await syncToServer();
    try {
      await _client?.auth.signOut();
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in ['total_seconds', 'is_pro', 'pro_until', 'trial_started_at', 'user_email', 'user_id', 'is_logged_in']) {
        await prefs.remove(key);
      }
    } catch (_) {}
    deviceId = "Aniqlanmoqda...";
    email = "";
    totalSeconds = 0;
    isPro = false;
    proUntil = null;
    isAdmin = false;
    paymentRequested = false;
    paymentPlan = null;
    trialStartedAt = null;
    _ticks = 0;
    notifyListeners();
  }
}

final ProfileService profile = ProfileService();

String formatUsage(int seconds) {
  final int h = seconds ~/ 3600;
  final int m = (seconds % 3600) ~/ 60;
  return h > 0 ? "$h soat $m daqiqa" : "$m daqiqa";
}
