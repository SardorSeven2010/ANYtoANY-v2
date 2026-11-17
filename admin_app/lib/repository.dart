import 'package:supabase_flutter/supabase_flutter.dart';

/// Admin ilovasining ma'lumot manbai. Sinovlarda soxta (fake) versiyasi ishlatiladi.
abstract class AdminRepository {
  /// Kirgan foydalanuvchi emaili
  String? get currentEmail;

  /// Kirgan foydalanuvchi admin ekanini serverdan tekshiradi
  Future<bool> currentUserIsAdmin();

  /// Hamma foydalanuvchi profillari (eng oxirgi o'zgarganlari birinchi)
  Future<List<Map<String, dynamic>>> fetchProfiles();

  /// Profilni yangilaydi. Server o'zgartirishga ruxsat bermasa false qaytaradi.
  Future<bool> updateProfile(String id, Map<String, dynamic> values);

  Future<void> signOut();
}

class SupabaseAdminRepository implements AdminRepository {
  SupabaseClient get _client => Supabase.instance.client;

  @override
  String? get currentEmail => _client.auth.currentUser?.email;

  @override
  Future<bool> currentUserIsAdmin() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return false;
    final row = await _client.from('user_profiles').select('is_admin').eq('id', uid).maybeSingle();
    return row?['is_admin'] == true;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchProfiles() async {
    final data = await _client
        .from('user_profiles')
        .select()
        .order('updated_at', ascending: false)
        .limit(5000);
    return List<Map<String, dynamic>>.from(data);
  }

  @override
  Future<bool> updateProfile(String id, Map<String, dynamic> values) async {
    final updated = await _client.from('user_profiles').update(values).eq('id', id).select('id');
    return updated.isNotEmpty;
  }

  @override
  Future<void> signOut() => _client.auth.signOut();
}
