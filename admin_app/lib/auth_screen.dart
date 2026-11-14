import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'main.dart';
import 'repository.dart';

// ================= ADMIN KIRISH (EMAIL KOD) =================
class AdminAuthScreen extends StatefulWidget {
  final AdminRepository repository;
  const AdminAuthScreen({super.key, required this.repository});

  @override
  State<AdminAuthScreen> createState() => _AdminAuthScreenState();
}

class _AdminAuthScreenState extends State<AdminAuthScreen> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  bool _codeSent = false;
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  void _show(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _send() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      _show("To'g'ri email kiriting");
      return;
    }
    setState(() => _loading = true);
    try {
      // shouldCreateUser: false - admin ilovasi orqali yangi akkaunt ochilmaydi
      await Supabase.instance.client.auth.signInWithOtp(email: email, shouldCreateUser: false);
      if (mounted) setState(() => _codeSent = true);
      _show("Pochtangizga kod yuborildi");
    } on AuthException catch (e) {
      _show(e.message.toLowerCase().contains("signups not allowed")
          ? "Bu email bilan akkaunt yo'q. Avval CORE ilovasida ro'yxatdan o'ting."
          : "Xatolik: ${e.message}");
    } catch (_) {
      _show("Internet bilan bog'lanib bo'lmadi");
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _verify() async {
    final code = _code.text.trim();
    if (code.isEmpty) return;
    setState(() => _loading = true);
    try {
      final res = await Supabase.instance.client.auth.verifyOTP(
        email: _email.text.trim(),
        token: code,
        type: OtpType.email,
      );
      if (res.user != null && mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => AdminGate(repository: widget.repository)),
        );
        return;
      }
    } catch (_) {
      _show("Kod xato yoki muddati o'tgan");
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: adminTheme(),
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
                        child: Image.asset("assets/logo.png", height: 100, errorBuilder: (_, _, _) => const SizedBox()),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      "Admin panel",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      "Faqat admin huquqi berilgan akkaunt kira oladi",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _email,
                      enabled: !_codeSent,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      decoration: const InputDecoration(labelText: "Email", prefixIcon: Icon(Icons.email_outlined)),
                    ),
                    if (_codeSent) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _code,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: "Pochtaga kelgan kod",
                          prefixIcon: Icon(Icons.lock_outline),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    FilledButton(
                      style: FilledButton.styleFrom(padding: const EdgeInsets.all(16)),
                      onPressed: _loading ? null : (_codeSent ? _verify : _send),
                      child: Text(_loading ? "Kuting..." : (_codeSent ? "Kirish" : "Kod olish")),
                    ),
                    if (_codeSent)
                      TextButton(
                        onPressed: _loading ? null : () => setState(() => _codeSent = false),
                        child: const Text("Emailni o'zgartirish"),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
