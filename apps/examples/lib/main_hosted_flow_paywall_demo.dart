import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import 'stub_products.dart';

/// Dev-only entrypoint: renders a HOSTED (OTA) **flow-shaped** paywall
/// (`fluent_pro` — a lowered `Navigator.push` paywall) fetched from a real
/// Restage backend through the SDK paywall flow active arm. This exercises the
/// hosted flow-paywall delivery path end to end (no in-app fake server).
///
///   flutter run -t lib/main_hosted_flow_paywall_demo.dart \
///     --dart-define=RESTAGE_BASE_URL=https://<backend> \
///     --dart-define=RESTAGE_API_KEY=rs_pk_...
///
/// `Restage.configure(baseUrl: …)` installs a `RestageVariantResolver` wired to
/// the backend; it fetches the active published version of `fluent_pro`. When
/// that active version is flow-shaped, the paywall flow active arm resolves +
/// renders it, gated against the app's bundled `fluent_pro` flow contract
/// (bundled from `assets/paywalls/` + `assets/paywalls/screens/`).
///
/// A load failure prints its reason to the console (see [_onEvent]) so a
/// failed hosted fetch is self-diagnosing rather than only visible on-screen.
const _baseUrl = String.fromEnvironment('RESTAGE_BASE_URL');
const _apiKey = String.fromEnvironment('RESTAGE_API_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Restage.configure(
    apiKey: _apiKey,
    baseUrl: _baseUrl,
    environment: RestageEnvironment.production,
    products: kStubProducts,
  );
  runApp(const _HostedFlowPaywallDemoApp());
}

class _HostedFlowPaywallDemoApp extends StatelessWidget {
  const _HostedFlowPaywallDemoApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'fluent_pro — hosted flow paywall',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        body: RestagePaywall(
          id: 'fluent_pro',
          priceQueries: kStubPriceQueries,
          onEvent: _onEvent,
          loadingBuilder: (context) =>
              const Center(child: CircularProgressIndicator()),
          errorBuilder: (context, error) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Paywall unavailable: $error',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void _onEvent(RestageEvent event) {
  if (event is PaywallLoadFailed) {
    debugPrint(
      '[hosted-flow-demo] paywall LOAD FAILED — '
      'code=${event.errorCode} retryable=${event.retryable} '
      'message="${event.message}"',
    );
  } else {
    debugPrint('[hosted-flow-demo] paywall event: ${event.name}');
  }
}
