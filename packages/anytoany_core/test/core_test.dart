import 'package:anytoany_core/anytoany_core.dart';
import 'package:test/test.dart';

void main() {
  test('prices', () {
    expect(proPlans.map((p) => p.priceLabel), ["12 000 so'm", "50 000 so'm", "100 000 so'm"]);
    expect(planById('year_1')!.months, 12);
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
}
