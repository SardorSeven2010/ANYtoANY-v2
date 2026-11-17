import 'package:flutter/material.dart';

import '../config.dart';
import '../services/profile_service.dart';

/// Bepul sinov yoki obuna muddati haqida qisqa eslatma. Kerak bo'lmasa hech narsa ko'rsatmaydi.
class TrialBanner extends StatelessWidget {
  final VoidCallback onTap;
  const TrialBanner({super.key, required this.onTap});

  /// Ko'rsatiladigan matn. Eslatma kerak bo'lmasa null.
  static String? messageFor(ProfileService p, {DateTime? now}) {
    final until = p.proUntil;
    if (p.trialActive && until != null) {
      final left = daysLeft(until, now: now);
      return "Bepul sinov: $left kun qoldi. Keyin oyiga ${formatSom(proPlans.first.price)}";
    }
    if (p.expiringSoon && until != null) {
      return "PRO ${daysLeft(until, now: now)} kundan keyin tugaydi. Uzaytirish uchun bosing";
    }
    if (!p.proActive && p.trialStartedAt != null) {
      return "Bepul sinov tugadi. PRO olish uchun bosing";
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: profile,
      builder: (context, _) {
        final text = messageFor(profile);
        if (text == null) return const SizedBox.shrink();
        final scheme = Theme.of(context).colorScheme;
        final bool warn = !profile.proActive || profile.expiringSoon;
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Material(
            color: warn ? scheme.errorContainer : scheme.primaryContainer,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              key: const Key("trialBanner"),
              borderRadius: BorderRadius.circular(14),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    Icon(
                      warn ? Icons.hourglass_bottom_rounded : Icons.card_giftcard_rounded,
                      size: 20,
                      color: warn ? scheme.onErrorContainer : scheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        text,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: warn ? scheme.onErrorContainer : scheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
