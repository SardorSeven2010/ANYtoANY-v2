import 'package:anytoany_admin/home_screen.dart';
import 'package:anytoany_admin/main.dart';
import 'package:anytoany_admin/repository.dart';
import 'package:anytoany_core/anytoany_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeRepository implements AdminRepository {
  FakeRepository(this.rows, {this.admin = true});
  final List<Map<String, dynamic>> rows;
  bool admin;
  final List<(String, Map<String, dynamic>)> updates = [];
  bool signedOut = false;

  @override
  String? get currentEmail => 'boss@example.com';
  @override
  Future<bool> currentUserIsAdmin() async => admin;
  @override
  Future<List<Map<String, dynamic>>> fetchProfiles() async => [for (final r in rows) Map.of(r)];
  @override
  Future<bool> updateProfile(String id, Map<String, dynamic> values) async {
    if (!admin) return false;
    updates.add((id, values));
    rows.firstWhere((r) => r['id'] == id).addAll(values);
    return true;
  }

  @override
  Future<void> signOut() async => signedOut = true;
}

final now = DateTime.now().toUtc();
String iso(Duration d) => now.add(d).toIso8601String();

List<Map<String, dynamic>> sampleRows() => [
      {
        'id': 'u1', 'email': 'ali@example.com', 'android_id': 'dev-ali', 'total_seconds': 3600,
        'is_pro': false, 'pro_until': null, 'payment_requested': true, 'payment_info': '9860 / Ali',
        'payment_plan': 'month_6', 'created_at': iso(const Duration(days: -2)), 'updated_at': iso(const Duration(minutes: -5)),
      },
      {
        'id': 'u2', 'email': 'vali@example.com', 'android_id': 'dev-vali', 'total_seconds': 7200,
        'is_pro': true, 'pro_until': iso(const Duration(days: 3)), 'payment_requested': false,
        'payment_plan': 'month_1', 'created_at': iso(const Duration(days: -40)), 'updated_at': iso(const Duration(hours: -1)),
      },
      {
        'id': 'u3', 'email': 'guli@example.com', 'android_id': 'dev-guli', 'total_seconds': 600,
        'is_pro': false, 'payment_requested': false, 'created_at': iso(const Duration(days: -1)),
        'updated_at': iso(const Duration(hours: -3)),
      },
      {
        'id': 'u4', 'email': 'boss@example.com', 'is_admin': true, 'is_pro': true, 'pro_until': iso(const Duration(days: 300)),
        'payment_plan': 'year_1', 'created_at': iso(const Duration(days: -90)), 'updated_at': iso(const Duration(days: -1)),
      },
    ];

