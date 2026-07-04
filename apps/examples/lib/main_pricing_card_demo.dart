import 'package:flutter/material.dart';
import 'package:restage/restage.dart';
import 'package:restage_example/user_factories.g.dart';

/// On-device demo for the `pricing_showcase` paywall — a **customer data class
/// rendered natively from the delivered blob**.
///
/// The paywall (`lib/paywalls/pricing_showcase.dart`) authors
/// `PricingCard(plan: Plan(...))` in ordinary Flutter; the build-time codegen
/// encodes each `Plan` value into `assets/paywalls/pricing_showcase.rfw` as a
/// field-name-keyed map. This entrypoint renders that bundled blob through the
/// SDK — the `PricingCard` factory reconstructs each `Plan` and paints it as
/// real Flutter widgets. Run it on a real device to confirm the native render
/// fidelity a web smoke cannot see (status bar, theming, real pixels):
///
///   flutter run -t lib/main_pricing_card_demo.dart --no-tree-shake-icons
///
/// This closes the chain end to end: source → encode → wire → decode → pixels.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Register the example's custom widgets (incl. PricingCard) so the delivered
  // blob's `PricingCard(plan: ...)` reference resolves to its generated factory.
  registerRestageCustomerWidgets();
  runApp(const _PricingCardDemoApp());
}

class _PricingCardDemoApp extends StatelessWidget {
  const _PricingCardDemoApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pricing card demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF6366F1),
        useMaterial3: true,
      ),
      home: Scaffold(
        body: RestagePaywall(
          id: 'pricing_showcase',
          // The bundled blob (the codegen's encode output) — no backend needed.
          resolver: const AssetVariantResolver(),
          onEvent: (event) => debugPrint('paywall event: ${event.toMap()}'),
          loadingBuilder: (context) =>
              const Center(child: CircularProgressIndicator()),
          errorBuilder: (context, error) => Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'This paywall is unavailable right now.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
