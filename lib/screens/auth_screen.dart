import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import 'style_screen.dart';

// ================= KIRISH VA RO'YXATDAN O'TISH OYNASI (EMAIL OTP) =================
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  bool _codeSent = false;
  bool _loading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  void _show(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String _errorText(Object error) {
    if (error is AuthException) {
      final String code = "${error.code} ${error.statusCode} ${error.message}".toLowerCase();
      if (code.contains("rate_limit") || code.contains("429")) {
        return "Juda ko'p urinish bo'ldi. Birozdan keyin qayta urinib ko'ring.";
      }
      if (code.contains("error sending")) {
        return "Tasdiqlash xatini yuborib bo'lmadi. Keyinroq urinib ko'ring.";
      }
      return "Xatolik: ${error.message}";
    }
    return "Internet bilan bog'lanib bo'lmadi. Qayta urinib ko'ring.";
  }

  Future<void> _sendOtp() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      _show("Iltimos, to'g'ri elektron pochta kiriting!");
      return;
    }

    setState(() => _loading = true);
    try {
      await Supabase.instance.client.auth.signInWithOtp(email: email);
      if (mounted) setState(() => _codeSent = true);
      _show("Pochtangizga tasdiqlash kodi yuborildi!");
    } catch (e) {
      _show(_errorText(e));
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _verifyOtp() async {
    final email = _emailController.text.trim();
    final code = _otpController.text.trim();
    if (code.isEmpty) return;

    setState(() => _loading = true);
    try {
      final res = await Supabase.instance.client.auth.verifyOTP(
        email: email,
        token: code,
        type: OtpType.email,
      );

      if (res.user != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_email', email);

        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => postLoginScreen()),
          );
        }
        return;
      }
      _show("Kirish amalga oshmadi, qayta urinib ko'ring!");
    } catch (e) {
      _show(e is AuthException ? "Kod xato yoki muddati o'tgan!" : _errorText(e));
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    // Kirish oynasi tanlangan mavzudan qat'i nazar o'z rasmi va ranglarida chiqadi
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFFFF8F5E), brightness: Brightness.dark);
    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: scheme,
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.black.withValues(alpha: 0.28),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFF0B1033),
        body: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              "assets/auth.jpg",
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x33000000), Color(0x22000000), Color(0x99000000)],
                ),
              ),
            ),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _logo(),
                        const SizedBox(height: 14),
                        Text(
                          "Video, Audio, Kodek va PDF Konverter",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.85)),
                        ),
                        const SizedBox(height: 28),
                        _form(scheme),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _logo() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 28, offset: const Offset(0, 10)),
        ],
      ),
      child: Image.asset(
        "assets/logo.png",
        height: 120,
        semanticLabel: appName,
        errorBuilder: (_, _, _) => const Text(
          appName,
          style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: Colors.black),
        ),
      ),
    );
  }

  Widget _form(ColorScheme scheme) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.36),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Kirish yoki ro'yxatdan o'tish",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
              ),
              const SizedBox(height: 4),
              Text(
                "Emailingizni kiriting, biz tasdiqlash kodini yuboramiz",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.75)),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _emailController,
                enabled: !_codeSent,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: "Elektron pochtangiz (Email)",
                  prefixIcon: Icon(Icons.email_outlined),
                ),
              ),
              if (_codeSent) ...[
                const SizedBox(height: 14),
                TextField(
                  controller: _otpController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: "Pochtaga kelgan kodni kiriting",
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _loading ? null : (_codeSent ? _verifyOtp : _sendOtp),
                child: Text(
                  _loading ? "Tekshirilmoqda..." : (_codeSent ? "Tasdiqlash va Kirish" : "Tasdiqlash kodini olish"),
                ),
              ),
              if (_codeSent)
                TextButton(
                  onPressed: _loading ? null : () => setState(() => _codeSent = false),
                  child: const Text("Elektron pochtani o'zgartirish"),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
