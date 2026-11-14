import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../config.dart';
import '../services/profile_service.dart';
import '../widgets/app_drawer.dart';
import '../widgets/trial_banner.dart';
import 'converter_screen.dart';
import 'media_library.dart';
import 'online_pdf_screen.dart';
import 'pdf_merge_screen.dart';
import 'subscription_screen.dart';
import 'viewers.dart';

// ================= ASOSIY OYNA =================
// Pastda 3 ta bo'lim: fayl konvertori, video fayllar, audio fayllar.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  static const List<String> _titles = [appName, "Video fayllar", "Audio fayllar"];

  int _tab = 0;
  // Bo'lim birinchi marta ochilgandagina yuklanadi
  final Set<int> _opened = {0};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    profile.load();
    profile.startTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      profile.syncToServer();
    } else if (state == AppLifecycleState.resumed) {
      profile.refreshFromServer();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    profile.stopTimer();
    super.dispose();
  }

  void _open(Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: profile,
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        return AppScaffold(
          drawer: const AppDrawer(),
          appBar: AppBar(
            title: Text(_titles[_tab], style: const TextStyle(fontWeight: FontWeight.w800)),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: ActionChip(
                  avatar: Icon(
                    Icons.workspace_premium_rounded,
                    color: profile.proActive ? Colors.amber.shade600 : scheme.onSurfaceVariant,
                  ),
                  label: Text(profile.proActive ? "PRO FAOL" : "PRO OLISH"),
                  onPressed: () => _open(const SubscriptionScreen()),
                ),
              ),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() {
              _tab = i;
              _opened.add(i);
            }),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.transform_outlined),
                selectedIcon: Icon(Icons.transform_rounded),
                label: "Konvertor",
              ),
              NavigationDestination(
                icon: Icon(Icons.video_library_outlined),
                selectedIcon: Icon(Icons.video_library_rounded),
                label: "Video",
              ),
              NavigationDestination(
                icon: Icon(Icons.library_music_outlined),
                selectedIcon: Icon(Icons.library_music_rounded),
                label: "Audio",
              ),
            ],
          ),
          body: Column(
            children: [
              TrialBanner(onTap: () => _open(const SubscriptionScreen())),
              Expanded(
                child: IndexedStack(
                  index: _tab,
                  children: [
                    const _ConverterTab(),
                    _opened.contains(1) ? const MediaLibraryTab(kind: MediaKind.video) : const SizedBox.shrink(),
                    _opened.contains(2) ? const MediaLibraryTab(kind: MediaKind.audio) : const SizedBox.shrink(),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ================= 1-BO'LIM: FAYL KONVERTORI =================
class _ConverterTab extends StatelessWidget {
  const _ConverterTab();

  void _open(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  Future<void> _openPdfReader(BuildContext context) async {
    try {
      final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ["pdf"]);
      final path = file?.path;
      if (file == null || path == null || !context.mounted) return;
      _open(context, PdfViewerScreen(pdfPath: path, fileName: file.name));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Faylni tanlab bo'lmadi: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      children: [
        // Profil yuklanganda yoki PRO o'zgarganda kartochka yangilanadi
        ListenableBuilder(listenable: profile, builder: (context, _) => _statusCard(scheme)),
        const SizedBox(height: 14),
        const _SectionTitle("Video va audio"),
        _ToolRow(
          icon: Icons.movie_filter_rounded,
          title: "Video konvertor",
          subtitle: "Videoni boshqa format va kodekka",
          onTap: () => _open(context, const ConverterScreen(mode: ConverterMode.video)),
        ),
        _ToolRow(
          icon: Icons.audiotrack_rounded,
          title: "Videodan audio",
          subtitle: "Videodan ovozni ajratib olish",
          onTap: () => _open(context, const ConverterScreen(mode: ConverterMode.videoToAudio)),
        ),
        _ToolRow(
          icon: Icons.graphic_eq_rounded,
          title: "Audio konvertor",
          subtitle: "MP3, WAV, FLAC va boshqalar",
          onTap: () => _open(context, const ConverterScreen(mode: ConverterMode.audio)),
        ),
        const _SectionTitle("PDF, hujjat va rasm"),
        _ToolRow(
          icon: Icons.description_rounded,
          title: "PDF dan Word",
          subtitle: "Word, PowerPoint, Excel",
          pro: true,
          onTap: () => _open(context, const OnlinePdfScreen(mode: OnlineMode.fromPdf)),
        ),
        _ToolRow(
          icon: Icons.note_add_rounded,
          title: "Hujjatdan PDF",
          subtitle: "Word, Excel, PowerPoint",
          pro: true,
          onTap: () => _open(context, const OnlinePdfScreen(mode: OnlineMode.toPdf)),
        ),
        _ToolRow(
          icon: Icons.merge_rounded,
          title: "PDF birlashtirish",
          subtitle: "Bir nechta PDF ni bittaga qo'shish",
          onTap: () => _open(context, const PdfMergeScreen()),
        ),
        _ToolRow(
          icon: Icons.picture_as_pdf_rounded,
          title: "Rasm va PDF",
          subtitle: "Rasmdan PDF, PDF dan rasm",
          onTap: () => _open(context, const ConverterScreen(mode: ConverterMode.pdfImage)),
        ),
        _ToolRow(
          icon: Icons.menu_book_rounded,
          title: "PDF o'qish",
          subtitle: "PDF faylni ochib ko'rish",
          onTap: () => _openPdfReader(context),
        ),
      ],
    );
  }

  Widget _statusCard(ColorScheme scheme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: scheme.primaryContainer,
              child: Icon(Icons.person_rounded, size: 30, color: scheme.onPrimaryContainer),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.email.isEmpty ? "Xush kelibsiz!" : profile.email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    profile.proLabel,
                    style: TextStyle(color: profile.proActive ? Colors.amber.shade700 : scheme.onSurfaceVariant),
                  ),
                  Text(
                    "Ishlatildi: ${formatUsage(profile.totalSeconds)}",
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: "Yangilash",
              onPressed: profile.refreshFromServer,
            ),
          ],
        ),
      ),
    );
  }
}

/// Konvertor bo'limidagi bitta satr
class _ToolRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool pro;
  final VoidCallback onTap;
  const _ToolRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.pro = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [scheme.primary, scheme.tertiary],
                    ),
                  ),
                  child: Icon(icon, color: scheme.onPrimary, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                if (pro)
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade600,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      "PRO",
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.black),
                    ),
                  ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Konvertor bo'limidagi guruh sarlavhasi
class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