Future<void> pumpHome(WidgetTester tester, FakeRepository repo) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: adminTheme(), home: AdminHome(repository: repo, refreshEvery: null)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('non-admin cannot get in', (tester) async {
    final repo = FakeRepository(sampleRows(), admin: false);
    await tester.pumpWidget(AdminApp(repository: repo, signedIn: true));
    await tester.pumpAndSettle();
    expect(find.text("Bu akkauntda admin huquqi yo'q"), findsOneWidget);
    expect(find.text("So'rovlar"), findsNothing);
  });

  testWidgets('admin gets the dashboard; signed out shows login', (tester) async {
    final repo = FakeRepository(sampleRows());
    await tester.pumpWidget(AdminApp(repository: repo, signedIn: true));
    await tester.pumpAndSettle();
    expect(find.text("So'rovlar"), findsOneWidget);
    await tester.pumpWidget(AdminApp(repository: repo, signedIn: false, key: const ValueKey('out')));
    await tester.pumpAndSettle();
    expect(find.text('Admin panel'), findsOneWidget);
    expect(find.text('Kod olish'), findsOneWidget);
  });

  testWidgets('approving a payment request grants the requested plan, undo restores', (tester) async {
    final rows = sampleRows();
    final repo = FakeRepository(rows);
    await pumpHome(tester, repo);

    expect(find.text('ali@example.com'), findsOneWidget);
    expect(find.text("6 oylik — 50 000 so'm"), findsOneWidget);
    expect(find.text("To'lov ma'lumoti: 9860 / Ali"), findsOneWidget);
    expect(find.text('vali@example.com'), findsNothing, reason: 'only pending requests on this tab');

    await tester.tap(find.text('Tasdiqlash (+6 oylik)'));
    await tester.pumpAndSettle();
    final (id, values) = repo.updates.single;
    expect(id, 'u1');
    expect(values['is_pro'], isTrue);
    expect(values['payment_requested'], isFalse);
    final until = DateTime.parse(values['pro_until']);
    expect(until.difference(addMonths(now, 6)).inMinutes.abs(), lessThan(2));
    expect(find.textContaining('PRO ${formatDate(until)} gacha yoqildi'), findsOneWidget);
    expect(find.text("Yangi to'lov so'rovlari yo'q"), findsOneWidget);

    await tester.tap(find.text('Qaytarish'));
    await tester.pumpAndSettle();
    expect(rows.first['is_pro'], isFalse);
    expect(rows.first['payment_requested'], isTrue);
    expect(find.text('ali@example.com'), findsOneWidget, reason: 'request is back after undo');
  });

  testWidgets('rejecting keeps PRO untouched', (tester) async {
    final repo = FakeRepository(sampleRows());
    await pumpHome(tester, repo);
    await tester.tap(find.text('Rad etish'));
    await tester.pumpAndSettle();
    expect(repo.updates.single.$2, {'payment_requested': false});
  });

  testWidgets('users tab: search, filters and extending an active subscription', (tester) async {
    final rows = sampleRows();
    final repo = FakeRepository(rows);
    await pumpHome(tester, repo);
    await tester.tap(find.text('Foydalanuvchilar'));
    await tester.pumpAndSettle();
    expect(find.text('4 ta foydalanuvchi'), findsOneWidget);

    await tester.tap(find.text('PRO'));
    await tester.pumpAndSettle();
    expect(find.text('2 ta foydalanuvchi'), findsOneWidget);
    await tester.tap(find.text('Bepul'));
    await tester.pumpAndSettle();
    expect(find.text('2 ta foydalanuvchi'), findsOneWidget);
    await tester.tap(find.text("So'rov"));
    await tester.pumpAndSettle();
    expect(find.text('1 ta foydalanuvchi'), findsOneWidget);
    await tester.tap(find.text('Hammasi'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'dev-vali');
    await tester.pumpAndSettle();
    expect(find.text('1 ta foydalanuvchi'), findsOneWidget);
    await tester.tap(find.text('vali@example.com'));
    await tester.pumpAndSettle();
    expect(find.text("PRO ni o'chirish"), findsOneWidget);
    await tester.tap(find.text('+1 oylik'));
    await tester.pumpAndSettle();
    // faol obuna (3 kun qolgan) ustiga 1 oy qo'shiladi
    final until = DateTime.parse(repo.updates.single.$2['pro_until']);
    final expected = addMonths(now.add(const Duration(days: 3)), 1);
    expect(until.difference(expected).inMinutes.abs(), lessThan(2));
  });

  testWidgets('stats tab', (tester) async {
    final repo = FakeRepository(sampleRows());
    await pumpHome(tester, repo);
    await tester.tap(find.text('Statistika'));
    await tester.pumpAndSettle();
    Finder card(String label) => find.ancestor(of: find.text(label), matching: find.byType(Card));
    expect(find.descendant(of: card('Jami foydalanuvchilar'), matching: find.text('4')), findsOneWidget);
    expect(find.descendant(of: card('Faol PRO'), matching: find.text('2')), findsOneWidget);
    expect(find.descendant(of: card("Kutilayotgan so'rovlar"), matching: find.text('1')), findsOneWidget);
    expect(find.descendant(of: card('7 kunda yangi'), matching: find.text('2')), findsOneWidget);
    expect(find.descendant(of: card('7 kunda tugaydi'), matching: find.text('1')), findsOneWidget);
    expect(find.descendant(of: card('Jami foydalanish'), matching: find.text('3 soat')), findsOneWidget);
    await tester.scrollUntilVisible(find.text('vali@example.com'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('vali@example.com'), findsOneWidget, reason: 'listed as expiring soon');
    expect(find.text('boss@example.com'), findsNothing, reason: 'yearly plan is not expiring');
  });

  testWidgets('new payment request while the app is open is announced', (tester) async {
    final rows = sampleRows();
    final repo = FakeRepository(rows);
    await pumpHome(tester, repo);
    rows[2]['payment_requested'] = true;
    rows[2]['payment_plan'] = 'month_1';
    await tester.tap(find.byTooltip('Yangilash'));
    await tester.pumpAndSettle();
    expect(find.text("Yangi to'lov so'rovi: guli@example.com"), findsOneWidget);
  });
}
