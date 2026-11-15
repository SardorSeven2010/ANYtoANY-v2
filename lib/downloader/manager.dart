import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../services/background.dart';
import '../services/media_tools.dart';
import '../services/native_bridge.dart';
import 'common.dart';
import 'job_runner.dart';

enum JobStatus { queued, running, done, failed, canceled }

/// Bitta yuklash: holati, jarayoni, tezligi va natijasi
class DownloadJob extends ChangeNotifier {
  DownloadJob(this.id, this.request, {DateTime? createdAt}) : createdAt = createdAt ?? DateTime.now();

  final String id;
  final DownloadRequest request;
  final DateTime createdAt;

  JobStatus status = JobStatus.queued;
  JobStage? stage;
  int received = 0;
  int? total;
  int activeSegments = 0;
  double speed = 0; // bayt/soniya
  String? error;
  String? outputPath;
  int? outputBytes;
  bool inGallery = false;
  String? note;
  DateTime? finishedAt;
  CancelToken? cancelToken;

  String get title => request.title;

  bool get isFinished => status == JobStatus.done || status == JobStatus.failed || status == JobStatus.canceled;

  double? get fraction {
    final t = total;
    if (t == null || t <= 0) return null;
    return (received / t).clamp(0.0, 1.0);
  }

  Duration? get eta {
    final t = total;
    if (t == null || speed < 1 || received >= t) return null;
    return Duration(seconds: ((t - received) / speed).ceil());
  }

  void touch() => notifyListeners();
}

/// Yuklashni bajaradigan funksiya (testlarda soxta bilan almashtiriladi)
typedef JobRunner = Future<JobResult> Function(DownloadRequest request, Directory outDir, Set<String> used, JobCallbacks callbacks);

/// Haftalik limit hisobi uchun yuklashlar jurnali
abstract class DownloadLog {
  Future<List<DateTime>> recent();
  Future<void> record({required String host, required String kind});
}

/// Qurilma xotirasi + serverdagi `download_log` jadvali (ilovani qayta o'rnatib limitni aylanib o'tmaslik uchun)
class PrefsDownloadLog implements DownloadLog {
  static const String _key = 'download_starts';

  SupabaseClient? get _client {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<DateTime>> recent() async {
    final since = DateTime.now().subtract(const Duration(days: 7));
    final all = <DateTime>{};
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final s in prefs.getStringList(_key) ?? const <String>[]) {
        final t = DateTime.tryParse(s);
        if (t != null && t.isAfter(since)) all.add(t);
      }
    } catch (_) {}
    final client = _client;
    if (client != null && client.auth.currentUser != null) {
      try {
        final rows = await client
            .from('download_log')
            .select('created_at')
            .gte('created_at', since.toUtc().toIso8601String())
            .timeout(const Duration(seconds: 6));
        for (final r in rows) {
          final t = DateTime.tryParse((r['created_at'] ?? '').toString());
          if (t != null) all.add(t.toLocal());
        }
      } catch (_) {
        // internet yo'q: qurilmadagi hisob bilan davom etamiz
      }
    }
    return all.toList()..sort();
  }

  @override
  Future<void> record({required String host, required String kind}) async {
    final now = DateTime.now();
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = (prefs.getStringList(_key) ?? <String>[])
          .where((s) => (DateTime.tryParse(s) ?? now).isAfter(now.subtract(const Duration(days: 7))))
          .toList()
        ..add(now.toIso8601String());
      await prefs.setStringList(_key, list);
    } catch (_) {}
    final client = _client;
    if (client != null && client.auth.currentUser != null) {
      try {
        await client.from('download_log').insert({'host': host, 'kind': kind}).timeout(const Duration(seconds: 6));
      } catch (_) {}
    }
  }
}

/// start() natijasi: yuklash boshlandi yoki sabab bilan rad etildi
class StartOutcome {
  final DownloadJob? job;
  final String? blocked;
  const StartOutcome.started(DownloadJob this.job) : blocked = null;
  const StartOutcome.blocked(String this.blocked) : job = null;
  bool get ok => job != null;
}

/// Yuklashlar boshqaruvchisi: navbat (bir vaqtda 2 ta), haftalik limit, tarix, bildirishnoma va fon xizmati.
class DownloadManager extends ChangeNotifier {
  DownloadManager({
    JobRunner? runner,
    DownloadLog? log,
    this.maxParallel = 2,
    Future<Directory> Function()? outDir,
    NativeBridge? bridge,
    BackgroundCoordinator? background,
    DateTime Function()? clock,
  })  : _runner = runner ?? runDownloadJob,
        _log = log ?? PrefsDownloadLog(),
        _outDir = outDir ?? downloadsDir,
        _bridgeOverride = bridge,
        _backgroundOverride = background,
        _clock = clock ?? DateTime.now;

  static const String _historyKey = 'download_history';

