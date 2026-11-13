import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:android_id/android_id.dart';
import 'package:file_picker/file_picker.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart' as pdfx;

// ================= SOZLAMALAR (SHU YERNI TO'LDIRING) =================
const String SUPABASE_URL = "https://sdectcjfuiswahjfdwme.supabase.co";
const String SUPABASE_KEY = "sb_publishable_pDWa6T015D6fMYOEn5jAIg_Wog39wND";
const String MY_CARD_NUMBER = "4466136952399476"; // O'zingizning Uzcard yoki Humo kartangiz
const String MY_CARD_OWNER = "Sardor Madiyorov"; // Karta egasi ismi
const String PRO_PRICE = "24 000 so'm"; // PRO tarif narxi
const String ADMIN_SECRET_PIN = "301002012010"; // Ilova ichidan odamlarga PRO yoqish uchun maxfiy parolingiz
// =====================================================================

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Supabase.initialize(
      url: SUPABASE_URL,
      anonKey: SUPABASE_KEY,
    );
  } catch (_) {}

  final prefs = await SharedPreferences.getInstance();
  final bool isLoggedIn = prefs.getBool('is_logged_in') ?? false;

  runApp(AnyToAnyApp(isLoggedIn: isLoggedIn));
}

class AnyToAnyApp extends StatelessWidget {
  final bool isLoggedIn;
  const AnyToAnyApp({super.key, required this.isLoggedIn});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ANYtoANY',
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.tealAccent,
          brightness: Brightness.dark,
        ),
      ),
      home: isLoggedIn ? const HomeScreen() : const AuthScreen(),
    );
  }
}

// ================= 1. RO'YXATDAN O'TISH OYNASI (EMAIL OTP) =================
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

  Future<void> _sendOtp() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Iltimos, to'g'ri elektron pochta kiriting!")),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      await Supabase.instance.client.auth.signInWithOtp(email: email);
      setState(() => _codeSent = true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Pochtangizga tasdiqlash kodi yuborildi!")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Xatolik: $e")),
        );
      }
    }
    setState(() => _loading = false);
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
        await prefs.setBool('is_logged_in', true);
        await prefs.setString('user_id', res.user!.id);
        await prefs.setString('user_email', email);

        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const HomeScreen()),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Kod xato yoki muddati o'tgan!")),
        );
      }
    }
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("ANYtoANY - Kirish"), centerTitle: true),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.transform_rounded, size: 80, color: Colors.tealAccent),
            const SizedBox(height: 12),
            const Text(
              "ANYtoANY",
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 1.5),
            ),
            const Text(
              "Video, Audio, Kodek va PDF Konverter",
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _emailController,
              enabled: !_codeSent,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: "Elektron pochtangiz (Email)",
                prefixIcon: Icon(Icons.email_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            if (_codeSent) ...[
              TextField(
                controller: _otpController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "Pochtaga kelgan kodni kiriting",
                  prefixIcon: Icon(Icons.lock_outline),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
            ],
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(padding: const EdgeInsets.all(16)),
                onPressed: _loading ? null : (_codeSent ? _verifyOtp : _sendOtp),
                child: Text(_loading
                    ? "Tekshirilmoqda..."
                    : (_codeSent ? "Tasdiqlash va Kirish" : "Tasdiqlash kodini olish")),
              ),
            ),
            if (_codeSent)
              TextButton(
                onPressed: () => setState(() => _codeSent = false),
                child: const Text("Elektron pochtani o'zgartirish"),
              ),
          ],
        ),
      ),
    );
  }
}

