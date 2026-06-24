import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:restage/restage.dart';
import 'package:restage_shared/restage_shared.dart';

import 'stub_products.dart';

/// Dev-only entrypoint that renders a paywall via **Restage-hosted delivery** —
/// fetched through `RestageVariantResolver`, exactly as a production app would.
///
/// Two modes, selected by `--dart-define`:
///
///  - **Self-contained (default).** An in-app fake surface server packages the
///    bundled `narrate_membership.rfw` into the surface-document envelope a Restage
///    backend would serve and hands it back, so the hosted-delivery path runs
///    end-to-end with no backend and no seed. Good for a quick local check / CI.
///
///        flutter run -t lib/main_hosted_paywall_demo.dart
///
///  - **Against a real backend (the device smoke).** Point the resolver at a
///    live delivery origin with a publishable key. First publish a real blob
///    (`restage surface publish narrate_membership --type paywall`), then:
///
///        flutter run -t lib/main_hosted_paywall_demo.dart \
///          --dart-define=RESTAGE_BASE_URL=https://your-backend.example \
///          --dart-define=RESTAGE_API_KEY=rs_pk_live_...
///
/// Either way the screen rendering, fail-closed fallback, and analytics wiring
/// are identical to the bundled-asset demo — only the delivery changes.
const _baseUrl = String.fromEnvironment('RESTAGE_BASE_URL');
const _apiKey =
    String.fromEnvironment('RESTAGE_API_KEY', defaultValue: 'rs_pk_demo');
const _paywallId = 'narrate_membership';

// A non-routable stand-in origin for the self-contained fake-server mode (the
// real origin is supplied via --dart-define, never baked in).
const _fakeBaseUrl = 'https://fake-surfaces.local';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (_baseUrl.isEmpty) {
    // Self-contained mode: serve the bundled paywall through an in-app fake
    // server so the hosted path renders anywhere, with no real backend.
    final envelope = await buildPaywallSurfaceEnvelope(_paywallId);
    Restage.configure(
      apiKey: _apiKey,
      baseUrl: _fakeBaseUrl,
      products: kStubProducts,
      resolver: RestageVariantResolver(
        apiKey: _apiKey,
        environment: RestageEnvironment.sandbox,
        baseUrl: _fakeBaseUrl,
        httpClient: FakeSurfaceServer(envelope),
      ),
    );
  } else {
    // Real hosted delivery: `configure` installs `RestageVariantResolver`
    // wired to the configured base URL as the default — it fetches the active
    // published version of the paywall from the backend.
    Restage.configure(
      apiKey: _apiKey,
      baseUrl: _baseUrl,
      environment: RestageEnvironment.production,
      products: kStubProducts,
    );
  }

  runApp(const _HostedPaywallDemoApp());
}

/// Resolves the bundled paywall `.rfw` and re-packages it as the blob surface
/// document envelope a Restage backend would serve for it — the input the fake
/// server hands back in self-contained mode.
Future<Uint8List> buildPaywallSurfaceEnvelope(String id) async {
  final variant = await const AssetVariantResolver().resolve(id);
  // The publish floor the CLI stamps for a paywall blob; the SDK renders
  // paywalls at this client capability.
  const minClient = 3;
  return SurfaceDocumentCodec.encode(
    SurfaceDocument(
      surfaceType: SurfaceType.paywall,
      surfaceSlug: id,
      version: 1,
      minClient: minClient,
      payload: BlobSurfacePayload(minClient: minClient, blob: variant.bytes),
      publishedAt: DateTime.now().toUtc(),
    ),
  );
}

class _HostedPaywallDemoApp extends StatelessWidget {
  const _HostedPaywallDemoApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hosted paywall delivery',
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        body: RestagePaywall(
          id: _paywallId,
          priceQueries: kStubPriceQueries,
          onEvent: (event) => debugPrint('paywall event: ${event.toMap()}'),
          loadingBuilder: (context) =>
              const Center(child: CircularProgressIndicator()),
          // Fail-closed: if delivery exhausts every tier (fetch + cache +
          // bundled asset), show a plain message instead of a blank screen.
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

/// The hosted-delivery capability demo surface, self-contained for the gallery.
///
/// It serves the bundled `narrate_membership.rfw` through an in-app
/// [FakeSurfaceServer] wrapped in a per-instance [RestageVariantResolver], so the
/// over-the-air fetch path renders end to end without a backend and without
/// touching the app-wide [Restage.configure] resolver. The standalone
/// entrypoint above keeps the dual-mode (`--dart-define`) wiring for the device
/// smoke; the gallery uses this self-contained widget.
class HostedPaywallDemo extends StatefulWidget {
  /// Creates the hosted-delivery demo surface.
  const HostedPaywallDemo({super.key});

  @override
  State<HostedPaywallDemo> createState() => _HostedPaywallDemoState();
}

class _HostedPaywallDemoState extends State<HostedPaywallDemo> {
  Future<RestageVariantResolver>? _resolver;

  @override
  void initState() {
    super.initState();
    _resolver = _buildResolver();
  }

  Future<RestageVariantResolver> _buildResolver() async {
    final envelope = await buildPaywallSurfaceEnvelope(_paywallId);
    return RestageVariantResolver(
      apiKey: _apiKey,
      environment: RestageEnvironment.sandbox,
      baseUrl: _fakeBaseUrl,
      httpClient: FakeSurfaceServer(envelope),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF101012),
      child: FutureBuilder<RestageVariantResolver>(
        future: _resolver,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return RestagePaywall(
            id: _paywallId,
            // A per-instance resolver — the fake-server hosted path — so the
            // gallery's app-wide AssetVariantResolver is left untouched.
            resolver: snapshot.data,
            priceQueries: kStubPriceQueries,
            onEvent: (event) {
              debugPrint('paywall event: ${event.toMap()}');
              // The served paywall (Narrate) carries its own close affordance,
              // which surfaces as a `close` PaywallCustomEvent. Route it to a
              // host pop so the demo is escapable to the gallery — otherwise the
              // close button would fire but go unhandled (the SDK shadows the
              // gallery's ambient dispatcher with the paywall's own).
              if (event is PaywallCustomEvent &&
                  (event.eventName == 'close' || event.eventName == 'skip')) {
                Navigator.of(context).maybePop();
              }
            },
            loadingBuilder: (context) =>
                const Center(child: CircularProgressIndicator()),
            // Fail-closed: if delivery exhausts every tier, show a plain message
            // instead of a blank screen.
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
          );
        },
      ),
    );
  }
}

/// An [http.Client] that answers every request with [envelope] wrapped in the
/// SDK serve-route response shape — the in-app stand-in for the backend so the
/// self-contained demo needs no network.
class FakeSurfaceServer extends http.BaseClient {
  /// Creates a fake server that always serves [envelope].
  FakeSurfaceServer(this._envelope);

  final Uint8List _envelope;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = jsonEncode({'envelope': base64Encode(_envelope)});
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(body)),
      200,
      request: request,
    );
  }
}
