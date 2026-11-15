import 'dart:async';

import 'package:flutter/material.dart';

import '../browser/backend.dart';
import '../downloader/detected.dart';
import '../downloader/manager.dart';
import '../services/background.dart';
import '../services/native_bridge.dart';
import 'download_sheets.dart';

/// Havola kiritilgan matnni manzilga aylantiradi: manzil bo'lmasa qidiruv.
Uri addressFromInput(String input) {
  final text = input.trim();
  if (text.isEmpty) return Uri.parse("about:blank");
  final hasScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(text);
  if (hasScheme) return Uri.parse(text);
  final looksLikeHost =
      !text.contains(' ') &&
      RegExp(r'^[^\s/]+\.[a-zA-Z]{2,}([/:?#].*)?$').hasMatch(text);
  if (looksLikeHost) return Uri.parse("https://$text");
  return Uri.https("duckduckgo.com", "/", {"q": text});
}

// ================= MINI-BRAUZER =================
// Sahifa ochiladi, video o'ynashi bilan detektor uni topadi va "Yuklash" tugmasi paydo bo'ladi.
/// Ekran o'chganda videoni to'xtatib qo'yadigan saytlar (YouTube): ular uchun kompyuter versiyasi o'zi yoqiladi
bool siteNeedsDesktop(String url) {
  final host = (Uri.tryParse(url)?.host ?? '').toLowerCase();
  return host == 'youtu.be' || host == 'youtube.com' || host.endsWith('.youtube.com');
}

