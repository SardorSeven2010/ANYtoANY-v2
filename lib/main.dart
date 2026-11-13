import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_theme.dart';
import 'config.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';

// Sozlamalar (Supabase, karta raqami, narxlar, telefon) lib/config.dart faylida.

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Supabase.initialize(
      url: supabaseUrl,
      publishableKey: supabaseKey,
    );
  } catch (_) {}

  await themeController.load();

  // Supabase sessiyasi saqlangan bo'lsa, qayta kirish so'ralmaydi
  bool isLoggedIn = false;
  try {
    isLoggedIn = Supabase.instance.client.auth.currentSession != null;
  } catch (_) {}

  runApp(AnyToAnyApp(isLoggedIn: isLoggedIn));
}

class AnyToAnyApp extends StatelessWidget {
  final bool isLoggedIn;
  const AnyToAnyApp({super.key, required this.isLoggedIn});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: themeController,
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'ANYtoANY',
        theme: buildAppTheme(themeController.current),
        home: isLoggedIn ? const HomeScreen() : const AuthScreen(),
      ),
    );
  }
}
