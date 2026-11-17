import 'dart:async';

import 'package:any_to_any/services/native_bridge.dart';

/// Android native qatlami o'rniga testlarda ishlatiladigan soxta ob'ekt
class FakeNativeBridge implements NativeBridge {
  FakeNativeBridge({this.supported = true, this.permissionGranted = true});

  @override
  final bool supported;
  bool permissionGranted;

  final StreamController<NativeEvent> controller = StreamController<NativeEvent>.broadcast();
  final List<String> calls = [];
  final Map<int, DateTime> reminders = {};
  final List<Map<String, Object?>> notifications = [];
  final List<Map<String, Object?>> foregrounds = [];
  bool pipArmed = false;
  int pipEntered = 0;
  String? pinned;

  void emit(String name, [Object? data]) => controller.add(NativeEvent(name, data));

  @override
  Stream<NativeEvent> get events => controller.stream;

  @override
  Future<bool> requestNotificationPermission() async {
    calls.add('requestNotificationPermission');
    return permissionGranted;
  }

  @override
  Future<bool> notificationsEnabled() async => permissionGranted;

  @override
  Future<void> notify({required int id, required String title, required String body, String channel = channelDownloads}) async {
    notifications.add({'id': id, 'title': title, 'body': body, 'channel': channel});
  }

  @override
  Future<void> scheduleReminder({required int id, required DateTime at, required String title, required String body}) async {
    reminders[id] = at;
    calls.add('schedule:$id:$title');
  }

  @override
  Future<void> cancelReminder(int id) async {
    reminders.remove(id);
    calls.add('cancel:$id');
  }

  @override
  Future<bool> showForeground({
    required String kind,
    required String title,
    required String text,
    int progress = -1,
    bool playing = false,
  }) async {
    foregrounds.add({'kind': kind, 'title': title, 'text': text, 'progress': progress, 'playing': playing});
    calls.add('foreground:$kind');
    return true;
  }

  @override
  Future<void> stopForeground() async {
    calls.add('stopForeground');
  }

  @override
  Future<bool> enterPip({int width = 16, int height = 9}) async {
    pipEntered++;
    return true;
  }

  @override
  Future<void> setPipArmed(bool armed, {int width = 16, int height = 9}) async {
    pipArmed = armed;
  }

  @override
  Future<bool> pinShortcut(String label) async {
    pinned = label;
    return true;
  }

  // ---- galereya va ovoz ----
  final List<Map<String, String?>> gallerySaves = [];
  String? Function(String path)? galleryResult; // null qaytarsa saqlab bo'lmadi
  double? systemVolume = 0.5;
  final List<double> volumeSets = [];

  @override
  Future<String?> saveToGallery({required String path, required String kind, String? name}) async {
    gallerySaves.add({'path': path, 'kind': kind, 'name': name});
    return galleryResult == null ? '/storage/emulated/0/Movies/CORE/${name ?? path.split('/').last}' : galleryResult!(path);
  }

  @override
  Future<double?> getSystemVolume() async => systemVolume;

  @override
  Future<void> setSystemVolume(double value) async {
    volumeSets.add(value);
    systemVolume = value;
  }

  /// Mini-brauzer WebView'ini fonda tirik tutish: (id, on) juftliklari
  final List<(int, bool)> webViewKeepAlives = [];

  @override
  Future<bool> webViewKeepAlive(int id, bool on) async {
    webViewKeepAlives.add((id, on));
    return true;
  }

  List<Map<String, Object?>>? ocrResult;

  @override
  Future<List<Map<String, Object?>>?> ocrImage(String path) async {
    calls.add('ocr:$path');
    return ocrResult;
  }
}
