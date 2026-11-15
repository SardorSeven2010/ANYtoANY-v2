import 'dart:async';

import 'package:audio_session/audio_session.dart';

import '../platform.dart';

/// Boshqa ilova (qo'ng'iroq, boshqa pleyer) ovozni olganda yoki quloqchin uzilganda pleyerni to'xtatish uchun.
enum AudioFocusEvent { pause, resume }

abstract class AudioFocus {
  /// Ijro boshlanganda: tizimga "musiqa pleyeri" ekanimizni aytadi (iPhone'da fonda ovoz uchun ham shart)
  Future<void> activate();
  Future<void> deactivate();
  Stream<AudioFocusEvent> get events;
}

class PlatformAudioFocus implements AudioFocus {
  final StreamController<AudioFocusEvent> _events = StreamController<AudioFocusEvent>.broadcast();
  final List<StreamSubscription<Object?>> _subs = [];
  bool _ready = false;

  @override
  Stream<AudioFocusEvent> get events => _events.stream;

  @override
  Future<void> activate() async {
    if (!isAndroidApp && !isIOSApp) return;
    try {
      final session = await AudioSession.instance;
      if (!_ready) {
        await session.configure(const AudioSessionConfiguration.music());
        _subs.addAll([
          session.interruptionEventStream.listen((e) {
            if (e.begin) {
              if (e.type == AudioInterruptionType.duck) return; // qisqa signal: ovoz o'zi pasayadi
              _events.add(AudioFocusEvent.pause);
            } else if (e.type == AudioInterruptionType.pause) {
              _events.add(AudioFocusEvent.resume);
            }
          }),
          session.becomingNoisyEventStream.listen((_) => _events.add(AudioFocusEvent.pause)),
        ]);
        _ready = true;
      }
      await session.setActive(true);
    } catch (_) {}
  }

  @override
  Future<void> deactivate() async {
    if (!_ready) return;
    try {
      final session = await AudioSession.instance;
      await session.setActive(false);
    } catch (_) {}
  }
}

AudioFocus? _focus;
AudioFocus get audioFocus => _focus ??= PlatformAudioFocus();
void setAudioFocus(AudioFocus? focus) => _focus = focus;
