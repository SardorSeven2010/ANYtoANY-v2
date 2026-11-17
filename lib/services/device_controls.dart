import 'package:screen_brightness/screen_brightness.dart';

import '../platform.dart';
import 'native_bridge.dart';

/// Pleyerdagi surish jestlari uchun: ekran yorug'ligi va ovoz.
/// Testlarda [setDeviceControls] bilan soxta ob'ekt qo'yiladi.
abstract class DeviceControls {
  /// Ilova oynasining yorug'ligi 0..1 (bilib bo'lmasa 0.5)
  Future<double> brightness();
  Future<void> setBrightness(double value);

  /// Pleyerdan chiqqanda yorug'lik avvalgi holatiga qaytadi
  Future<void> resetBrightness();

  /// Tizim media ovozi 0..1. null: bu qurilmada o'zgartirib bo'lmaydi (pleyer o'z ovozini ishlatadi)
  Future<double?> volume();
  Future<void> setVolume(double value);
}

class PlatformDeviceControls implements DeviceControls {
  bool get _brightnessSupported => isAndroidApp || isIOSApp || isWindowsApp;

  @override
  Future<double> brightness() async {
    if (!_brightnessSupported) return 0.5;
    try {
      return (await ScreenBrightness.instance.application).clamp(0.0, 1.0);
    } catch (_) {
      return 0.5;
    }
  }

  @override
  Future<void> setBrightness(double value) async {
    if (!_brightnessSupported) return;
    try {
      await ScreenBrightness.instance.setApplicationScreenBrightness(value.clamp(0.0, 1.0));
    } catch (_) {}
  }

  @override
  Future<void> resetBrightness() async {
    if (!_brightnessSupported) return;
    try {
      await ScreenBrightness.instance.resetApplicationScreenBrightness();
    } catch (_) {}
  }

  @override
  Future<double?> volume() => nativeBridge.getSystemVolume();

  @override
  Future<void> setVolume(double value) => nativeBridge.setSystemVolume(value.clamp(0.0, 1.0));
}

DeviceControls? _controls;
DeviceControls get deviceControls => _controls ??= PlatformDeviceControls();
void setDeviceControls(DeviceControls? controls) => _controls = controls;
