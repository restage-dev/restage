import 'package:flutter/material.dart';
import 'package:restage/restage.dart';
import 'package:restage_example/user_factories.g.dart';

/// On-device demo for the `pricing_table_showcase` paywall — a **list of
/// customer data classes rendered natively from the delivered blob**.
///
/// The paywall (`lib/paywalls/pricing_table_showcase.dart`) authors
/// `PricingTable(plans: [Plan(...), Plan(...)])` in ordinary Flutter; the
/// build-time codegen encodes the whole `List<Plan>` into
/// `assets/paywalls/pricing_table_showcase.rfw` as a list of field-name-keyed
/// maps. This entrypoint renders that bundled blob through the SDK — the
/// `PricingTable` factory reconstructs each `Plan` element in order and paints
/// the list as real Flutter widgets. Run it on a real device to confirm the
/// native render fidelity a web smoke cannot see (status bar, theming, real
/// pixels):
///
///   flutter run -t lib/main_pricing_table_demo.dart --no-tree-shake-icons
///
/// This closes the chain end to end for a list-of-data-class property:
/// source → encode → wire → decode → pixels.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Register the example's custom widgets (incl. PricingTable) so the delivered
  // blob's `PricingTable(plans: ...)` reference resolves to its generated
  // factory.
  registerRestageCustomerWidgets();
  runApp(const _PricingTableDemoApp());
}

class _PricingTableDemoApp extends StatelessWidget {
  const _PricingTableDemoApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pricing table demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF6366F1),
        useMaterial3: true,
      ),
      home: Scaffold(
        body: RestagePaywall(
          id: 'pricing_table_showcase',
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
