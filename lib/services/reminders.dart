import '../config.dart';
import 'native_bridge.dart';
import 'profile_service.dart';

/// Obuna eslatmalari uchun bildirishnoma raqamlari
const int reminderBefore3Days = 9001;
const int reminderBefore1Day = 9002;
const int reminderExpired = 9003;

/// PRO yoki bepul sinov tugashidan 3 kun va 1 kun oldin hamda tugagan paytda eslatma qo'yadi.
/// Eski eslatmalar bekor qilinadi (obuna uzaytirilgan bo'lishi mumkin). Qo'yilgan vaqtlarni qaytaradi.
Future<List<DateTime>> syncReminders(ProfileService p, NativeBridge bridge, {DateTime? now}) async {
  final current = now ?? DateTime.now();
  for (final id in [reminderBefore3Days, reminderBefore1Day, reminderExpired]) {
    await bridge.cancelReminder(id);
  }
  final until = p.proUntil;
  if (!bridge.supported || !p.isPro || until == null || !until.isAfter(current)) return const [];

  final what = p.trialActive ? "Bepul sinov" : "PRO obuna";
  final plan = formatSom(proPlans.first.price);
  final items = <(int, DateTime, String, String)>[
    (reminderBefore3Days, until.subtract(const Duration(days: 3)), "$what 3 kundan keyin tugaydi",
        "Uzilishsiz foydalanish uchun obunani uzaytiring: oyiga $plan."),
    (reminderBefore1Day, until.subtract(const Duration(days: 1)), "$what ertaga tugaydi",
        "Obunani hozir uzaytirib qo'ying."),
    (reminderExpired, until, "$what tugadi",
        "PRO imkoniyatlari o'chdi. Tarifni tanlash uchun $appName ilovasini oching."),
  ];
  final scheduled = <DateTime>[];
  for (final (id, at, title, body) in items) {
    if (at.isAfter(current)) {
      await bridge.scheduleReminder(id: id, at: at, title: title, body: body);
      scheduled.add(at);
    }
  }
  return scheduled;
}
