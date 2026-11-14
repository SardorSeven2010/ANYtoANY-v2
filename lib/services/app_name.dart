import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import 'native_bridge.dart';
import 'profile_service.dart';

/// PRO obunachilar ilova nomini o'zlari uchun o'zgartira oladi.
/// Android ilovaning o'z belgisi nomini ish vaqtida o'zgartirishga ruxsat bermaydi, shuning uchun:
///  - ilova ichidagi nom (sarlavha, menyu) o'zgaradi;
///  - asosiy ekranga yangi nomli yorliq qo'shish so'raladi (Android, foydalanuvchi tasdiqlaydi).
/// Obuna tugasa, nom o'zi "CORE" ga qaytadi (tanlangan nom saqlanib turadi).
class AppNameService extends ChangeNotifier {
  AppNameService({ProfileService? profileService, NativeBridge? bridge})
      : _profile = profileService,
        _bridge = bridge;

  static const String _key = 'custom_app_name';
  static const int maxLength = 24;

  final ProfileService? _profile;
  final NativeBridge? _bridge;
  String? _custom;

  ProfileService get _p => _profile ?? profile;
  NativeBridge get _native => _bridge ?? nativeBridge;

  /// Saqlangan (PRO bo'lmasa ishlatilmaydigan) nom
  String? get customName => _custom;

  /// Hozir ko'rsatiladigan nom
  String get displayName {
    final c = _custom;
    return (c != null && c.isNotEmpty && _p.proActive) ? c : appName;
  }

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _custom = prefs.getString(_key);
      notifyListeners();
    } catch (_) {}
  }

  /// Nomni tekshiradi. Yaroqli bo'lsa null, aks holda sababi.
  static String? validate(String raw) {
    final name = raw.trim();
    if (name.isEmpty) return "Nom bo'sh bo'lishi mumkin emas";
    if (name.length > maxLength) return "Nom $maxLength belgidan oshmasin";
    if (RegExp(r'[\x00-\x1f]').hasMatch(name)) return "Nomda noto'g'ri belgilar bor";
    return null;
  }

  /// Nomni o'zgartiradi (faqat PRO). Natija: [RenameResult].
  Future<RenameResult> rename(String raw) async {
    if (!_p.proActive) return RenameResult.proRequired;
    final problem = validate(raw);
    if (problem != null) return RenameResult.invalid(problem);
    final name = raw.trim();
    _custom = name == appName ? null : name;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_custom == null) {
        await prefs.remove(_key);
      } else {
        await prefs.setString(_key, _custom!);
      }
    } catch (_) {}
    notifyListeners();
    // yangi nomli yorliq (faqat Android)
    final shortcut = _custom != null && await _native.pinShortcut(name);
    return RenameResult.done(shortcutRequested: shortcut);
  }

  Future<void> reset() async {
    _custom = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
    notifyListeners();
  }
}

class RenameResult {
  final bool ok;
  final bool needsPro;
  final String? problem;
  final bool shortcutRequested;
  const RenameResult._(this.ok, this.needsPro, this.problem, this.shortcutRequested);

  static const RenameResult proRequired = RenameResult._(false, true, null, false);
  factory RenameResult.invalid(String problem) => RenameResult._(false, false, problem, false);
  factory RenameResult.done({required bool shortcutRequested}) => RenameResult._(true, false, null, shortcutRequested);
}

final AppNameService appNameService = AppNameService();
