import 'dart:math';

/// Takrorlash rejimi: o'chiq (ro'yxat oxirida to'xtaydi), ro'yxatni takrorlash, bitta faylni takrorlash
enum QueueRepeat { off, all, one }

QueueRepeat nextQueueRepeat(QueueRepeat mode) => switch (mode) {
      QueueRepeat.off => QueueRepeat.all,
      QueueRepeat.all => QueueRepeat.one,
      QueueRepeat.one => QueueRepeat.off,
    };

/// Navbatdagi bitta fayl. Yo'l darhol ma'lum bo'lmasligi mumkin (galereya fayllari uchun [resolve]).
class QueueItem {
  final String title;
  final String? path;
  final Future<String?> Function()? resolve;
  const QueueItem({required this.title, this.path, this.resolve});

  Future<String?> source() async => path ?? await resolve?.call();

  /// Turini aniqlash uchun fayl nomi (kengaytma bo'yicha)
  String get nameForType => path ?? title;
}

/// Ijro navbati: ketma-ket, aralashtirish va takrorlash qoidalari.
/// Faqat mantiq: pleyerning o'zidan mustaqil, shuning uchun alohida sinaladi.
class PlayQueue {
  PlayQueue(List<QueueItem> items, {int start = 0, Random? random})
      : assert(items.isNotEmpty),
        _items = List.of(items),
        _random = random ?? Random() {
    _order = List<int>.generate(_items.length, (i) => i);
    _pos = start.clamp(0, _items.length - 1);
  }

  final List<QueueItem> _items;
  final Random _random;
  late List<int> _order;
  late int _pos;
  bool _shuffle = false;

  QueueRepeat repeat = QueueRepeat.off;

  List<QueueItem> get items => List.unmodifiable(_items);
  int get length => _items.length;

  /// Hozirgi faylning ro'yxatdagi tartib raqami (0 dan)
  int get index => _order[_pos];
  QueueItem get current => _items[index];
  bool get shuffle => _shuffle;

  /// Aralashtirish: hozirgi fayl o'z joyida qoladi, qolganlari tasodifiy tartibda keladi.
  set shuffle(bool value) {
    if (value == _shuffle) return;
    final cur = index;
    _shuffle = value;
    if (value) {
      _order = _shuffledOrder(first: cur);
      _pos = 0;
    } else {
      _order = List<int>.generate(_items.length, (i) => i);
      _pos = cur;
    }
  }

  List<int> _shuffledOrder({required int first, int? notFirst}) {
    final rest = [for (var i = 0; i < _items.length; i++) if (i != first) i]..shuffle(_random);
    if (notFirst != null && rest.length > 1 && rest.first == notFirst) {
      // yangi aylanishning birinchi fayli oxirgi o'ynalgan bilan bir xil bo'lib qolmasin
      final swap = 1 + _random.nextInt(rest.length - 1);
      final t = rest[0];
      rest[0] = rest[swap];
      rest[swap] = t;
    }
    return [first, ...rest];
  }

  /// Keyingi faylga o'tadi. [auto] true bo'lsa fayl o'zi tugagan (shunda "bittasini takrorlash" amal qiladi).
  /// Qaytaradi: hozirgi fayl (yoki yangisi) ijro etilsin (true) yoki ro'yxat tugadi (false).
  bool next({bool auto = false}) {
    if (auto && repeat == QueueRepeat.one) return true;
    if (_pos + 1 < _order.length) {
      _pos++;
      return true;
    }
    if (repeat == QueueRepeat.all || (!auto && repeat == QueueRepeat.one)) {
      if (_order.length == 1) return repeat == QueueRepeat.all;
      if (_shuffle) {
        final last = index;
        _order = _shuffledOrder(first: _randomOther(last), notFirst: last);
      }
      _pos = 0;
      return true;
    }
    return false;
  }

  int _randomOther(int not) {
    if (_items.length == 1) return 0;
    var i = _random.nextInt(_items.length - 1);
    if (i >= not) i++;
    return i;
  }

  /// Oldingi faylga o'tadi. Ro'yxat boshida va takrorlash yoqilmagan bo'lsa false.
  bool previous() {
    if (_pos > 0) {
      _pos--;
      return true;
    }
    if (repeat != QueueRepeat.off && _order.length > 1) {
      _pos = _order.length - 1;
      return true;
    }
    return false;
  }

  /// Ro'yxatdan tanlangan faylga o'tadi
  void jumpTo(int itemIndex) {
    if (itemIndex < 0 || itemIndex >= _items.length) return;
    final p = _order.indexOf(itemIndex);
    if (p >= 0) _pos = p;
  }

  /// Keyingi ijro etiladigan fayl (ko'rsatish uchun); yo'q bo'lsa null
  QueueItem? get upNext {
    if (_pos + 1 < _order.length) return _items[_order[_pos + 1]];
    if (repeat == QueueRepeat.all && _order.length > 1) return _items[_order.first];
    return null;
  }
}
