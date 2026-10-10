import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:restage/restage.dart';
import 'package:restage_shared/restage_shared.dart';

import 'user_factories.g.dart';

/// Renders a published surface through Restage-hosted delivery, fetched by
/// `RestageVariantResolver` as a production app would.
///
/// Against a backend, name the surface and its type. Push and publish it
/// first (`restage surface push <slug> --type paywall`, then
/// `restage surface publish <slug> --type paywall`):
///
///     flutter run -t lib/main_hosted_surface_demo.dart \
///       --dart-define=RESTAGE_BASE_URL=https://your-edge.example \
///       --dart-define=RESTAGE_API_KEY=rs_pk_... \
///       --dart-define=RESTAGE_SURFACE=<slug> \
///       --dart-define=RESTAGE_SURFACE_TYPE=paywall
///
/// The key selects the organization, project, app and environment.
///
/// Paywalls render by slug. Onboarding, message, survey and general surfaces
/// render through the generated `<Stem>Surface` mount compiled into the app,
/// so the published version must match a flow this app was built with.
///
/// With no base URL, an in-app fake server serves a bundled paywall
/// (`RESTAGE_SURFACE`, default `narrate_membership`) with no backend.
const _baseUrl = String.fromEnvironment('RESTAGE_BASE_URL');
const _apiKey = String.fromEnvironment('RESTAGE_API_KEY');
const _surfaceSlug = String.fromEnvironment('RESTAGE_SURFACE');
const _surfaceType =
    String.fromEnvironment('RESTAGE_SURFACE_TYPE', defaultValue: 'paywall');

const _bundledPaywallId = 'narrate_membership';
const _fakeApiKey = 'rs_pk_demo';

// A non-routable stand-in origin for the self-contained fake-server mode.
const _fakeBaseUrl = 'https://fake-surfaces.local';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // A string-identified paywall mounts nothing generated, so the app
  // installs its own vocabulary.
  registerRestageWidgets();

  final problem = hostedSurfaceConfigurationProblem(
    baseUrl: _baseUrl,
    apiKey: _apiKey,
    surfaceSlug: _surfaceSlug,
    surfaceType: _surfaceType,
  );
  if (problem != null) {
    runApp(_MisconfiguredApp(problem));
    return;
  }

  final String slug;
  if (_baseUrl.isEmpty) {
    slug = _surfaceSlug.isEmpty ? _bundledPaywallId : _surfaceSlug;
    final envelope = await buildPaywallSurfaceEnvelope(slug);
    Restage.configure(
      apiKey: _fakeApiKey,
      baseUrl: _fakeBaseUrl,
      resolver: RestageVariantResolver(
        apiKey: _fakeApiKey,
        environment: RestageEnvironment.sandbox,
        baseUrl: _fakeBaseUrl,
        httpClient: FakeSurfaceServer(envelope),
      ),
    );
  } else {
    slug = _surfaceSlug;
    // With a base URL and no resolver, `configure` installs
    // `RestageVariantResolver`, which fetches the published version.
    Restage.configure(apiKey: _apiKey, baseUrl: _baseUrl);
  }

  runApp(_HostedSurfaceDemoApp(slug: slug));
}

/// Why the given defines cannot render a surface, or null when they can.
String? hostedSurfaceConfigurationProblem({
  required String baseUrl,
  required String apiKey,
  required String surfaceSlug,
  required String surfaceType,
}) {
  final Surface surface;
  try {
    surface = Surface.fromWireName(surfaceType);
  } on FormatException {
    final known = Surface.values.map((s) => s.wireName).join(', ');
    return 'Unknown RESTAGE_SURFACE_TYPE "$surfaceType". Use one of: $known.';
  }
  if (surface != Surface.paywall) {
    return 'A ${surface.wireName} surface renders through its generated '
        'Surface mount, compiled into the app. This entrypoint renders '
        'paywalls by slug.';
  }
  if (baseUrl.isNotEmpty && (apiKey.isEmpty || surfaceSlug.isEmpty)) {
    return 'With RESTAGE_BASE_URL set, also set RESTAGE_API_KEY and '
        'RESTAGE_SURFACE.';
  }
  return null;
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
      surfaceType: Surface.paywall,
      surfaceSlug: id,
      version: 1,
      minClient: minClient,
      payload: BlobSurfacePayload(minClient: minClient, blob: variant.bytes),
      publishedAt: DateTime.now().toUtc(),
    ),
  );
}

class _HostedSurfaceDemoApp extends StatelessWidget {
  const _HostedSurfaceDemoApp({required this.slug});

  final String slug;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hosted surface delivery',
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        body: RestagePaywall(
          id: slug,
          onEvent: (event) => debugPrint('paywall event: ${event.toMap()}'),
          loadingBuilder: (context) =>
              const Center(child: CircularProgressIndicator()),
          // Fail-closed: if delivery exhausts every tier (fetch + cache +
          // bundled asset), show a plain message instead of a blank screen.
          errorBuilder: (context, error) => Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'Paywall "$slug" is unavailable right now.\n\n$error',
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

class _MisconfiguredApp extends StatelessWidget {
  const _MisconfiguredApp(this.problem);

  final String problem;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(problem, textAlign: TextAlign.center),
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
/// touching the app-wide [Restage.configure] resolver.
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
    final envelope = await buildPaywallSurfaceEnvelope(_bundledPaywallId);
    return RestageVariantResolver(
      apiKey: _fakeApiKey,
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
          // `hasData` is false for a failed future too, so spinning on it alone
          // turns any error on this path into a screen that never settles.
          if (snapshot.hasError) {
            debugPrint('hosted demo resolver failed: ${snapshot.error}');
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'This paywall is unavailable right now.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFFB9B9C6)),
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return RestagePaywall(
            id: _bundledPaywallId,
            // A per-instance resolver — the fake-server hosted path — so the
            // gallery's app-wide AssetVariantResolver is left untouched.
            resolver: snapshot.data,
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

  /// Where this stand-in says its content lives. Never resolved on a network —
  /// the same object answers for it.
  static const String _origin = 'https://artifacts.invalid';

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final document = SurfaceDocumentCodec.decode(_envelope);
    final content = document.payload.canonicalBytes;
    final url = '$_origin/artifacts/orgs/1/artifacts/'
        '$kSurfaceArtifactPayloadFormatVersion/${document.contentHash}';

    // Delivery is two exchanges: a description of the surface, then its
    // content. Answering both here keeps the demo on the real wire — a
    // stand-in that skipped the second exchange would exercise a delivery path
    // the app never actually takes.
    if (request.url.toString() == url) {
      return http.StreamedResponse(
        Stream<List<int>>.value(content),
        200,
        request: request,
      );
    }

    final body = jsonEncode({
      'artifact': SurfaceArtifactDescriptor(
        payloadFormatVersion: kSurfaceArtifactPayloadFormatVersion,
        surfaceType: document.surfaceType,
        surfaceSlug: document.surfaceSlug,
        version: document.version,
        publishedAtMicros: document.publishedAt.toUtc().microsecondsSinceEpoch,
        contentHash: document.contentHash,
        artifactUrl: url,
        // Shaped like a real pass. Nothing here verifies one; that is the
        // edge's job, and this stand-in is not the edge.
        artifactPass: 'v1.k1.4102444800.${'0' * 64}',
      ).toJson(),
    });
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(body)),
      200,
      request: request,
    );
  }
}
