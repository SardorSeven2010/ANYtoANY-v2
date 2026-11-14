import 'dart:io';

import 'package:android_id/android_id.dart';
import 'package:device_info_plus/device_info_plus.dart';

import '../platform.dart';

/// Qurilmani aniqlovchi qiymat. Bepul sinov (1 oy) bir qurilmaga bir marta beriladi.
/// Testlarda shu o'zgaruvchi soxta qiymat bilan almashtiriladi.
Future<String> Function() deviceIdLoader = _platformDeviceId;

/// Aniqlab bo'lmasa serverga yuboriladigan umumiy nomlar. Server ularga sinov bermaydi.
const String unknownDevice = "unknown_device";

Future<String> _platformDeviceId() async {
  try {
    if (isAndroidApp) {
      final id = await const AndroidId().getId();
      return (id == null || id.isEmpty) ? unknownDevice : id;
    }
    final info = DeviceInfoPlugin();
    if (isIOSApp) {
      final id = (await info.iosInfo).identifierForVendor;
      return (id == null || id.isEmpty) ? "iPhone" : "ios:$id";
    }
    if (isWindowsApp) {
      final w = await info.windowsInfo;
      return w.deviceId.isEmpty ? _hostName() : "win:${w.deviceId}";
    }
    if (isLinuxApp) {
      final id = (await info.linuxInfo).machineId;
      return (id == null || id.isEmpty) ? _hostName() : "linux:$id";
    }
  } catch (_) {}
  return isAndroidApp ? unknownDevice : _hostName();
}

String _hostName() {
  try {
    return "PC: ${Platform.localHostname}";
  } catch (_) {
    return "PC";
  }
}
