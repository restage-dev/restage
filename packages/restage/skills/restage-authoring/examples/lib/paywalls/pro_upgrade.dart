import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/pro_upgrade.restage.g.dart';

const kFeatures = [
  'Unlimited habits',
  'Weekly insights',
  'Home screen widgets',
];

@Paywall(id: 'pro_upgrade', completesOn: [ProUpgradePaywall.trialStarted])
class ProUpgradePaywall extends StatelessWidget {
  const ProUpgradePaywall({super.key, this.onClose, this.onStartTrial});

  /// Dismisses the paywall.
  final VoidCallback? onClose;

  /// Starts the trial; true when the purchase went through.
  final Future<bool> Function()? onStartTrial;

  /// Fired once the trial started; it completes the paywall.
  static const trialStarted = SurfaceEvent<void>('trial_started');

  Widget _feature(String text) =>
      ListTile(leading: const Icon(Icons.check), title: Text(text));

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = Text(
      'Go Pro',
      style: TextStyle(fontSize: 28, color: scheme.primary),
    );
    return Scaffold(
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            title,
            for (final feature in kFeatures) _feature(feature),
            FilledButton(
              onPressed: () async {
                final started = await onStartTrial?.call() ?? false;
                if (started && context.mounted) {
                  context.surfaceEvent(ProUpgradePaywall.trialStarted)();
                }
              },
              child: const Text('Start free trial'),
            ),
            TextButton(
              onPressed: onClose,
              child: const Text('Not now'),
            ),
          ],
        ),
      ),
    );
  }
}