// ================= 2. ASOSIY OYNA =================
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  String _deviceId = "Aniqlanmoqda...";
  String _userEmail = "";
  int _totalSeconds = 0;
  bool _isPro = false;
  bool _paymentRequested = false;
  Timer? _usageTimer;

  List<PlatformFile> _selectedFiles = [];
  String _targetFormat = "mp3";
  String _videoCodec = "libx264";
  bool _isConverting = false;
  int _completedCount = 0;

  final List<String> _formats = [
    "mp3", "wav", "aac", "m4a", "flac", "ogg",
    "mp4", "mkv", "avi", "mov", "webm", "gif",
    "pdf", "png", "jpg"
  ];

  final List> _codecs = [
    {"name": "H.264 (Barcha telefonlar uchun)", "val": "libx264"},
    {"name": "H.265 / HEVC (Kichik hajm, yuqori sifat)", "val": "libx265"},
    {"name": "VP9 (WebM / YouTube kodeki)", "val": "libvpx-vp9"},
    {"name": "MPEG-4 (Eski qurilmalar uchun)", "val": "mpeg4"},
    {"name": "Kodekni o'zgartirmasdan tez ko'chirish", "val": "copy"},
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initDeviceAndSync();
    _startTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _syncToServer();
    }
  }

  Future<void> _initDeviceAndSync() async {
    const androidIdPlugin = AndroidId();
    final String? id = await androidIdPlugin.getId();
    final prefs = await SharedPreferences.getInstance();

    final String deviceId = id ?? "unknown_device";
    final String email = prefs.getString('user_email') ?? "";
    int localSec = prefs.getInt('total_seconds') ?? 0;
    bool localPro = prefs.getBool('is_pro') ?? false;

    setState(() {
      _deviceId = deviceId;
      _userEmail = email;
      _totalSeconds = localSec;
      _isPro = localPro;
    });

    try {
      final String? userId = prefs.getString('user_id');

      // Ilova o'chirib qayta o'rnatilganda ham ANDROID_ID yoki ID orqali topadi
      final existing = await Supabase.instance.client
          .from('user_profiles')
          .select()
          .or('id.eq.$userId,android_id.eq.$deviceId')
          .limit(1)
          .maybeSingle();

      if (existing != null) {
        final int serverSec = existing['total_seconds'] ?? 0;
        final bool serverPro = existing['is_pro'] ?? false;
        final bool payReq = existing['payment_requested'] ?? false;

        if (serverSec > _totalSeconds) {
          _totalSeconds = serverSec;
          await prefs.setInt('total_seconds', _totalSeconds);
        }
        _isPro = serverPro;
        _paymentRequested = payReq;
        await prefs.setBool('is_pro', _isPro);
        setState(() {});
      } else if (userId != null) {
        await Supabase.instance.client.from('user_profiles').upsert({
          'id': userId,
          'email': email,
          'android_id': _deviceId,
          'total_seconds': _totalSeconds,
          'is_pro': _isPro,
        });
      }
    } catch (_) {}
  }

  void _startTimer() {
    _usageTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      setState(() => _totalSeconds += 10);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('total_seconds', _totalSeconds);

      if (_totalSeconds % 60 == 0) {
        await _syncToServer();
      }
    });
  }

  Future<void> _syncToServer() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id');
      if (userId != null) {
        final res = await Supabase.instance.client
            .from('user_profiles')
            .update({
              'total_seconds': _totalSeconds,
              'android_id': _deviceId,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', userId)
            .select()
            .maybeSingle();

        if (res != null && mounted) {
          final bool serverPro = res['is_pro'] ?? false;
          if (serverPro != _isPro) {
            setState(() => _isPro = serverPro);
            await prefs.setBool('is_pro', serverPro);
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.any,
    );
    if (result != null) {
      if (!_isPro && result.files.length > 3) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Bepul tarifda 3 tagacha fayl! 20+ fayl uchun PRO tarifni yoqing."),
            ),
          );
        }
        setState(() => _selectedFiles = result.files.take(3).toList());
      } else {
        setState(() => _selectedFiles = result.files);
      }
    }
  }

  Future<void> _convertFilesOffline() async {
    if (_selectedFiles.isEmpty) return;
    setState(() {
      _isConverting = true;
      _completedCount = 0;
    });

    Directory? outDir = Directory('/storage/emulated/0/Download');
    if (!await outDir.exists()) {
      outDir = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
    }

    const int batchSize = 4;
    for (int i = 0; i < _selectedFiles.length; i += batchSize) {
      final batch = _selectedFiles.skip(i).take(batchSize);
      await Future.wait(batch.map((file) async {
        if (file.path == null) return;
        final baseName = file.name.replaceAll(RegExp(r'\.[^\.]+$'), '');
        final outPath = "${outDir!.path}/${baseName}_ANYtoANY.$_targetFormat";

        String cmd = "";
        if (["mp4", "mkv", "webm", "mov", "avi"].contains(_targetFormat)) {
          cmd = '-y -i "${file.path}" -c:v $_videoCodec -c:a aac "$outPath"';
        } else {
          cmd = '-y -i "${file.path}" "$outPath"';
        }

        final session = await FFmpegKit.execute(cmd);
        final rc = await session.getReturnCode();
        if (ReturnCode.isSuccess(rc) && mounted) {
          setState(() => _completedCount++);
        }
      }));
    }

    setState(() => _isConverting = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 5),
          content: Text("Tayyor! $_completedCount ta fayl Download papkasiga saqlandi."),
        ),
      );
    }
  }

  // Mijoz kartaga pul o'tkazgach so'rov yuborishi
  Future<void> _sendPaymentNotification(String cardDetails) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id');
      if (userId != null) {
        await Supabase.instance.client.from('user_profiles').update({
          'payment_requested': true,
          'payment_info': cardDetails,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', userId);

        setState(() => _paymentRequested = true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("To'lov ma'lumoti yuborildi! Admin tasdiqlashi bilan PRO avtomatik yonadi."),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Internet xatoligi: $e")),
        );
      }
    }
  }

  void _showPaymentDialog() {
    final payInfoController = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("PRO Tarifga ulanish"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("PRO imkoniyatlari:", style: TextStyle(fontWeight: FontWeight.bold)),
              const Text("• Bir vaqtning o'zida 20+ faylni aylantirish"),
              const Text("• Barcha video kodeklar (H.265, VP9, H.264)"),
              const Text("• PDF va media konvertatsiya cheklovsiz"),
              const Divider(height: 24),
              Text("Narxi: $PRO_PRICE (Umrbod)", style: const TextStyle(color: Colors.amber)),
              const SizedBox(height: 8),
              const Text("To'lov uchun karta raqam:"),
              Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      MY_CARD_NUMBER,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Colors.tealAccent,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 20),
                    onPressed: () {
                      Clipboard.setData(const ClipboardData(text: MY_CARD_NUMBER));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Karta raqam nusxalandi!")),
                      );
                    },
                  ),
                ],
              ),
              Text("Karta egasi: $MY_CARD_OWNER", style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 16),
              TextField(
                controller: payInfoController,
                decoration: const InputDecoration(
                  labelText: "Kartangiz oxirgi 4 raqami yoki ismingiz",
                  hintText: "Masalan: 9860 / Ali",
                  border: OutlineInputBorder(),
                ),
              ),
              if (_paymentRequested)
                const Padding(
                  padding: EdgeInsets.only(top: 8.0),
                  child: Text(
                    "Sizning to'lov so'rovingiz tekshirilmoqda...",
                    style: TextStyle(color: Colors.orangeAccent, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              _initDeviceAndSync();
              Navigator.pop(context);
            },
            child: const Text("PRO holatni yangilash"),
          ),
          FilledButton(
            onPressed: () {
              if (payInfoController.text.trim().isNotEmpty) {
                _sendPaymentNotification(payInfoController.text.trim());
                Navigator.pop(context);
              }
            },
            child: const Text("To'lov qildim"),
          ),
        ],
      ),
    );
  }

  // Siz (Ilova egasi) uchun maxfiy Admin Panelga kirish
  void _openAdminLogin() {
    final pinCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Admin Boshqaruvi"),
        content: TextField(
          controller: pinCtrl,
          obscureText: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: "Admin PIN parolni kiriting",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Bekor qilish")),
          FilledButton(
            onPressed: () {
              if (pinCtrl.text.trim() == ADMIN_SECRET_PIN) {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminPanelScreen()));
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("PIN parol xato!")),
                );
              }
            },
            child: const Text("Kirish"),
          ),
        ],
      ),
    );
  }

  String _formatTime(int sec) {
    final int h = sec ~/ 3600;
    final int m = (sec % 3600) ~/ 60;
    final int s = sec % 60;
    return "${h}s ${m}d ${s}soniya";
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _usageTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onLongPress: _openAdminLogin, // "ANYtoANY" yozuvini bosib tursangiz Admin Panel ochiladi
          child: const Text("ANYtoANY", style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.admin_panel_settings_outlined),
            tooltip: "Admin Panel",
            onPressed: _openAdminLogin,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: ActionChip(
              avatar: Icon(Icons.workspace_premium, color: _isPro ? Colors.amber : Colors.grey),
              label: Text(_isPro ? "PRO FAOL" : "PRO OLISH"),
              onPressed: _showPaymentDialog,
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.phone_android, color: Colors.tealAccent),
                title: SelectableText("Qurilma ID: $_deviceId", style: const TextStyle(fontSize: 12)),
                subtitle: Text("Ishlatilgan vaqt: ${_formatTime(_totalSeconds)}\nEmail: $_userEmail"),
                isThreeLine: true,
                trailing: IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _initDeviceAndSync,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isConverting ? null : _pickFiles,
                    icon: const Icon(Icons.file_present_rounded),
                    label: Text(_isPro ? "Fayllarni tanlash (20+)" : "Fayl tanlash (Max 3)"),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.tealAccent),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _targetFormat,
                      items: _formats
                          .map((f) => DropdownMenuItem(value: f, child: Text(f.toUpperCase())))
                          .toList(),
                      onChanged: _isConverting ? null : (v) => setState(() => _targetFormat = v!),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (["mp4", "mkv", "webm", "mov", "avi"].contains(_targetFormat))
              DropdownButtonFormField<String>(
                value: _videoCodec,
                decoration: const InputDecoration(
                  labelText: "Video Kodekni tanlang",
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                items: _codecs
                    .map((c) => DropdownMenuItem(value: c["val"], child: Text(c["name"]!)))
                    .toList(),
                onChanged: _isConverting ? null : (v) => setState(() => _videoCodec = v!),
              ),
            const SizedBox(height: 10),
            if (_isConverting) ...[
              LinearProgressIndicator(
                value: _selectedFiles.isEmpty ? 0 : _completedCount / _selectedFiles.length,
              ),
              const SizedBox(height: 4),
              Text("Aylantirilmoqda: $_completedCount / ${_selectedFiles.length}"),
            ],
            Expanded(
              child: _selectedFiles.isEmpty
                  ? const Center(
                      child: Text(
                        "Video, Audio yoki PDF fayllarni tanlang.\nPDF faylni ko'zcha tugmasi orqali o'qishingiz mumkin.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _selectedFiles.length,
                      itemBuilder: (ctx, i) {
                        final f = _selectedFiles[i];
                        final bool isPdf = f.name.toLowerCase().endsWith('.pdf');
                        return ListTile(
                          leading: Icon(
                            isPdf ? Icons.picture_as_pdf : Icons.perm_media,
                            color: isPdf ? Colors.redAccent : Colors.tealAccent,
                          ),
                          title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text("${(f.size / 1024 / 1024).toStringAsFixed(2)} MB -> .$_targetFormat"),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isPdf && f.path != null)
                                IconButton(
                                  icon: const Icon(Icons.visibility, color: Colors.lightBlueAccent),
                                  tooltip: "PDF ni ochish",
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => PdfViewerScreen(
                                          pdfPath: f.path!,
                                          fileName: f.name,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: _isConverting
                                    ? null
                                    : () => setState(() => _selectedFiles.removeAt(i)),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(padding: const EdgeInsets.all(16)),
                onPressed: (_selectedFiles.isEmpty || _isConverting) ? null : _convertFilesOffline,
                icon: const Icon(Icons.bolt),
                label: Text(
                  _isConverting
                      ? "Jarayon ketmoqda..."
                      : "Barchasini .${_targetFormat.toUpperCase()} ga aylantirish (${_selectedFiles.length} ta)",
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ================= 3. ADMIN PANEL (PUL TASHLAGANLARGA PRO YOQISH) =================
class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  List<dynamic> _users = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() => _loading = true);
    try {
      final data = await Supabase.instance.client
          .from('user_profiles')
          .select()
          .order('payment_requested', ascending: false)
          .order('updated_at', ascending: false);
      setState(() => _users = data);
    } catch (_) {}
    setState(() => _loading = false);
  }

  Future<void> _toggleUserPro(String id, bool currentPro) async {
    await Supabase.instance.client.from('user_profiles').update({
      'is_pro': !currentPro,
      'payment_requested': false,
    }).eq('id', id);
    await _loadUsers();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Admin: Foydalanuvchilar & To'lovlar"),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadUsers),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _users.length,
              itemBuilder: (ctx, i) {
                final u = _users[i];
                final bool isPro = u['is_pro'] ?? false;
                final bool payReq = u['payment_requested'] ?? false;
                final int mins = (u['total_seconds'] ?? 0) ~/ 60;
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: ListTile(
                    title: Text(u['email'] ?? "Noma'lum Email"),
                    subtitle: Text(
                      "ID: ${u['android_id']}\nIshlatgan: $mins daqiqa\nTo'lov xabari: ${u['payment_info'] ?? '-'}",
                    ),
                    isThreeLine: true,
                    trailing: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isPro
                            ? Colors.green
                            : (payReq ? Colors.orange : Colors.blueGrey),
                      ),
                      onPressed: () => _toggleUserPro(u['id'], isPro),
                      child: Text(isPro ? "PRO O'chirish" : "PRO Yoqish"),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

// ================= 4. PDF O'QUVCHI OYNA =================
class PdfViewerScreen extends StatefulWidget {
  final String pdfPath;
  final String fileName;
  const PdfViewerScreen({super.key, required this.pdfPath, required this.fileName});

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  late pdfx.PdfController _pdfController;

  @override
  void initState() {
    super.initState();
    _pdfController = pdfx.PdfController(
      document: pdfx.PdfDocument.openFile(widget.pdfPath),
    );
  }

  @override
  void dispose() {
    _pdfController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.fileName)),
      body: pdfx.PdfView(controller: _pdfController),
    );
  }
}
