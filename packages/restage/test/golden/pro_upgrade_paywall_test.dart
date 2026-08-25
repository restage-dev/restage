import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';

/// Test fixture mirroring `apps/examples/lib/paywalls/pro_upgrade_paywall.dart`.
///
/// Replicated inline because the SDK's test environment cannot import from the
/// `apps/examples/` package.
@PaywallSource(id: 'pro_upgrade')
class _ProUpgradePaywall extends StatelessWidget {
  const _ProUpgradePaywall();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Restage Pro',
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Native paywalls authored in Flutter, served over the air.',
                  style: TextStyle(fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),
                ElevatedButton(
                  onPressed: paywallEvent(
                    'cta_tapped',
                    args: const {'action': 'primary'},
                  ),
                  child: const Text('Subscribe — \$X.XX / mo'),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: paywallEvent(
                    'cta_tapped',
                    args: const {'action': 'secondary'},
                  ),
                  child: const Text('\$X.XX / yr — best value'),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: paywallEvent(
                    'cta_tapped',
                    args: const {'action': 'tertiary'},
                  ),
                  child: const Text('Restore purchases'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

void main() {
  testWidgets('pro_upgrade paywall (Dart-authored) golden', (tester) async {
    tester.view.physicalSize = const Size(1320, 2868);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      home: const _ProUpgradePaywall(),
    ));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(_ProUpgradePaywall),
      matchesGoldenFile('goldens/pro_upgrade_paywall.png'),
    );
    // Goldens are recorded on macOS. Linux's font renderer produces
    // sub-percent pixel differences that aren't actionable — skip the
    // pixel comparison on non-mac so CI stays meaningful.
  }, skip: !Platform.isMacOS);
}
