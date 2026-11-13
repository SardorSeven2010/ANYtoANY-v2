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
import 'package:pdf/pdf.dart' as pdf;
import 'package:pdf/widgets.dart' as pw;
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
      publishableKey: SUPABASE_KEY,
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

  @override
  void dispose() {
    _emailController.dispose();
    _otpController.dispose();
    super.dispose();
  }

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
      if (mounted) {
        setState(() => _codeSent = true);
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
        await prefs.setBool('is_logged_in', true);
        await prefs.setString('user_id', res.user!.id);
        await prefs.setString('user_email', email);

        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const HomeScreen()),
          );
        }
        return;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Kirish amalga oshmadi, qayta urinib ko'ring!")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Kod xato yoki muddati o'tgan!")),
        );
      }
    }
    if (mounted) setState(() => _loading = false);
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
  int _failedCount = 0;
  int _timerTicks = 0;

  static const String _publicDownloadDir = '/storage/emulated/0/Download';

  static const List<String> _audioFormats = ["mp3", "wav", "aac", "m4a", "flac", "ogg"];
  static const List<String> _videoFormats = ["mp4", "mkv", "avi", "mov", "webm"];
  static const List<String> _imageFormats = ["png", "jpg"];
  // PDF ga aylantirish mumkin bo'lgan rasm turlari
  static const List<String> _imageInputs = ["png", "jpg", "jpeg", "webp", "bmp", "gif", "tif", "tiff"];

  final List<String> _formats = [
    ..._audioFormats,
    ..._videoFormats, "gif",
    "pdf", ..._imageFormats,
  ];

  final List<Map<String, String>> _codecs = [
    {"name": "H.264 (Barcha telefonlar uchun)", "val": "libx264"},
    {"name": "H.265 / HEVC (Kichik hajm, yuqori sifat)", "val": "libx265"},
    {"name": "VP9 (WebM / YouTube kodeki)", "val": "libvpx-vp9"},
    {"name": "MPEG-4 (Eski qurilmalar uchun)", "val": "mpeg4"},
    {"name": "Kodekni o'zgartirmasdan tez ko'chirish", "val": "copy"},
  ];

  // Har bir konteyner hamma kodekni ham qabul qilmaydi (masalan WebM faqat VP9)
  List<Map<String, String>> _codecsFor(String format) {
    const Map<String, List<String>> allowed = {
      "webm": ["libvpx-vp9", "copy"],
      "mov": ["libx264", "libx265", "mpeg4", "copy"],
      "avi": ["libx264", "mpeg4", "copy"],
    };
    final list = allowed[format];
    if (list == null) return _codecs;
    return _codecs.where((c) => list.contains(c["val"])).toList();
  }

  void _onFormatChanged(String format) {
    setState(() {
      _targetFormat = format;
      final available = _codecsFor(format).map((c) => c["val"]!).toList();
      if (!available.contains(_videoCodec)) _videoCodec = available.first;
    });
  }

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
    String? androidId;
    try {
      androidId = await const AndroidId().getId();
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();

    final String deviceId = androidId ?? "unknown_device";
    final String email = prefs.getString('user_email') ?? "";
    final String? userId = prefs.getString('user_id');
    int localSec = prefs.getInt('total_seconds') ?? 0;
    bool localPro = prefs.getBool('is_pro') ?? false;

    if (!mounted) return;
    setState(() {
      _deviceId = deviceId;
      _userEmail = email;
      _totalSeconds = localSec;
      _isPro = localPro;
    });

    try {
      // Avval shu akkauntning o'z profili qidiriladi
      Map<String, dynamic>? ownProfile;
      if (userId != null) {
        ownProfile = await Supabase.instance.client
            .from('user_profiles')
            .select()
            .eq('id', userId)
            .maybeSingle();
      }

      // Ilova o'chirib qayta o'rnatilganda ham ANDROID_ID orqali topadi
      Map<String, dynamic>? profile = ownProfile;
      if (profile == null && androidId != null) {
        profile = await Supabase.instance.client
            .from('user_profiles')
            .select()
            .eq('android_id', androidId)
            .order('is_pro', ascending: false)
            .limit(1)
            .maybeSingle();
      }

      if (profile != null) {
        final int serverSec = (profile['total_seconds'] as num?)?.toInt() ?? 0;
        final bool serverPro = profile['is_pro'] == true;
        final bool payReq = profile['payment_requested'] == true;

        if (serverSec > _totalSeconds) {
          await prefs.setInt('total_seconds', serverSec);
        }
        await prefs.setBool('is_pro', serverPro);
        if (mounted) {
          setState(() {
            if (serverSec > _totalSeconds) _totalSeconds = serverSec;
            _isPro = serverPro;
            _paymentRequested = payReq;
          });
        }
      }

      // Shu akkaunt uchun qator bo'lmasa yaratiladi (aks holda sinxronlash va
      // to'lov so'rovi hech qayerga yozilmay qoladi)
      if (ownProfile == null && userId != null) {
        await Supabase.instance.client.from('user_profiles').upsert({
          'id': userId,
          'email': email,
          'android_id': deviceId,
          'total_seconds': _totalSeconds,
          'is_pro': _isPro,
        });
      }
    } catch (_) {}
  }

  void _startTimer() {
    _usageTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      if (!mounted) return;
      setState(() => _totalSeconds += 10);
      _timerTicks++;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('total_seconds', _totalSeconds);

      // Har 1 daqiqada serverga sinxronlanadi
      if (_timerTicks % 6 == 0) {
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
          final bool serverPro = res['is_pro'] == true;
          if (serverPro != _isPro) {
            setState(() => _isPro = serverPro);
            await prefs.setBool('is_pro', serverPro);
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _pickFiles() async {
    List<PlatformFile> files;
    try {
      files = await FilePicker.pickFiles(type: FileType.any);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Fayllarni tanlab bo'lmadi: $e")),
        );
      }
      return;
    }
    if (files.isEmpty || !mounted) return;

    if (!_isPro && files.length > 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Bepul tarifda 3 tagacha fayl! 20+ fayl uchun PRO tarifni yoqing."),
        ),
      );
      setState(() => _selectedFiles = files.take(3).toList());
    } else {
      setState(() => _selectedFiles = files.toList());
    }
  }

  // Download papkasiga yozib bo'lmasa (Android 10 va undan eski), ilovaning o'z papkasi ishlatiladi
  Future<Directory> _resolveOutputDir() async {
    final download = Directory(_publicDownloadDir);
    try {
      if (await download.exists()) {
        final probe = File("${download.path}/anytoany_${DateTime.now().microsecondsSinceEpoch}.tmp");
        await probe.writeAsString("ok", flush: true);
        await probe.delete();
        return download;
      }
    } catch (_) {}
    return await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
  }

  // Mavjud faylni ustidan yozmaslik uchun takrorlanmas nom tanlaydi
  String _uniquePath(Directory dir, String baseName, String ext, Set<String> usedPaths) {
    String path = "${dir.path}/$baseName.$ext";
    for (int n = 1; usedPaths.contains(path) || File(path).existsSync(); n++) {
      path = "${dir.path}/${baseName}_$n.$ext";
    }
    usedPaths.add(path);
    return path;
  }

  List<String> _ffmpegArgs(String inPath, String outPath) {
    final args = <String>["-y", "-i", inPath];
    if (_videoFormats.contains(_targetFormat)) {
      args.addAll(["-c:v", _videoCodec]);
      if (_videoCodec != "copy") {
        // Ko'p pleyerlar faqat yuv420p va juft o'lchamli videoni o'qiy oladi
        args.addAll(["-pix_fmt", "yuv420p", "-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2"]);
      }
      final String audioCodec = switch (_targetFormat) {
        "webm" => "libvorbis",
        "avi" => "libmp3lame",
        _ => "aac",
      };
      args.addAll(["-c:a", audioCodec]);
    } else if (_audioFormats.contains(_targetFormat)) {
      args.add("-vn");
    } else if (_imageFormats.contains(_targetFormat)) {
      args.addAll(["-an", "-frames:v", "1", "-update", "1"]);
    }
    args.add(outPath);
    return args;
  }

  Future<bool> _runFfmpeg(List<String> args) async {
    final session = await FFmpegKit.executeWithArguments(args);
    return ReturnCode.isSuccess(await session.getReturnCode());
  }

  Future<void> _deleteQuietly(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  // PDF ning har bir sahifasini alohida rasm qilib saqlaydi
  Future<void> _pdfToImages(String pdfPath, Directory outDir, String baseName, Set<String> usedPaths) async {
    final document = await pdfx.PdfDocument.openFile(pdfPath);
    try {
      for (int n = 1; n <= document.pagesCount; n++) {
        final page = await document.getPage(n);
        try {
          final image = await page.render(
            width: page.width * 2,
            height: page.height * 2,
            format: _targetFormat == "png" ? pdfx.PdfPageImageFormat.png : pdfx.PdfPageImageFormat.jpeg,
            backgroundColor: '#FFFFFF',
          );
          if (image == null) throw Exception("$n-sahifani chizib bo'lmadi");
          final pageName = document.pagesCount > 1 ? "${baseName}_$n-bet" : baseName;
          await File(_uniquePath(outDir, pageName, _targetFormat, usedPaths)).writeAsBytes(image.bytes, flush: true);
        } finally {
          await page.close();
        }
      }
    } finally {
      await document.close();
    }
  }

  // Rasmni bir sahifali PDF ga joylaydi. Xato bo'lsa sababini qaytaradi
  Future<String?> _imageToPdf(String imagePath, String ext, String outPath) async {
    String jpgPath = imagePath;
    String? tempPath;
    if (ext != "jpg" && ext != "jpeg") {
      // JPEG PDF ichiga qayta siqilmasdan joylanadi, boshqa rasmlar avval JPEG ga o'tkaziladi
      final tempDir = await getTemporaryDirectory();
      tempPath = "${tempDir.path}/anytoany_${DateTime.now().microsecondsSinceEpoch}.jpg";
      final ok = await _runFfmpeg(
        ["-y", "-i", imagePath, "-frames:v", "1", "-update", "1", "-q:v", "2", tempPath],
      );
      if (!ok) {
        await _deleteQuietly(tempPath);
        return "rasmni o'qib bo'lmadi";
      }
      jpgPath = tempPath;
    }

    try {
      final image = pw.MemoryImage(await File(jpgPath).readAsBytes());
      final double ratio = (image.height ?? 1) / (image.width ?? 1);
      final pageFormat = pdf.PdfPageFormat(pdf.PdfPageFormat.a4.width, pdf.PdfPageFormat.a4.width * ratio);
      final document = pw.Document();
      document.addPage(
        pw.Page(
          pageFormat: pageFormat,
          margin: pw.EdgeInsets.zero,
          build: (_) => pw.Center(child: pw.Image(image)),
        ),
      );
      await File(outPath).writeAsBytes(await document.save(), flush: true);
      return null;
    } finally {
      if (tempPath != null) await _deleteQuietly(tempPath);
    }
  }

  // Bitta faylni aylantiradi. Muvaffaqiyatli bo'lsa null, aks holda xato sababini qaytaradi
  Future<String?> _convertOne(PlatformFile file, Directory outDir, Set<String> usedPaths) async {
    final inPath = file.path;
    if (inPath == null) return "fayl manzili topilmadi";
    final ext = (file.extension ?? "").toLowerCase();
    final baseName = "${file.name.replaceAll(RegExp(r'\.[^\.]+$'), '')}_ANYtoANY";

    // FFmpeg PDF bilan ishlamaydi, shuning uchun PDF alohida aylantiriladi
    if (ext == "pdf") {
      if (!_imageFormats.contains(_targetFormat)) {
        return "PDF faylni faqat PNG yoki JPG ga aylantirish mumkin";
      }
      await _pdfToImages(inPath, outDir, baseName, usedPaths);
      return null;
    }
    if (_targetFormat == "pdf") {
      if (!_imageInputs.contains(ext)) {
        return "PDF ga faqat rasm fayllarni aylantirish mumkin";
      }
      final outPath = _uniquePath(outDir, baseName, "pdf", usedPaths);
      final error = await _imageToPdf(inPath, ext, outPath);
      if (error != null) await _deleteQuietly(outPath);
      return error;
    }

    final outPath = _uniquePath(outDir, baseName, _targetFormat, usedPaths);
    if (await _runFfmpeg(_ffmpegArgs(inPath, outPath))) return null;
    await _deleteQuietly(outPath);
    return "bu faylni .$_targetFormat ga aylantirib bo'lmadi";
  }

  Future<void> _convertFilesOffline() async {
    if (_selectedFiles.isEmpty || _isConverting) return;
    final files = List<PlatformFile>.of(_selectedFiles);
    setState(() {
      _isConverting = true;
      _completedCount = 0;
      _failedCount = 0;
    });

    final errors = <String>[];
    int done = 0;
    String savedTo = "";
    try {
      final outDir = await _resolveOutputDir();
      savedTo = outDir.path == _publicDownloadDir ? "Download papkasiga" : "${outDir.path} papkasiga";
      final usedPaths = <String>{};

      // PDF sahifalarini parallel chizib bo'lmaydi, qolgan fayllar 4 tadan aylantiriladi
      final bool hasPdf =
          _targetFormat == "pdf" || files.any((f) => (f.extension ?? "").toLowerCase() == "pdf");
      final int batchSize = hasPdf ? 1 : 4;

      for (int i = 0; i < files.length; i += batchSize) {
        final batch = files.skip(i).take(batchSize);
        await Future.wait(batch.map((file) async {
          String? error;
          try {
            error = await _convertOne(file, outDir, usedPaths);
          } catch (e) {
            error = "$e";
          }
          if (error == null) {
            done++;
          } else {
            errors.add("${file.name}: $error");
          }
          if (mounted) {
            setState(() {
              _completedCount = done;
              _failedCount = errors.length;
            });
          }
        }));
      }
    } catch (e) {
      errors.add("$e");
    } finally {
      if (mounted) setState(() => _isConverting = false);
    }

    if (!mounted) return;
    String message = done > 0
        ? "Tayyor! $done ta fayl $savedTo saqlandi."
        : "Hech bir fayl aylantirilmadi.";
    if (errors.isNotEmpty) {
      final String firstError =
          errors.first.length > 160 ? "${errors.first.substring(0, 160)}..." : errors.first;
      message += "\n${errors.length} ta xatolik. $firstError";
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(duration: const Duration(seconds: 6), content: Text(message)),
    );
  }

  // Mijoz kartaga pul o'tkazgach so'rov yuborishi
  Future<void> _sendPaymentNotification(String cardDetails) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id');
      if (userId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Avval ilovaga qaytadan kiring!")),
          );
        }
        return;
      }

      final String now = DateTime.now().toIso8601String();
      final updated = await Supabase.instance.client
          .from('user_profiles')
          .update({
            'payment_requested': true,
            'payment_info': cardDetails,
            'updated_at': now,
          })
          .eq('id', userId)
          .select('id');

      // Profil qatori hali yaratilmagan bo'lsa, so'rov yo'qolib ketmasligi uchun yaratiladi
      if (updated.isEmpty) {
        await Supabase.instance.client.from('user_profiles').upsert({
          'id': userId,
          'email': _userEmail,
          'android_id': _deviceId,
          'total_seconds': _totalSeconds,
          'is_pro': _isPro,
          'payment_requested': true,
          'payment_info': cardDetails,
          'updated_at': now,
        });
      }

      if (mounted) {
        setState(() => _paymentRequested = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("To'lov ma'lumoti yuborildi! Admin tasdiqlashi bilan PRO avtomatik yonadi."),
          ),
        );
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
                      onChanged: _isConverting
                          ? null
                          : (v) {
                              if (v != null) _onFormatChanged(v);
                            },
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_videoFormats.contains(_targetFormat))
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: "Video Kodekni tanlang",
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _videoCodec,
                    isExpanded: true,
                    isDense: true,
                    items: _codecsFor(_targetFormat)
                        .map((c) => DropdownMenuItem<String>(
                              value: c["val"]!,
                              child: Text(c["name"]!, overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    onChanged: _isConverting
                        ? null
                        : (v) {
                            if (v != null) setState(() => _videoCodec = v);
                          },
                  ),
                ),
              ),
            const SizedBox(height: 10),
            if (_isConverting) ...[
              LinearProgressIndicator(
                value: _selectedFiles.isEmpty
                    ? 0
                    : (_completedCount + _failedCount) / _selectedFiles.length,
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
                          subtitle: Text(
                            "${((f.lengthSync() ?? 0) / 1024 / 1024).toStringAsFixed(2)} MB -> .$_targetFormat",
                          ),
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
      if (mounted) setState(() => _users = data);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Ro'yxatni yuklab bo'lmadi: $e")),
        );
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _toggleUserPro(String id, bool currentPro) async {
    try {
      await Supabase.instance.client.from('user_profiles').update({
        'is_pro': !currentPro,
        'payment_requested': false,
      }).eq('id', id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("O'zgartirib bo'lmadi: $e")),
        );
      }
      return;
    }
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
                final bool isPro = u['is_pro'] == true;
                final bool payReq = u['payment_requested'] == true;
                final int mins = ((u['total_seconds'] as num?)?.toInt() ?? 0) ~/ 60;
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
                      onPressed: () => _toggleUserPro(u['id'].toString(), isPro),
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
