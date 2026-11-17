import 'package:anytoany_core/anytoany_core.dart';
import 'package:test/test.dart';

void main() {
  test('prices', () {
    expect(proPlans.map((p) => p.title), ['1 oylik', '3 oylik', '6 oylik', '9 oylik', '1 yillik']);
    expect(proPlans.map((p) => p.priceLabel),
        ["12 000 so'm", "32 000 so'm", "50 000 so'm", "72 000 so'm", "100 000 so'm"]);
    expect(proPlans.map((p) => p.months), [1, 3, 6, 9, 12]);
    expect(planById('month_3')!.price, 32000);
    expect(planById('month_9')!.price, 72000);
    expect(planById('year_1')!.months, 12);
    // uzoq tarif har doim oyma-oy to'lashdan arzon bo'lishi kerak
    for (final p in proPlans.skip(1)) {
      expect(p.price, lessThan(proPlans.first.price * p.months), reason: p.title);
    }
    expect(appName, 'CORE');
  });

  test('addMonths keeps the day inside the month', () {
    expect(addMonths(DateTime.utc(2026, 1, 31), 1), DateTime.utc(2026, 2, 28));
    expect(addMonths(DateTime.utc(2028, 1, 31), 1), DateTime.utc(2028, 2, 29));
    expect(addMonths(DateTime.utc(2026, 11, 14, 9, 30), 6), DateTime.utc(2027, 5, 14, 9, 30));
    expect(addMonths(DateTime.utc(2026, 12, 5), 12), DateTime.utc(2027, 12, 5));
  });

  test('extending a subscription', () {
    final now = DateTime.utc(2026, 11, 14);
    // obunasi yo'q -> bugundan
    expect(extendProUntil({'is_pro': false}, 1, now: now), DateTime.utc(2026, 12, 14));
    // faol obuna -> tugash sanasining ustiga qo'shiladi
    final active = {'is_pro': true, 'pro_until': '2026-12-01T00:00:00Z'};
    expect(isProActive(active, now: now), isTrue);
    expect(extendProUntil(active, 6, now: now), DateTime.utc(2027, 6, 1));
    // muddati o'tgan -> bugundan
    final expired = {'is_pro': true, 'pro_until': '2026-10-01T00:00:00Z'};
    expect(isProActive(expired, now: now), isFalse);
    expect(extendProUntil(expired, 1, now: now), DateTime.utc(2026, 12, 14));
    // muddatsiz PRO faol hisoblanadi
    expect(isProActive({'is_pro': true}, now: now), isTrue);

    final values = grantProValues(active, 1, now: now);
    expect(values['is_pro'], isTrue);
    expect(values['payment_requested'], isFalse);
    expect(values['pro_until'], '2027-01-01T00:00:00.000Z');
    expect(revokeProValues, {'is_pro': false, 'pro_until': null, 'payment_requested': false});
  });

  test('trial', () {
    final now = DateTime.utc(2026, 11, 14);
    final fresh = {'is_pro': true, 'pro_until': '2026-12-10T00:00:00Z', 'trial_started_at': '2026-11-10T00:00:00Z'};
    expect(trialEndsAt(fresh), DateTime.utc(2026, 12, 10));
    expect(isTrialActive(fresh, now: now), isTrue);
    expect(daysLeft(DateTime.utc(2026, 12, 10), now: now), 26);
    // sinov tugagan
    expect(isTrialActive(fresh, now: DateTime.utc(2026, 12, 11)), isFalse);
    // sinov bo'lmagan akkaunt
    expect(isTrialActive({'is_pro': true, 'pro_until': '2027-01-01T00:00:00Z'}, now: now), isFalse);
    expect(trialEndsAt({'is_pro': false}), isNull);
    // sinov davrida PRO o'chirilgan bo'lsa, faol emas
    expect(isTrialActive({...fresh, 'is_pro': false}, now: now), isFalse);
    expect(daysLeft(DateTime.utc(2026, 11, 13), now: now), 0);
    expect(daysLeft(DateTime.utc(2026, 11, 14, 5), now: now), 1);
  });

  test('download limits', () {
    const free = DownloadLimits(pro: false);
    const pro = DownloadLimits(pro: true);
    expect([free.maxSegments, pro.maxSegments], [6, 18]);
    expect([free.defaultSegments, pro.defaultSegments], [6, 12]);
    expect(free.clampSegments(18), 6);
    expect(pro.clampSegments(18), 18);
    expect(pro.clampSegments(30), 18);
    expect(free.clampSegments(0), 1);

    final now = DateTime.utc(2026, 11, 14, 12);
    final starts = [for (int i = 0; i < 10; i++) now.subtract(Duration(days: i % 6, hours: i))];
    expect(DownloadLimits.usedInWeek(starts, now: now), 10);
    expect(free.remaining(starts, now: now), 0);
    expect(free.canStart(starts, now: now), isFalse);
    expect(pro.canStart(starts, now: now), isTrue, reason: 'PRO has no weekly cap');
    expect(pro.remaining(starts, now: now), isNull);
    // 7 kundan eski yuklashlar hisobga olinmaydi
    final old = [...starts.take(5), for (int i = 0; i < 5; i++) now.subtract(Duration(days: 8 + i))];
    expect(free.remaining(old, now: now), 5);
    expect(free.canStart(old, now: now), isTrue);
    // limit qachon bo'shashi
    final slot = free.nextSlotAt(starts, now: now);
    expect(slot, starts.reduce((a, b) => a.isBefore(b) ? a : b).add(const Duration(days: 7)));
    expect(free.nextSlotAt(old, now: now), isNull);
  });
}
