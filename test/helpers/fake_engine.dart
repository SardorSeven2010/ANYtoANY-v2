import 'dart:async';
import 'dart:typed_data';

import 'package:any_to_any/player/engine.dart';
import 'package:flutter/material.dart';

/// Haqiqiy pleyer o'rniga testlarda ishlatiladigan soxta dvigatel.
class FakeEngine implements PlayerEngine {
  FakeEngine({this.fileDuration = const Duration(seconds: 100)});

  final Duration fileDuration;
  final List<({String source, Duration start, bool play})> opened = [];
  final List<String> log = [];
  final List<Duration> seeks = [];

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  int? _w, _h;
  double rate = 1.0;
  DecoderMode? decoder;
  String activeDecoderName = 'no';
  Uint8List? screenshotBytes = Uint8List.fromList([137, 80, 78, 71]);
  Object? openError;
  BoxFit? lastFit;
  bool disposed = false;

  final _playingC = StreamController<bool>.broadcast(sync: true);
  final _positionC = StreamController<Duration>.broadcast(sync: true);
  final _durationC = StreamController<Duration>.broadcast(sync: true);
  final _completedC = StreamController<bool>.broadcast(sync: true);
  final _errorC = StreamController<String>.broadcast(sync: true);
  final _sizeC = StreamController<({int? width, int? height})>.broadcast(sync: true);

  @override
  bool get playing => _playing;
  @override
  Duration get position => _position;
  @override
  Duration get duration => _duration;
  @override
  int? get videoWidth => _w;
  @override
  int? get videoHeight => _h;

  @override
  Stream<bool> get playingStream => _playingC.stream;
  @override
  Stream<Duration> get positionStream => _positionC.stream;
  @override
  Stream<Duration> get durationStream => _durationC.stream;
  @override
  Stream<bool> get completedStream => _completedC.stream;
  @override
  Stream<String> get errorStream => _errorC.stream;
  @override
  Stream<({int? width, int? height})> get videoSizeStream => _sizeC.stream;

  void _setPlaying(bool v) {
    if (_playing == v) return;
    _playing = v;
    _playingC.add(v);
  }

  @override
  Future<void> open(String source, {Duration start = Duration.zero, bool play = true}) async {
    if (openError != null) throw openError!;
    opened.add((source: source, start: start, play: play));
    log.add('open:$source');
    _position = start;
    _positionC.add(start);
    _duration = fileDuration;
    _durationC.add(fileDuration);
    _completedC.add(false);
    _setPlaying(play);
  }

  @override
  Future<void> play() async {
    log.add('play');
    _setPlaying(true);
  }

  @override
  Future<void> pause() async {
    log.add('pause');
    _setPlaying(false);
  }

  @override
  Future<void> seek(Duration position) async {
    log.add('seek:${position.inSeconds}');
    seeks.add(position);
    _position = position;
    _positionC.add(position);
  }

  @override
  Future<void> setRate(double r) async {
    rate = r;
    log.add('rate:$r');
  }

  @override
  Future<void> setVolume(double percent) async {}

  @override
  Future<void> setDecoder(DecoderMode mode) async {
    decoder = mode;
    log.add('decoder:${mode.name}');
  }

  @override
  Future<String?> activeDecoder() async => activeDecoderName;

  @override
  Future<Uint8List?> screenshot() async => screenshotBytes;

  @override
  Widget buildVideo({BoxFit fit = BoxFit.contain}) {
    lastFit = fit;
    return const ColoredBox(key: Key('fakeVideo'), color: Colors.blueGrey);
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }

  // ---- testdan boshqarish ----
  void tick(Duration p) {
    _position = p;
    _positionC.add(p);
  }

  void finish() {
    _setPlaying(false);
    _completedC.add(true);
  }

  void failWith(String message) => _errorC.add(message);

  void setSize(int w, int h) {
    _w = w;
    _h = h;
    _sizeC.add((width: w, height: h));
  }
}
