import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'apex_drop.rsscreen.g.dart';

/// A single-screen in-app message — a streetwear product "drop" announcement.
///
/// A "message" is the simplest possible flow: one screen, one terminal state,
/// authored exactly like an onboarding screen. The card offers two choices:
///
/// - **Shop the drop** fires [act], the flow's one graph transition. It
///   completes the flow; the host's `onComplete` then does the real work (open
///   the product / the shop). A CTA that "acts" is just a flow that completes.
/// - **×** fires [dismiss], a flow custom event the host listens for to close
///   the message. Dismissing is not a graph transition — the message goes away.
@ScreenSource(id: 'apex_drop')
class ApexDropScreen extends StatelessWidget {
  /// The primary action — completes the flow so the host can act on it.
  static const act = OnboardingEvent<void>('act');

  /// Dismisses the message (host-handled custom event).
  static const dismiss = OnboardingEvent<void>('dismiss');

  const ApexDropScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    onPressed: onboardingEvent(dismiss),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Color(0xFF8C8C8C),
                    ),
                  ),
                ],
              ),
              Container(
                height: 232,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF00E5FF), Color(0xFF0091C2)],
                  ),
                ),
                child: const Center(
                  child: Icon(
                    Icons.flash_on_rounded,
                    size: 116,
                    color: Color(0xFF0A0A0A),
                  ),
                ),
              ),
              const SizedBox(height: 26),
              const Text(
                'NEW DROP',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF00E5FF),
                  letterSpacing: 2.4,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Velocity Run',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: -0.6,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Members get first access. Limited pairs — once they’re gone, '
                'they’re gone.',
                style: TextStyle(
                  fontSize: 16,
                  color: Color(0xFFB0B0B0),
                  height: 1.5,
                ),
              ),
              const Spacer(),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF00E5FF),
                  foregroundColor: const Color(0xFF0A0A0A),
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: onboardingEvent(act),
                child: const Text(
                  'Shop the drop',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
