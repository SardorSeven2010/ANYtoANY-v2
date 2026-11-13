// ================= SOZLAMALAR (SHU YERNI TO'LDIRING) =================
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