  final JobRunner _runner;
  final DownloadLog _log;
  final int maxParallel;
  final Future<Directory> Function() _outDir;
  final NativeBridge? _bridgeOverride;
  final BackgroundCoordinator? _backgroundOverride;
  final DateTime Function() _clock;

  final List<DownloadJob> _jobs = [];
  final Set<String> _usedPaths = {};
  int _seq = 0;
  Timer? _bgTimer;
  bool _loaded = false;

  NativeBridge get _bridge => _bridgeOverride ?? nativeBridge;
  BackgroundCoordinator get _background => _backgroundOverride ?? backgroundService;

  List<DownloadJob> get jobs => List.unmodifiable(_jobs);
  int get activeCount => _jobs.where((j) => j.status == JobStatus.queued || j.status == JobStatus.running).length;
  int get runningCount => _jobs.where((j) => j.status == JobStatus.running).length;

  // ---------- limit ----------

  /// Bu hafta nechta yuklash qolgani (PRO: null = cheksiz)
  Future<int?> remainingThisWeek(bool pro) async {
    final limits = DownloadLimits(pro: pro);
    if (limits.weeklyLimit == null) return null;
    final left = limits.remaining(await _log.recent(), now: _clock());
    return ((left ?? 0) - activeCount).clamp(0, 1 << 30);
  }

  /// Yuklashni navbatga qo'yadi. Limit tugagan bo'lsa, sabab bilan rad etadi.
  Future<StartOutcome> start(DownloadRequest request, {required bool pro}) async {
    final limits = DownloadLimits(pro: pro);
    final starts = await _log.recent();
    final now = _clock();
    final remaining = limits.remaining(starts, now: now);
    if (remaining != null && remaining - activeCount <= 0) {
      final next = limits.nextSlotAt(starts, now: now);
      final when = next == null ? "" : " Keyingisi ${formatDate(next)} dan ochiladi.";
      return StartOutcome.blocked("Bu hafta ${limits.weeklyLimit} ta yuklash limiti tugadi.$when PRO obunada cheklov yo'q.");
    }
    final req = DownloadRequest(
      url: request.url,
      title: request.title,
      headers: request.headers,
      kind: request.kind,
      segments: limits.clampSegments(request.segments),
      codec: pro ? request.codec : OutputCodec.original,
      pageUrl: request.pageUrl,
      variantUrl: request.variantUrl,
    );
    final job = DownloadJob("${_clock().microsecondsSinceEpoch}_${_seq++}", req, createdAt: now);
    _jobs.insert(0, job);
    notifyListeners();
    _pump();
    return StartOutcome.started(job);
  }

  // ---------- navbat ----------

  void _pump() {
    for (final job in _jobs.reversed.toList()) {
      if (runningCount >= maxParallel) break;
      if (job.status == JobStatus.queued) unawaited(_run(job));
    }
    _updateBackground();
  }

  Future<void> _run(DownloadJob job) async {
    job.status = JobStatus.running;
    job.cancelToken = CancelToken();
    job.error = null;
    final clock = Stopwatch()..start();
    var lastTick = 0;
    var lastBytes = 0;
    job.touch();
    notifyListeners();
    try {
      final dir = await _outDir();
      final result = await _runner(
        job.request,
        dir,
        _usedPaths,
        JobCallbacks(
          cancel: job.cancelToken!,
          onStage: (s) {
            job.stage = s;
            job.touch();
          },
          onProgress: (received, total, active) {
            job.received = received;
            job.total = total;
            job.activeSegments = active;
            final ms = clock.elapsedMilliseconds;
            if (ms - lastTick >= 700) {
              final inst = (received - lastBytes) * 1000 / (ms - lastTick);
              job.speed = job.speed == 0 ? inst : job.speed * 0.6 + inst * 0.4;
              lastTick = ms;
              lastBytes = received;
              job.touch();
              _scheduleBackgroundUpdate();
            }
          },
        ),
      );
      job.status = JobStatus.done;
      job.outputPath = result.path;
      job.outputBytes = result.bytes;
      job.inGallery = result.inGallery;
      job.note = result.note;
      job.received = result.bytes;
      job.total = result.bytes;
      job.speed = 0;
      unawaited(_log.record(host: job.request.url.host, kind: job.request.kind.name));
      unawaited(_bridge.notify(id: _notificationId(job), title: "Yuklandi", body: job.title));
    } on DownloadCancelled {
      job.status = JobStatus.canceled;
    } catch (e) {
      job.status = JobStatus.failed;
      job.error = e is DownloadException ? e.message : "Yuklab bo'lmadi";
      unawaited(_bridge.notify(id: _notificationId(job), title: "Yuklab bo'lmadi", body: "${job.title}: ${job.error}"));
    }
    job.finishedAt = _clock();
    job.stage = null;
    job.touch();
    await _saveHistory();
    notifyListeners();
    _pump();
  }

  int _notificationId(DownloadJob job) => 5000 + (job.id.hashCode & 0xfff);

