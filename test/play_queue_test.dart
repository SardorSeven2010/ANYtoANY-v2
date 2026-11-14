import 'dart:math';

import 'package:any_to_any/player/play_queue.dart';
import 'package:flutter_test/flutter_test.dart';

List<QueueItem> items(int n) => [for (var i = 0; i < n; i++) QueueItem(title: 'v$i.mp4', path: '/m/v$i.mp4')];

void main() {
  group('sequential (stop at the end)', () {
    test('plays through and stops after the last file', () {
      final q = PlayQueue(items(3));
      expect(q.index, 0);
      expect(q.next(auto: true), isTrue);
      expect(q.index, 1);
      expect(q.next(auto: true), isTrue);
      expect(q.index, 2);
      expect(q.next(auto: true), isFalse, reason: 'last file finished -> stop');
      expect(q.index, 2);
      expect(q.upNext, isNull);
    });

    test('manual previous/next at the edges do nothing', () {
      final q = PlayQueue(items(2));
      expect(q.previous(), isFalse);
      expect(q.index, 0);
      q.next();
      expect(q.next(), isFalse);
      expect(q.index, 1);
    });

    test('start index is respected and clamped', () {
      expect(PlayQueue(items(5), start: 3).index, 3);
      expect(PlayQueue(items(5), start: 99).index, 4);
      expect(PlayQueue(items(5), start: -4).index, 0);
    });
  });

  group('repeat', () {
    test('repeat all wraps around in both directions', () {
      final q = PlayQueue(items(3), start: 2)..repeat = RepeatMode.all;
      expect(q.next(auto: true), isTrue);
      expect(q.index, 0);
      expect(q.previous(), isTrue);
      expect(q.index, 2);
      expect(q.upNext!.title, 'v0.mp4');
    });

    test('repeat one replays the same file when it ends, but next still moves on', () {
      final q = PlayQueue(items(3), start: 1)..repeat = RepeatMode.one;
      expect(q.next(auto: true), isTrue);
      expect(q.index, 1, reason: 'same file again');
      expect(q.next(), isTrue);
      expect(q.index, 2, reason: 'user pressed Next');
      expect(q.next(), isTrue, reason: 'wraps in repeat-one on manual next');
      expect(q.index, 0);
    });

    test('a single file: repeat all keeps playing it, off stops', () {
      final q = PlayQueue(items(1));
      expect(q.next(auto: true), isFalse);
      q.repeat = RepeatMode.all;
      expect(q.next(auto: true), isTrue);
      expect(q.index, 0);
    });

    test('repeat button cycles off -> all -> one -> off', () {
      expect(nextRepeatMode(RepeatMode.off), RepeatMode.all);
      expect(nextRepeatMode(RepeatMode.all), RepeatMode.one);
      expect(nextRepeatMode(RepeatMode.one), RepeatMode.off);
    });
  });

  group('shuffle', () {
    test('keeps the current file first and plays every file exactly once', () {
      final q = PlayQueue(items(8), start: 3, random: Random(7))..shuffle = true;
      expect(q.index, 3);
      final seen = <int>[q.index];
      while (q.next(auto: true)) {
        seen.add(q.index);
      }
      expect(seen.length, 8);
      expect(seen.toSet().length, 8, reason: 'no file twice');
      expect(seen, isNot(equals([3, 4, 5, 6, 7, 0, 1, 2])), reason: 'actually shuffled (with this seed)');
    });

    test('turning shuffle off continues from the current file in list order', () {
      final q = PlayQueue(items(6), random: Random(3))..shuffle = true;
      q.next();
      q.next();
      final here = q.index;
      q.shuffle = false;
      expect(q.index, here);
      q.next();
      expect(q.index, here + 1 < 6 ? here + 1 : here);
    });

    test('previous walks back through the shuffled order', () {
      final q = PlayQueue(items(5), random: Random(11))..shuffle = true;
      final first = q.index;
      q.next();
      final second = q.index;
      q.next();
      expect(q.previous(), isTrue);
      expect(q.index, second);
      expect(q.previous(), isTrue);
      expect(q.index, first);
    });

    test('shuffle + repeat all reshuffles on wrap and the first file differs from the last played', () {
      final q = PlayQueue(items(6), random: Random(5))
        ..shuffle = true
        ..repeat = RepeatMode.all;
      for (var round = 0; round < 20; round++) {
        final seen = <int>{q.index};
        var last = q.index;
        for (var i = 0; i < 5; i++) {
          expect(q.next(auto: true), isTrue);
          seen.add(q.index);
          last = q.index;
        }
        expect(seen.length, 6, reason: 'round $round covers every file');
        expect(q.next(auto: true), isTrue);
        expect(q.index, isNot(last), reason: 'no immediate repeat across rounds');
      }
    });

    test('shuffle without repeat stops after everything was played once', () {
      final q = PlayQueue(items(4), random: Random(1))..shuffle = true;
      for (var i = 0; i < 3; i++) {
        expect(q.next(auto: true), isTrue);
      }
      expect(q.next(auto: true), isFalse);
    });
  });

  test('jumpTo selects the file (also while shuffled)', () {
    final q = PlayQueue(items(5), random: Random(2));
    q.jumpTo(3);
    expect(q.index, 3);
    q.shuffle = true;
    q.jumpTo(1);
    expect(q.index, 1);
    q.jumpTo(99);
    expect(q.index, 1, reason: 'out of range ignored');
  });

  test('items can resolve their path lazily (gallery assets)', () async {
    var calls = 0;
    final item = QueueItem(title: 'IMG_1', resolve: () async {
      calls++;
      return '/storage/IMG_1.mp4';
    });
    expect(await item.source(), '/storage/IMG_1.mp4');
    expect(calls, 1);
    expect(await const QueueItem(title: 'x', path: '/a/x.mp3').source(), '/a/x.mp3');
    expect(await const QueueItem(title: 'x').source(), isNull);
  });
}
