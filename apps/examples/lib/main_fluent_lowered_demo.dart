import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import 'stub_products.dart';

/// On-device smoke for the **screen-navigation lowering**: the Fluent Pro entry
/// paywall in `paywalls/fluent_pro.dart` authors a `Navigator.push` to the
/// "Choose a plan" all-tiers screen, which the build-time codegen lowers to a
/// flow. It is delivered as a bundled flow and hosted here through the remote
/// render path (`RestagePaywall(id:)`) — the same delivery pipeline a real app
/// uses.
///
/// Tap "View all plans" to push the all-tiers screen, the back chevron to
/// return. On the all-tiers screen a plan tap only SELECTS it; the footer CTA
/// charges the selected tier (select-then-subscribe). The entry screen's CTA
/// charges directly. A purchase can fire on either screen; navigation drives
/// the flow.
///
/// Run on a simulator or device with:
///   flutter run -t lib/main_fluent_lowered_demo.dart
void main() {
  Restage.configure(
    apiKey: 'rs_pk_example',
    products: kStubProducts,
    resolver: const AssetVariantResolver(),
  );
  runApp(const _FluentLoweredDemoApp());
}

class _FluentLoweredDemoApp extends StatelessWidget {
  const _FluentLoweredDemoApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fluent Pro lowered-paywall-flow demo',
      debugShowCheckedModeBanner: false,
      home: RestagePaywall(
        id: 'fluent_pro',
        priceQueries: kStubPriceQueries,
        onEvent: (event) => debugPrint('paywall event: ${event.name}'),
      ),
    );
  }
}
