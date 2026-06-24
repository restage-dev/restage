import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:restage/restage.dart';
import 'package:restage_shared/restage_shared.dart';

import 'onboarding/flows/first_run.dart';

/// Dev-only entrypoint that runs the first-run onboarding flow **server-
/// delivered** — fetched through a [ServerFlowResolver], exactly as a production
/// app would, but backed by an in-app fake surface server so it needs no real
/// backend and no seed.
///
/// This is the local test harness for the server-delivery path: it packages the
/// app's own bundled flow into the surface document a Restage backend would
/// serve, stands up a fake server for it, and points the SDK at that server via
/// `Restage.configure(flowResolver: …)`. The screen rendering, navigation,
/// fail-closed, and analytics wiring are identical to the bundled-asset demo —
/// only the delivery changes. Watch the console for the `[onboarding analytics]`
/// lines as the funnel events fire.
///
/// Run it with `flutter run -t lib/main_server_onboarding_demo.dart`.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final envelope = await buildFirstRunSurfaceEnvelope();
  Restage.configure(
    apiKey: 'rs_pk_demo',
    baseUrl: 'https://fake-surfaces.local',
    flowResolver: ServerFlowResolver(
      baseUrl: 'https://fake-surfaces.local',
      apiKey: 'rs_pk_demo',
      httpClient: FakeSurfaceServer(envelope),
    ),
  );
  runApp(
    MaterialApp(
      title: 'Server-delivered onboarding',
      home: _FirstRunOnboardingHost(
        actions: FirstRunActions(
          // A real app shows the OS notification dialog here and returns the
          // user's choice; this dev harness returns a fixed granted decision so
          // the server-delivered flow renders its full happy path.
          requestNotifications: (_, __) async =>
              const NotificationDecision(granted: true),
        ),
      ),
    ),
  );
}

/// Minimal host for the first-run onboarding flow — renders it through
/// [RestageOnboarding] and fails closed to a plain surface if the flow can't be
/// made available. The host owns only the small amount of app code a flow needs:
/// the notification host action (passed in) and the fail-closed fallback.
class _FirstRunOnboardingHost extends StatelessWidget {
  const _FirstRunOnboardingHost({required this.actions});

  final FirstRunActions actions;

  @override
  Widget build(BuildContext context) {
    return RestageOnboarding<FirstRunResult>(
      flow: FirstRunFlowDescriptor.ref,
      actions: actions,
      loadingBuilder: (context) => const ColoredBox(color: Color(0xFF0E1B33)),
      unavailable: FlowUnavailablePolicy.fallback(
        builder: (context, error) => const ColoredBox(
          color: Color(0xFF0E1B33),
          child: Center(
            child: Text(
              'Let’s get you started',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: Color(0xFFF5F7FB),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Resolves the bundled first-run flow and re-packages it as the surface
/// document envelope a Restage backend would serve for it — the input the fake
/// server hands back.
Future<Uint8List> buildFirstRunSurfaceEnvelope() async {
  final resolved =
      await const AssetFlowResolver().resolve(FirstRunFlowDescriptor.ref);
  final document = resolved.document;
  return SurfaceDocumentCodec.encode(
    SurfaceDocument(
      surfaceType: SurfaceType.onboarding,
      surfaceSlug: document.flow,
      version: document.version,
      minClient: document.minClient,
      payload: FlowSurfacePayload(
        flowDocument: document,
        screenBlobs: resolved.screenBlobs,
      ),
      publishedAt: DateTime.now().toUtc(),
    ),
  );
}

/// An [http.Client] that answers every request with [envelope] wrapped in the
/// SDK serve-route response shape — the in-app stand-in for the backend so the
/// demo needs no network.
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