  void cancel(String id) {
    final job = _find(id);
    if (job == null) return;
    if (job.status == JobStatus.queued) {
      job.status = JobStatus.canceled;
      job.finishedAt = _clock();
      job.touch();
      notifyListeners();
      _updateBackground();
    } else if (job.status == JobStatus.running) {
      job.cancelToken?.cancel();
    }
  }

  void cancelAll() {
    for (final j in List.of(_jobs)) {
      cancel(j.id);
    }
  }

  /// Xato bilan tugagan yoki bekor qilingan yuklashni qayta boshlaydi (uzilgan joyidan davom etadi)
  void retry(String id) {
    final job = _find(id);
    if (job == null || (job.status != JobStatus.failed && job.status != JobStatus.canceled)) return;
    job.status = JobStatus.queued;
    job.error = null;
    job.received = 0;
    job.total = null;
    job.speed = 0;
    job.finishedAt = null;
    job.touch();
    notifyListeners();
    _pump();
  }

  Future<void> remove(String id, {bool deleteFile = false}) async {
    final job = _find(id);
    if (job == null) return;
    if (!job.isFinished) cancel(id);
    if (deleteFile && job.outputPath != null) await deleteQuietly(job.outputPath!);
    _jobs.remove(job);
    await _saveHistory();
    notifyListeners();
  }

  Future<void> clearFinished() async {
    _jobs.removeWhere((j) => j.isFinished);
    await _saveHistory();
    notifyListeners();
  }

  DownloadJob? _find(String id) {
    for (final j in _jobs) {
      if (j.id == id) return j;
    }
    return null;
  }

  // ---------- fon xizmati va bildirishnoma ----------

  void _scheduleBackgroundUpdate() {
    if (_bgTimer?.isActive ?? false) return;
    _bgTimer = Timer(const Duration(seconds: 1), _updateBackground);
  }

  void _updateBackground() {
    final active = _jobs.where((j) => j.status == JobStatus.running || j.status == JobStatus.queued).toList();
    if (active.isEmpty) {
      _background.setDownloads(null);
      return;
    }
    final running = active.where((j) => j.status == JobStatus.running).toList();
    final fractions = running.map((j) => j.fraction).whereType<double>().toList();
    final progress = fractions.isEmpty ? -1 : (fractions.reduce((a, b) => a + b) / fractions.length * 100).round();
    _background.setDownloads(DownloadSummary(
      active: active.length,
      progress: progress,
      title: (running.isNotEmpty ? running.first : active.first).title,
    ));
  }

  // ---------- tarix ----------

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_historyKey);
      if (raw == null) return;
      for (final item in (jsonDecode(raw) as List).cast<Map<String, dynamic>>()) {
        final status = JobStatus.values.firstWhere((s) => s.name == item['status'], orElse: () => JobStatus.failed);
        final job = DownloadJob(
          item['id'] as String,
          DownloadRequest(
            url: Uri.parse(item['url'] as String),
            title: item['title'] as String,
            kind: MediaKind.values.firstWhere((k) => k.name == item['kind'], orElse: () => MediaKind.direct),
          ),
          createdAt: DateTime.tryParse(item['createdAt'] as String? ?? ''),
        )
          ..status = status
          ..error = item['error'] as String?
          ..outputPath = item['path'] as String?
          ..outputBytes = item['bytes'] as int?
          ..finishedAt = DateTime.tryParse(item['finishedAt'] as String? ?? '');
        // fayl o'chirib yuborilgan bo'lsa, "tayyor" deb ko'rsatilmaydi
        if (status == JobStatus.done && job.outputPath != null && !File(job.outputPath!).existsSync()) continue;
        _jobs.add(job);
        if (job.outputPath != null) _usedPaths.add(job.outputPath!);
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _saveHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final items = _jobs
          .where((j) => j.isFinished)
          .take(100)
          .map((j) => {
                'id': j.id,
                'url': j.request.url.toString(),
                'title': j.title,
                'kind': j.request.kind.name,
                'status': j.status.name,
                'error': j.error,
                'path': j.outputPath,
                'bytes': j.outputBytes,
                'createdAt': j.createdAt.toIso8601String(),
                'finishedAt': j.finishedAt?.toIso8601String(),
              })
          .toList();
      await prefs.setString(_historyKey, jsonEncode(items));
    } catch (_) {}
  }

  @override
  void dispose() {
    _bgTimer?.cancel();
    super.dispose();
  }
}

/// Butun ilova uchun yagona boshqaruvchi
final DownloadManager downloads = DownloadManager();

/// Bo'laklar soni: bepul tarifda 6, PRO'da 6..18
List<int> segmentChoices(bool pro) => pro ? [for (var i = freeDefaultSegments; i <= proMaxSegments; i++) i] : [freeDefaultSegments];

/// Haftalik limit matni (interfeys uchun)
String quotaLabel(bool pro, int? remaining) {
  if (pro) return "PRO: haftasiga cheklovsiz";
  return "Bu hafta qoldi: ${remaining ?? freeWeeklyDownloads} / $freeWeeklyDownloads";
}
