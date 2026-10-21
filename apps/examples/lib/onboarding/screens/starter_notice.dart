import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:restage/restage.dart';

part 'restage.generated/starter_notice.restage.g.dart';

/// A one-screen notice, such as an announcement or a what's-new message.
///
/// [act] completes the flow, and your app acts in `onComplete`. [dismiss] is a
/// custom event your app handles by closing the surface. It follows the app
/// theme.
@Screen()
class StarterNoticeScreen extends StatelessWidget {
  /// The primary action — completes the flow so the host can act.
  static const act = SurfaceEvent<void>('act');

  /// Dismisses the surface (host-handled custom event).
  static const dismiss = SurfaceEvent<void>('dismiss');

  /// Const constructor.
  const StarterNoticeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        systemOverlayStyle: Theme.of(context).brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: surfaceEvent(dismiss),
            tooltip: 'Dismiss',
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Icon(
                Icons.campaign_rounded,
                size: 56,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 20),
              Text(
                "What's new",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'A short, server-driven announcement — delivered over the air, '
                'rendered as real Flutter widgets.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  height: 1.45,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              FilledButton(
                onPressed: surfaceEvent(act),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Take a look'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
