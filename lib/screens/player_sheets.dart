import 'package:flutter/material.dart';

import '../player/aspect.dart';
import '../player/controller.dart';
import '../player/engine.dart';
import '../player/play_queue.dart';

/// Pleyerning quyi oynalari: tezlik, dekoder, video o'lchami, navbat.

Future<void> showPlayerSheet(
  BuildContext context,
  Widget Function(BuildContext) builder,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    // video ustida ochiladi: Liquid Glass uslubida ham o'qilishi uchun to'liq zich fon
    backgroundColor: Theme.of(context).colorScheme.surface,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: builder,
  );
}

String speedLabel(double v) {
  final s = v
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
  return "${s}x";
}

// ================= TEZLIK =================
class SpeedSheet extends StatelessWidget {
  final PlayerController controller;
  const SpeedSheet({super.key, required this.controller});

  static const List<double> presets = [
    0.25,
    0.5,
    0.75,
    1.0,
    1.25,
    1.5,
    2.0,
    3.0,
    4.0,
  ];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final speed = controller.speed;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Video tezligi: ${speedLabel(speed)}",
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  IconButton(
                    tooltip: "Sekinlashtirish",
                    onPressed: () => controller.setSpeed(speed - 0.05),
                    icon: const Icon(Icons.remove_circle_outline_rounded),
                  ),
                  Expanded(
                    child: Slider(
                      key: const Key("speedSlider"),
                      min: minSpeed,
                      max: maxSpeed,
                      divisions: 75,
                      value: speed.clamp(minSpeed, maxSpeed),
                      label: speedLabel(speed),
                      onChanged: controller.setSpeed,
                    ),
                  ),
                  IconButton(
                    tooltip: "Tezlashtirish",
                    onPressed: () => controller.setSpeed(speed + 0.05),
                    icon: const Icon(Icons.add_circle_outline_rounded),
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final p in presets)
                    ChoiceChip(
                      key: Key("speed_$p"),
                      label: Text(speedLabel(p)),
                      selected: (speed - p).abs() < 0.001,
                      onSelected: (_) => controller.setSpeed(p),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              const Text("0.25x dan 4x gacha", style: TextStyle(fontSize: 12)),
            ],
          ),
        );
      },
    );
  }
}

// ================= DEKODER =================
class DecoderSheet extends StatelessWidget {
  final PlayerController controller;
  const DecoderSheet({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 0, 12, 4),
              child: Text(
                "Video dekoderi",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ),
            for (final mode in DecoderMode.values)
              ListTile(
                key: Key("decoder_${mode.name}"),
                leading: Icon(
                  controller.decoder == mode
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                ),
                title: Text(mode.label),
                subtitle: Text(mode.hint),
                onTap: () {
                  controller.setDecoder(mode);
                  Navigator.of(context).maybePop();
                },
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: FutureBuilder<String?>(
                future: controller.engine.activeDecoder(),
                builder: (context, snap) {
                  final v = snap.data;
                  final text = (v == null || v.isEmpty)
                      ? "aniqlanmadi"
                      : (v == "no" ? "dasturiy (protsessor)" : v);
                  return Text(
                    "Hozir ishlatilayotgani: $text\nDekoder almashganda video shu joydan qayta boshlanadi.",
                    style: const TextStyle(fontSize: 12),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ================= VIDEO O'LCHAMI =================
class AspectSheet extends StatelessWidget {
  final PlayerController controller;
  const AspectSheet({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Video o'lchami",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final a in AspectMode.values)
                  ChoiceChip(
                    key: Key("aspect_${a.name}"),
                    label: Text(a.label),
                    selected: controller.aspect == a,
                    onSelected: (_) => controller.setAspect(a),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              "16:9, 19.5:9 va boshqa o'lchamlarda video shu nisbatga moslab cho'ziladi.",
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

// ================= NAVBAT =================
class QueueSheet extends StatelessWidget {
  final PlayerController controller;
  const QueueSheet({super.key, required this.controller});

  Widget _header(PlayQueue q) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Navbat (${q.length} ta)",
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          SegmentedButton<QueueRepeat>(
            key: const Key("repeatSegments"),
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: QueueRepeat.off,
                icon: Icon(Icons.stop_circle_outlined),
                label: Text("To'xtash"),
              ),
              ButtonSegment(
                value: QueueRepeat.all,
                icon: Icon(Icons.repeat_rounded),
                label: Text("Ro'yxat"),
              ),
              ButtonSegment(
                value: QueueRepeat.one,
                icon: Icon(Icons.repeat_one_rounded),
                label: Text("Bitta"),
              ),
            ],
            selected: {q.repeat},
            onSelectionChanged: (s) {
              while (q.repeat != s.first) {
                controller.cycleRepeat();
              }
            },
          ),
          const SizedBox(height: 4),
          Text(repeatLabel(q.repeat), style: const TextStyle(fontSize: 12)),
          SwitchListTile(
            key: const Key("shuffleSwitch"),
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.shuffle_rounded),
            title: const Text("Aralashtirish"),
            value: q.shuffle,
            onChanged: (_) => controller.toggleShuffle(),
          ),
          const Divider(height: 1),
        ],
      ),
    );
  }

  static String repeatLabel(QueueRepeat m) => switch (m) {
    QueueRepeat.off => "Oxirigacha, so'ng to'xtash",
    QueueRepeat.all => "Ro'yxatni takrorlash",
    QueueRepeat.one => "Bittasini takrorlash",
  };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final q = controller.queue;
        final height = MediaQuery.sizeOf(context).height * 0.85;
        return SizedBox(
          height: height > 560 ? 560 : height,
          // Sarlavha ham ro'yxat bilan birga suriladi: past (gorizontal) ekranda ham fayllar ko'rinadi
          child: ListView.builder(
            itemCount: q.length + 1,
            itemBuilder: (context, i) {
              if (i == 0) return _header(q);
              final index = i - 1;
              final item = q.items[index];
              final current = index == q.index;
              return ListTile(
                key: Key("queue_$index"),
                leading: Icon(
                  current
                      ? (controller.playing
                            ? Icons.graphic_eq_rounded
                            : Icons.pause_circle_outline_rounded)
                      : Icons.play_arrow_outlined,
                  color: current ? Theme.of(context).colorScheme.primary : null,
                ),
                title: Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: current ? FontWeight.w800 : FontWeight.normal,
                  ),
                ),
                onTap: () {
                  controller.jumpTo(index);
                  Navigator.of(context).maybePop();
                },
              );
            },
          ),
        );
      },
    );
  }
}
