import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/pro_upgrade.restage.g.dart';

const kFeatures = [
  'Unlimited habits',
  'Weekly insights',
  'Home screen widgets',
];

@Paywall(id: 'pro_upgrade')
class ProUpgradePaywall extends StatelessWidget {
  const ProUpgradePaywall({super.key});

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
              onPressed: paywallEvent('continue'),
              child: const Text('Continue'),
            ),
            TextButton(
              onPressed: paywallEvent('close'),
              child: const Text('Not now'),
            ),
          ],
        ),
      ),
    );
  }
}
