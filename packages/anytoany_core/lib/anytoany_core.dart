// ================= SOZLAMALAR (SHU YERNI TO'LDIRING) =================
// Bu fayl ikkala ilova uchun umumiy: ANYtoANY va ANYtoANY Admin.
const String supabaseUrl = "https://fqswjksqlmtsiokwmsdy.supabase.co";
const String supabaseKey = "sb_publishable_gR8RxvY6nhzN4V1ZgMilhw_xkPxvIhS";

const String cardNumber = "4466136952399476"; // O'zingizning Uzcard yoki Humo kartangiz
const String cardOwner = "Sardor Madiyorov"; // Karta egasi ismi
const String supportPhone = "+998887028708"; // Qo'llab-quvvatlash xizmati raqami

// PDF ni Word / PowerPoint / Excel ga aylantiradigan Supabase Edge Function nomi.
// Supabase'dagi funksiya manzilining oxirgi qismi bilan bir xil bo'lishi kerak:
// https://<loyiha>.supabase.co/functions/v1/quick-worker
const String convertFunctionName = "quick-worker";

// Bepul tarifda bir martada tanlash mumkin bo'lgan fayllar soni
const int freeFileLimit = 3;

// PRO obuna tariflari
class ProPlan {
  final String id;
  final String title;
  final int months;
  final int price;
  const ProPlan({required this.id, required this.title, required this.months, required this.price});

  String get priceLabel => formatSom(price);
}

const List<ProPlan> proPlans = [
  ProPlan(id: "month_1", title: "1 oylik", months: 1, price: 12000),
  ProPlan(id: "month_6", title: "6 oylik", months: 6, price: 50000),
  ProPlan(id: "year_1", title: "1 yillik", months: 12, price: 100000),
];
// =====================================================================

ProPlan? planById(String? id) {
  for (final plan in proPlans) {
    if (plan.id == id) return plan;
  }
  return null;
}

/// 12000 -> "12 000 so'm"
String formatSom(int value) {
  final digits = value.toString();
  final buffer = StringBuffer();
  for (int i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(' ');
    buffer.write(digits[i]);
  }
  return "$buffer so'm";
}

/// 2026-12-31 -> "31.12.2026"
String formatDate(DateTime date) {
  final d = date.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return "${two(d.day)}.${two(d.month)}.${d.year}";
}

// ================= PRO OBUNA MUDDATI =================

/// [date] ga [months] oy qo'shadi. Oyning oxirgi kunidan oshib ketmaydi:
/// 31-yanvar + 1 oy = 28 (yoki 29)-fevral.
DateTime addMonths(DateTime date, int months) {
  final d = date.toUtc();
  final int total = d.year * 12 + (d.month - 1) + months;
  final int year = total ~/ 12;
  final int month = total % 12 + 1;
  final int lastDay = DateTime.utc(year, month + 1, 0).day;
  final int day = d.day > lastDay ? lastDay : d.day;
  return DateTime.utc(year, month, day, d.hour, d.minute, d.second);
}

/// Profil qatori bo'yicha PRO hozir faolmi
bool isProActive(Map<String, dynamic> row, {DateTime? now}) {
  if (row['is_pro'] != true) return false;
  final until = DateTime.tryParse((row['pro_until'] ?? "").toString());
  return until == null || until.isAfter(now ?? DateTime.now());
}

/// PRO ni [months] oyga uzaytirgandagi yangi tugash sanasi.
/// Obuna hali faol bo'lsa, muddat uning ustiga qo'shiladi; aks holda bugundan boshlanadi.
DateTime extendProUntil(Map<String, dynamic> row, int months, {DateTime? now}) {
  final current = (now ?? DateTime.now()).toUtc();
  final until = DateTime.tryParse((row['pro_until'] ?? "").toString())?.toUtc();
  final base = (isProActive(row, now: current) && until != null && until.isAfter(current)) ? until : current;
  return addMonths(base, months);
}

/// Admin PRO yoqqanda bazaga yoziladigan qiymatlar
Map<String, dynamic> grantProValues(Map<String, dynamic> row, int months, {DateTime? now}) => {
      'is_pro': true,
      'pro_until': extendProUntil(row, months, now: now).toIso8601String(),
      'payment_requested': false,
    };

/// Admin PRO ni o'chirganda (yoki so'rovni rad etganda) yoziladigan qiymatlar
const Map<String, dynamic> revokeProValues = {
  'is_pro': false,
  'pro_until': null,
  'payment_requested': false,
};