class BrowserScreen extends StatefulWidget {
  final Uri? initial;
  final BrowserBackend? backend; // testlar uchun
  final MediaDetector? detector;
  final DownloadManager? manager;
  const BrowserScreen({
    super.key,
    this.initial,
    this.backend,
    this.detector,
    this.manager,
  });

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen>
    with WidgetsBindingObserver {
  late final BrowserBackend _browser =
      widget.backend ?? browserBackendFactory();
  late final MediaDetector _detector = widget.detector ?? MediaDetector();
  final TextEditingController _address = TextEditingController();
  final FocusNode _focus = FocusNode();

  int _progress = 0;
  bool _loading = false;
  bool _started = false;
  bool _canBack = false;
  bool _canForward = false;
  String _pageUrl = "";
  StreamSubscription<NativeEvent>? _nativeSub;
  bool _notified = false;
  bool _desktop = false;
  bool _desktopByUser = false; // foydalanuvchi o'zi tanlagan: avtomatik almashtirilmaydi
  bool _keepAlive = false;
  Timer? _keepAliveOff;

  @override
  void initState() {
    super.initState();
    _browser.onPageStarted = (url) {
      // yangi sahifa: oldingi sahifaning videolari ro'yxatdan olib tashlanadi
      if (_stripHash(url) != _stripHash(_pageUrl)) {
        _detector.reset();
        _clearNotification(); // yangi sahifa: video haqida eski bildirishnoma o'chadi
      }
      _pageUrl = url;
      if (!_focus.hasFocus) _address.text = url;
      if (mounted) setState(() => _loading = true);
      _autoDesktop(url);
      _refreshNav();
    };
    _browser.onPageFinished = (url) {
      _pageUrl = url;
      if (!_focus.hasFocus) _address.text = url;
      if (mounted) setState(() => _loading = false);
      _refreshNav();
    };
    _browser.onProgress = (p) {
      if (mounted) setState(() => _progress = p);
    };
    _browser.onMessage = _detector.onMessage;
    _browser.onMedia = _onMedia;
    WidgetsBinding.instance.addObserver(this);
    // bildirishnomadagi pleyer tugmalari sahifadagi videoni boshqaradi
    _nativeSub = nativeBridge.events.listen(_onNativeEvent);
    final initial = widget.initial;
    if (initial != null) {
      _started = true;
      _address.text = initial.toString();
      _open(initial);
    }
  }

  /// Sahifa ochishdan oldin kerakli versiya (telefon / kompyuter) tanlanadi, shunda sahifa ikki marta yuklanmaydi
  Future<void> _open(Uri uri) async {
    if (!_desktopByUser) {
      final want = siteNeedsDesktop(uri.toString());
      if (want != _desktop) await _setDesktop(want, reload: false);
    }
    await _browser.load(uri);
  }

  /// Havola bosilganda sahifa o'zi ochilgan bo'lsa ham versiya almashadi (sahifa qayta yuklanadi)
  void _autoDesktop(String url) {
    if (_desktopByUser) return;
    final want = siteNeedsDesktop(url);
    if (want == _desktop) return;
    _setDesktop(want);
    if (want && mounted) {
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text("Kompyuter versiyasi yoqildi: ekran o'chganda ham ovoz davom etadi"),
          duration: Duration(seconds: 3),
        ));
    }
  }

  Future<void> _setDesktop(bool on, {bool reload = true}) async {
    if (_desktop == on) return;
    if (mounted) {
      setState(() => _desktop = on);
    } else {
      _desktop = on;
    }
    await _browser.setDesktopMode(on);
    if (reload && _started) await _browser.reload();
  }

  /// Ekran o'chganda ham WebView'ni "ko'rinadi" holatda ushlab turish (video ovozi to'xtamasligi uchun)
  void _setKeepAlive(bool on) {
    if (on) {
      _keepAliveOff?.cancel();
      _keepAliveOff = null;
    }
    if (_keepAlive == on) return;
    _keepAlive = on;
    final id = _browser.nativeWebViewId;
    if (id != null || !on) nativeBridge.webViewKeepAlive(id ?? 0, on);
  }

  static String _stripHash(String url) => url.split('#').first;

  Future<void> _refreshNav() async {
    final back = await _browser.canGoBack();
    final fwd = await _browser.canGoForward();
    if (mounted)
      setState(() {
        _canBack = back;
        _canForward = fwd;
      });
  }

  /// Sahifadagi video o'ynay boshlasa: bildirishnomada pleyer va fon xizmati (ekran o'chganda ham ovoz davom etadi)
  void _onMedia(BrowserMedia m) {
    if (!mounted) return;
    if (!m.hasMedia) {
      _clearNotification();
      return;
    }
    _notified = true;
    if (m.playing) {
      _setKeepAlive(true);
    } else {
      // pauza: keyingi videoga o'tish paytida to'xtamaslik uchun biroz kutamiz
      _keepAliveOff ??= Timer(const Duration(seconds: 20), () {
        _keepAliveOff = null;
        _setKeepAlive(false);
      });
    }
    final title = m.title.trim().isEmpty ? "Mini-brauzer" : m.title.trim();
    backgroundService.setMedia(
      MediaInfo(title: title, subtitle: "Mini-brauzer", playing: m.playing),
    );
  }

  void _clearNotification() {
    _keepAliveOff?.cancel();
    _keepAliveOff = null;
    _setKeepAlive(false);
    if (!_notified) return;
    _notified = false;
    backgroundService.setMedia(null);
  }

  void _onNativeEvent(NativeEvent e) {
    if (e.name != 'mediaAction') return;
    switch (e.data) {
      case 'play':
        _browser.mediaCommand('play');
      case 'pause':
      case 'stop':
        _browser.mediaCommand('pause');
      case 'playpause':
        _browser.mediaCommand('toggle');
      case 'next':
        _browser.mediaCommand('next');
      case 'previous':
        _browser.mediaCommand('previous');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // ilova fonda: sayt videoni o'zi to'xtatmasin va keyingi videoga to'xtamay o'tsin
    _browser.setBackground(
      state == AppLifecycleState.paused || state == AppLifecycleState.hidden,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _nativeSub?.cancel();
    _keepAliveOff?.cancel();
    _clearNotification();
    _browser.dispose();
    _address.dispose();
    _focus.dispose();
    if (widget.detector == null) _detector.dispose();
    super.dispose();
  }

  void _go([String? text]) {
    final uri = addressFromInput(text ?? _address.text);
    if (uri.toString() == "about:blank") return;
    _focus.unfocus();
    setState(() => _started = true);
    _address.text = uri.toString();
    _open(uri);
  }

  Future<void> _showVideos() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (sheetContext) => _DetectedList(
        detector: _detector,
        onPick: (media) async {
          Navigator.of(sheetContext).pop();
          await _download(media);
        },
      ),
    );
  }

  Future<void> _download(DetectedMedia media) async {
    final page = Uri.tryParse(_pageUrl) ?? media.page;
    final headers = await _browser.requestHeaders(page);
    _detector.headers = headers;
    if (!mounted) return;
    await showDownloadSheet(
      context,
      media: media,
      title: _detector.suggestedTitle(media),
      headers: headers,
      manager: widget.manager,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !_canBack,
      onPopInvokedWithResult: (didPop, _) {
        // "Orqaga" tugmasi avval sahifa tarixida orqaga qaytadi
        if (!didPop && _canBack) _browser.goBack().then((_) => _refreshNav());
      },
      child: Scaffold(
        backgroundColor: scheme
            .surface, // Liquid Glass uslubida Scaffold shaffof: brauzerga zich fon kerak
        appBar: AppBar(
          titleSpacing: 0,
          title: TextField(
            key: const Key("browserAddress"),
            controller: _address,
            focusNode: _focus,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.go,
            autocorrect: false,
            onSubmitted: _go,
            style: TextStyle(color: scheme.onSurface),
            decoration: InputDecoration(
              hintText: "Sayt manzili yoki qidiruv",
              isDense: true,
              filled: true,
              fillColor: scheme.surfaceContainerHighest,
              prefixIcon: const Icon(Icons.public_rounded, size: 20),
              suffixIcon: IconButton(
                key: const Key("browserGo"),
                icon: const Icon(Icons.arrow_forward_rounded),
                onPressed: () => _go(),
              ),
            ),
          ),
          bottom: _loading
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(3),
                  child: LinearProgressIndicator(
                    value: _progress <= 0 ? null : _progress / 100,
                    minHeight: 3,
                  ),
                )
              : null,
        ),
        body: Stack(
          children: [
            Positioned.fill(child: _browser.view()),
            if (!_started) Positioned.fill(child: _startPage(scheme)),
            Positioned(right: 16, bottom: 16, child: _videoButton(scheme)),
          ],
        ),
        bottomNavigationBar: BottomAppBar(
          height: 56,
          padding: EdgeInsets.zero,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              IconButton(
                key: const Key("browserBack"),
                tooltip: "Orqaga",
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: _canBack
                    ? () => _browser.goBack().then((_) => _refreshNav())
                    : null,
              ),
              IconButton(
                key: const Key("browserForward"),
                tooltip: "Oldinga",
                icon: const Icon(Icons.arrow_forward_rounded),
                onPressed: _canForward
                    ? () => _browser.goForward().then((_) => _refreshNav())
                    : null,
              ),
              IconButton(
                tooltip: "Yangilash",
                icon: const Icon(Icons.refresh_rounded),
                onPressed: _started ? _browser.reload : null,
              ),
              IconButton(
                key: const Key("browserDesktop"),
                tooltip: _desktop ? "Telefon versiyasi" : "Kompyuter versiyasi",
                isSelected: _desktop,
                icon: const Icon(Icons.desktop_windows_outlined),
                selectedIcon: const Icon(Icons.desktop_windows_rounded),
                onPressed: _started
                    ? () {
                        _desktopByUser = true;
                        _setDesktop(!_desktop);
                      }
                    : null,
              ),
              IconButton(
                tooltip: "Yopish",
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Video topilganda paydo bo'ladigan tugma
  Widget _videoButton(ColorScheme scheme) {
    return ListenableBuilder(
      listenable: _detector,
      builder: (context, _) {
        final n = _detector.count;
        return AnimatedScale(
          scale: n > 0 ? 1 : 0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutBack,
          child: FloatingActionButton.extended(
            key: const Key("videoFound"),
            onPressed: n > 0 ? _showVideos : null,
            icon: const Icon(Icons.download_rounded),
            label: Text("Yuklash ($n)"),
          ),
        );
      },
    );
  }

  Widget _startPage(ColorScheme scheme) {
    return ColoredBox(
      color: scheme.surface,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.travel_explore_rounded,
                size: 72,
                color: scheme.primary,
              ),
              const SizedBox(height: 14),
              const Text(
                "Videoni toping va yuklang",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                "Yuqoriga sayt manzilini yozing yoki qidiring. Sahifada video o'ynay boshlaganda \"Yuklash\" tugmasi paydo bo'ladi.",
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 14),
              Text(
                "DRM bilan himoyalangan videolar (Netflix va shu kabi) yuklanmaydi.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetectedList extends StatelessWidget {
  final MediaDetector detector;
  final ValueChanged<DetectedMedia> onPick;
  const _DetectedList({required this.detector, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: detector,
      builder: (context, _) {
        final items = detector.items;
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.8,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              Text(
                "Topilgan videolar (${items.length})",
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              if (items.isEmpty)
                const Text("Hozircha video topilmadi. Videoni ijro eting."),
              for (var i = 0; i < items.length; i++)
                Card(
                  key: Key("detected_$i"),
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Icon(
                      items[i].downloadable
                          ? Icons.movie_rounded
                          : Icons.lock_rounded,
                      color: items[i].downloadable
                          ? scheme.primary
                          : scheme.error,
                    ),
                    title: Text(
                      items[i].pageTitle.isEmpty
                          ? items[i].url.pathSegments.lastWhere(
                              (s) => s.isNotEmpty,
                              orElse: () => items[i].url.host,
                            )
                          : items[i].pageTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(_subtitle(items[i])),
                    trailing: items[i].downloadable
                        ? const Icon(Icons.download_rounded)
                        : null,
                    onTap: items[i].downloadable
                        ? () => onPick(items[i])
                        : null,
                  ),
                ),
              if (items.any((m) => m.kind == DetectedKind.blob))
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    "Himoyalangan oqim (blob) to'g'ridan-to'g'ri yuklanmaydi. Ba'zan videoni bir necha soniya ijro etsangiz, haqiqiy manzil topiladi.",
                    style: TextStyle(fontSize: 12),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  String _subtitle(DetectedMedia m) {
    if (m.error != null) return m.error!;
    return [
      m.typeLabel,
      if (m.qualities.isNotEmpty) "${m.qualities.first.label} gacha",
      if (m.bytes != null) formatBytes(m.bytes),
      if (m.seconds != null) formatSeconds(m.seconds),
      if (!m.checked) "tekshirilmoqda...",
    ].join(" • ");
  }
}
