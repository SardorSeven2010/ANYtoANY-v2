import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../services/profile_service.dart';
import '../widgets/app_drawer.dart';
import 'converter_screen.dart';
import 'online_pdf_screen.dart';
import 'player_screen.dart';
import 'subscription_screen.dart';
import 'viewers.dart';

// ================= ASOSIY OYNA =================
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
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

  Future<void> _openPdfReader() async {
    try {
      final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ["pdf"]);
      final path = file?.path;
      if (file == null || path == null || !mounted) return;
      _open(PdfViewerScreen(pdfPath: path, fileName: file.name));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Faylni tanlab bo'lmadi: $e")),
      );
    }
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
            title: const Text("ANYtoANY", style: TextStyle(fontWeight: FontWeight.w800)),
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
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            children: [
              _statusCard(scheme),
              const SizedBox(height: 16),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.98,
                children: [
                  _ToolCard(
                    icon: Icons.transform_rounded,
                    title: "Media konvertor",
                    subtitle: "Video, audio va rasm formatlari",
                    onTap: () => _open(const ConverterScreen(mode: ConverterMode.media)),
                  ),
                  _ToolCard(
                    icon: Icons.audiotrack_rounded,
                    title: "Videodan audio",
                    subtitle: "Videodan ovozni ajratib olish",
                    onTap: () => _open(const ConverterScreen(mode: ConverterMode.videoToAudio)),
                  ),
                  _ToolCard(
                    icon: Icons.description_rounded,
                    title: "PDF dan Word / PowerPoint",
                    subtitle: "Tahrirlanadigan hujjat (onlayn)",
                    pro: true,
                    onTap: () => _open(const OnlinePdfScreen()),
                  ),
                  _ToolCard(
                    icon: Icons.picture_as_pdf_rounded,
                    title: "PDF va rasm",
                    subtitle: "PDF dan rasm, rasmdan PDF",
                    onTap: () => _open(const ConverterScreen(mode: ConverterMode.pdfImage)),
                  ),
                  _ToolCard(
                    icon: Icons.play_circle_fill_rounded,
                    title: "Pleyer",
                    subtitle: "Video va audio ijro etish",
                    onTap: () => _open(const PlayerPickScreen()),
                  ),
                  _ToolCard(
                    icon: Icons.menu_book_rounded,
                    title: "PDF o'qish",
                    subtitle: "PDF faylni ochib ko'rish",
                    onTap: _openPdfReader,
                  ),
                ],
              ),
            ],
          ),
        );
      },
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

class _ToolCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool pro;
  final VoidCallback onTap;
  const _ToolCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.pro = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
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
                  const Spacer(),
                  if (pro)
                    Container(
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
                ],
              ),
              const Spacer(),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, height: 1.15),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant, height: 1.2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
