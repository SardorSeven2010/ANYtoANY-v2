import 'dart:async';

import 'package:flutter/services.dart';

import '../platform.dart';

/// Android'ning o'z imkoniyatlari (bildirishnoma, fon xizmati, PiP, yorliq) bilan aloqa.
/// Kod `installer/android/kotlin` ichida. Boshqa platformalarda hech narsa qilmaydi.
/// Testlarda [setNativeBridge] bilan soxta ob'ekt qo'yiladi.

const String channelDownloads = 'core_downloads';
const String channelReminders = 'core_reminders';

/// Native tomondan kelgan hodisa: mediaAction (previous / playpause / next),
/// downloadsStop, pipChanged (data: bool)
class NativeEvent {
  final String name;
  final Object? data;
  const NativeEvent(this.name, [this.data]);

  @override
  String toString() => 'NativeEvent($name, $data)';
}

abstract class NativeBridge {
  /// Bu platformada native qatlam bormi (Android)
  bool get supported;
  Stream<NativeEvent> get events;

  Future<bool> requestNotificationPermission();
  Future<bool> notificationsEnabled();
  Future<void> notify({required int id, required String title, required String body, String channel = channelDownloads});
  Future<void> scheduleReminder({required int id, required DateTime at, required String title, required String body});
  Future<void> cancelReminder(int id);

  /// Fon xizmatini yoqadi yoki xabarini yangilaydi. kind: "media" yoki "download".
  Future<bool> showForeground({
    required String kind,
    required String title,
    required String text,
    int progress = -1,
    bool playing = false,
  });
  Future<void> stopForeground();

  /// Qalqib chiquvchi oyna (PiP)
  Future<bool> enterPip({int width = 16, int height = 9});

  /// true bo'lsa, foydalanuvchi "Home" ni bosganda video avtomatik qalqib chiquvchi oynaga o'tadi
  Future<void> setPipArmed(bool armed, {int width = 16, int height = 9});

  /// Asosiy ekranga berilgan nomli yorliq qo'shishni so'raydi (PRO)
  Future<bool> pinShortcut(String label);

  /// Faylni galereyaga (MediaStore) nusxalaydi. kind: video, audio yoki image.
  /// Qaytaradi: galereyadagi fayl yo'li (bo'lmasa null). Asl fayl o'chirilmaydi.
  Future<String?> saveToGallery({required String path, required String kind, String? name});

  /// Tizim media ovozi 0..1 (qo'llab-quvvatlanmasa null)
  Future<double?> getSystemVolume();
  Future<void> setSystemVolume(double value);

  /// Mini-brauzerdagi WebView ekran o'chganda ham "ko'rinadi" holatda ushlab turiladi (video ovozi to'xtamasligi uchun).
  /// [id] - WebView'ning native identifikatori. Qaytaradi: native qatlam WebView'ni topdimi.
  Future<bool> webViewKeepAlive(int id, bool on);
}

class NoopNativeBridge implements NativeBridge {
  @override
  bool get supported => false;
  @override
  Stream<NativeEvent> get events => const Stream.empty();
  @override
  Future<bool> requestNotificationPermission() async => false;
  @override
  Future<bool> notificationsEnabled() async => false;
  @override
  Future<void> notify({required int id, required String title, required String body, String channel = channelDownloads}) async {}
  @override
  Future<void> scheduleReminder({required int id, required DateTime at, required String title, required String body}) async {}
  @override
  Future<void> cancelReminder(int id) async {}
  @override
  Future<bool> showForeground({
    required String kind,
    required String title,
    required String text,
    int progress = -1,
    bool playing = false,
  }) async =>
      false;
  @override
  Future<void> stopForeground() async {}
  @override
  Future<bool> enterPip({int width = 16, int height = 9}) async => false;
  @override
  Future<void> setPipArmed(bool armed, {int width = 16, int height = 9}) async {}
  @override
  Future<bool> pinShortcut(String label) async => false;
  @override
  Future<String?> saveToGallery({required String path, required String kind, String? name}) async => null;
  @override
  Future<double?> getSystemVolume() async => null;
  @override
  Future<void> setSystemVolume(double value) async {}
  @override
  Future<bool> webViewKeepAlive(int id, bool on) async => false;
}

class MethodChannelNativeBridge implements NativeBridge {
  MethodChannelNativeBridge() {
    _channel.setMethodCallHandler((call) async {
      _events.add(NativeEvent(call.method, call.arguments));
      return null;
    });
  }

  final MethodChannel _channel = const MethodChannel('core/native');
  final StreamController<NativeEvent> _events = StreamController<NativeEvent>.broadcast();

  @override
  bool get supported => true;
  @override
  Stream<NativeEvent> get events => _events.stream;

  Future<T> _call<T>(String method, T fallback, [Map<String, Object?>? args]) async {
    try {
      final r = await _channel.invokeMethod<T>(method, args);
      return r ?? fallback;
    } catch (_) {
      return fallback;
    }
  }

  @override
  Future<bool> requestNotificationPermission() => _call('requestNotificationPermission', false);
  @override
  Future<bool> notificationsEnabled() => _call('notificationsEnabled', false);
  @override
  Future<void> notify({required int id, required String title, required String body, String channel = channelDownloads}) =>
      _call<bool>('notify', false, {'id': id, 'title': title, 'body': body, 'channel': channel});
  @override
  Future<void> scheduleReminder({required int id, required DateTime at, required String title, required String body}) =>
      _call<bool>('scheduleReminder', false, {'id': id, 'at': at.millisecondsSinceEpoch, 'title': title, 'body': body});
  @override
  Future<void> cancelReminder(int id) => _call<bool>('cancelReminder', false, {'id': id});
  @override
  Future<bool> showForeground({
    required String kind,
    required String title,
    required String text,
    int progress = -1,
    bool playing = false,
  }) =>
      _call('startForeground', false, {'kind': kind, 'title': title, 'text': text, 'progress': progress, 'playing': playing});
  @override
  Future<void> stopForeground() => _call<bool>('stopForeground', false);
  @override
  Future<bool> enterPip({int width = 16, int height = 9}) => _call('enterPip', false, {'width': width, 'height': height});
  @override
  Future<void> setPipArmed(bool armed, {int width = 16, int height = 9}) =>
      _call<bool>('setPipArmed', false, {'armed': armed, 'width': width, 'height': height});
  @override
  Future<bool> pinShortcut(String label) => _call('pinShortcut', false, {'label': label});
  @override
  Future<String?> saveToGallery({required String path, required String kind, String? name}) async {
    try {
      return await _channel.invokeMethod<String>('saveToGallery', {'path': path, 'kind': kind, 'name': name});
    } catch (_) {
      return null;
    }
  }

  @override
  Future<double?> getSystemVolume() async {
    try {
      return await _channel.invokeMethod<double>('getVolume');
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> setSystemVolume(double value) => _call<bool>('setVolume', false, {'value': value});
  @override
  Future<bool> webViewKeepAlive(int id, bool on) => _call('webviewKeepAlive', false, {'id': id, 'on': on});
}

NativeBridge? _bridge;

/// Joriy platformaga mos native aloqa
NativeBridge get nativeBridge => _bridge ??= isAndroidApp ? MethodChannelNativeBridge() : NoopNativeBridge();

/// Testlar uchun almashtirish (null qaytaradi: standart holatga)
void setNativeBridge(NativeBridge? bridge) => _bridge = bridge;
