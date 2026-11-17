import 'dart:async';

import 'package:any_to_any/services/audio_focus.dart';
import 'package:any_to_any/services/device_controls.dart';

/// Yorug'lik va ovozni boshqarishning soxta varianti
class FakeDeviceControls implements DeviceControls {
  FakeDeviceControls({this.systemVolume = true});

  double bright = 0.4;
  double? vol = 0.5;
  final bool systemVolume;
  final List<double> brightnessSets = [];
  final List<double> volumeSets = [];
  int brightnessResets = 0;

  @override
  Future<double> brightness() async => bright;

  @override
  Future<void> setBrightness(double value) async {
    bright = value;
    brightnessSets.add(value);
  }

  @override
  Future<void> resetBrightness() async => brightnessResets++;

  @override
  Future<double?> volume() async => systemVolume ? vol : null;

  @override
  Future<void> setVolume(double value) async {
    vol = value;
    volumeSets.add(value);
  }
}

/// Audio fokusning soxta varianti: testdan voqea yuboriladi
class FakeAudioFocus implements AudioFocus {
  final StreamController<AudioFocusEvent> controller = StreamController<AudioFocusEvent>.broadcast(sync: true);
  int activated = 0;
  int deactivated = 0;

  void emit(AudioFocusEvent e) => controller.add(e);

  @override
  Stream<AudioFocusEvent> get events => controller.stream;
  @override
  Future<void> activate() async => activated++;
  @override
  Future<void> deactivate() async => deactivated++;
}
