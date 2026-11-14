import 'package:anytoany_core/anytoany_core.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_screen.dart';
import 'home_screen.dart';
import 'repository.dart';

// ANYtoANY Admin: to'lov so'rovlarini tasdiqlash, PRO berish va foydalanuvchilarni kuzatish.
// Sozlamalar (Supabase, tariflar) asosiy ilova bilan umumiy: packages/anytoany_core

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  bool signedIn = false;
  try {
    await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseKey);
    signedIn = Supabase.instance.client.auth.currentSession != null;
  } catch (_) {}
  runApp(AdminApp(repository: SupabaseAdminRepository(), signedIn: signedIn));
}

ThemeData adminTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFFFFD60A), brightness: Brightness.dark);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFF12141C),
    appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF12141C), centerTitle: false),
    cardTheme: CardThemeData(
      color: const Color(0xFF1C1F2A),
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF1C1F2A),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    ),
    navigationBarTheme: const NavigationBarThemeData(backgroundColor: Color(0xFF181B25)),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

class AdminApp extends StatelessWidget {
  final AdminRepository repository;
  final bool signedIn;
  const AdminApp({super.key, required this.repository, required this.signedIn});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ANYtoANY Admin',
      theme: adminTheme(),
      home: signedIn ? AdminGate(repository: repository) : AdminAuthScreen(repository: repository),
    );
  }
}

/// Kirgan akkaunt admin ekanini tekshiradi
class AdminGate extends StatefulWidget {
  final AdminRepository repository;
  const AdminGate({super.key, required this.repository});

  @override
  State<AdminGate> createState() => _AdminGateState();
}

class _AdminGateState extends State<AdminGate> {
  late Future<bool> _check = widget.repository.currentUserIsAdmin();

  Future<void> _signOut() async {
    await widget.repository.signOut();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => AdminAuthScreen(repository: widget.repository)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _check,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.data == true) return AdminHome(repository: widget.repository);
        return Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_rounded, size: 64),
                  const SizedBox(height: 12),
                  Text(
                    snapshot.hasError ? "Server bilan bog'lanib bo'lmadi" : "Bu akkauntda admin huquqi yo'q",
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    snapshot.hasError
                        ? "Internetni tekshirib, qayta urinib ko'ring."
                        : "${widget.repository.currentEmail ?? ''}\n"
                            "Supabase → Table Editor → user_profiles jadvalida is_admin = true qiling.",
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  if (snapshot.hasError)
                    FilledButton(
                      onPressed: () => setState(() => _check = widget.repository.currentUserIsAdmin()),
                      child: const Text("Qayta urinish"),
                    ),
                  TextButton(onPressed: _signOut, child: const Text("Boshqa akkaunt bilan kirish")),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
