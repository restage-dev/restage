import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/analytics/analytics_event_mapper.dart';
// The installed built-in catalog content version (the resolver's capability
// ceiling) is internal; this proof reaches it via the src path.
import 'package:restage/src/runtime/builtin_catalog_capabilities.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/formats.dart';

import 'flow_test_support.dart';

/// The renderable built-in catalog floor: a baseline proof flow installs at the
/// SDK's current built-in catalog version (distinct from the host-action
/// contract `minClient`, which is the separate action-capability axis).
const int _renderableMinClient =
    RestageBuiltInCatalogCapabilities.currentVersion;

/// The host's compiled flow-ref floor for this proof. Pinned at or above the
/// installed catalog version so a valid document at the installed version
/// renders. Derived from the installed version so it survives catalog version
/// bumps. (Distinct from the host-action contract `minClient` axis, which the
/// action contracts below pin independently.)
const int _refFloorMinClient = _renderableMinClient + 2;

/// End-to-end proof slice for Phase 4: a SERVER-delivered onboarding flow
/// (fetched through a real [ServerFlowResolver] from a fake surface server)
/// fires the onboarding analytics events on the public `Restage.events` stream,
/// and those events map to the blessed onboarding analytics envelope.
///
/// The controller's `onEvent` is wired to `Restage.fireEvent` — the same path
/// `RestageOnboarding` uses — so the assertions exercise the public stream, not
/// a private capture. Per-branch emission correctness is covered exhaustively in
/// `onboarding_events_test.dart`; this proves the delivery + stream integration.
void main() {
  const baseUrl = 'https://surfaces.example.com';
  const apiKey = 'rs_pk_test_proof';
  const appContext = AnalyticsAppContext(
    platform: 'ios',
    locale: 'en_US',
    sdkVersion: '1.0.0',
  );

  setUp(Restage.debugReset);

  RestageFlowController<_ProofResult> serverController(
    Uint8List envelope, {
    FlowActionRegistry? actions,
    required void Function(RestageEvent) onEvent,
  }) {
    final controller = RestageFlowController<_ProofResult>(
      flow: _proofRef,
      resolver: ServerFlowResolver(
        baseUrl: baseUrl,
        apiKey: apiKey,
        httpClient: _server(envelope),
      ),
      actions: actions,
      onEvent: onEvent,
      onComplete: (_) {},
      onUnavailable: (_) {},
    );
    addTearDown(controller.dispose);
    return controller;
  }

  test(
      'a server-delivered flow fires flow_started + step + permission through '
      'Restage.events, mapping to the onboarding envelope', () async {
    final events = <RestageEvent>[];
    final sub = Restage.events.listen(events.add);
    addTearDown(sub.cancel);

    final controller = serverController(
      _permissionEnvelope(),
      actions: _permissionRegistry(granted: true),
      onEvent: Restage.fireEvent,
    );

    await controller.load();
    await drainFlowTasks();

    // flow_started precedes the first impression; the initial screen's
    // step-viewed rode the server-delivered flow onto the public stream.
    expect(events.whereType<FlowStarted>(), hasLength(1));
    final firstSteps = events.whereType<OnboardingStepViewed>().toList();
    expect(firstSteps.single.screenId, 'welcome');
    expect(firstSteps.single.stepIndex, 0);
    expect(firstSteps.single.stepCount, 2);

    // Run the permission host action; granted advances to the second screen.
    controller.handleEvent('grant', null);
    await drainFlowTasks();

    final perms = events.whereType<OnboardingPermissionResponse>().toList();
    expect(perms, hasLength(1));
    expect(perms.single.permission, 'requestNotifications');
    expect(perms.single.granted, isTrue);
    expect(
      events.whereType<OnboardingStepViewed>().map((e) => e.screenId).toList(),
      ['welcome', 'ready'],
    );

    // The server-delivered typed event maps to the blessed onboarding envelope.
    final envelope = mapRestageEventToEnvelope(
      firstSteps.single,
      eventId: 'evt-1',
      anonymousId: 'anon-1',
      sessionId: 'sess-1',
      appContext: appContext,
      now: DateTime.utc(2026),
    );
    expect(envelope.surface, AnalyticsSurface.onboarding);
    expect(envelope.surfaceId, 'proof');
    expect(envelope.surfaceVersion, '1');
    expect(envelope.properties, {
      'screenId': 'welcome',
      'stepIndex': 0,
      'stepCount': 2,
    });
  });

  test(
      'a server-delivered flow fires onboarding_skipped through Restage.events',
      () async {
    final events = <RestageEvent>[];
    final sub = Restage.events.listen(events.add);
    addTearDown(sub.cancel);

    final controller = serverController(
      _skipEnvelope(),
      onEvent: Restage.fireEvent,
    );

    await controller.load();
    await drainFlowTasks();
    controller.skip();
    await drainFlowTasks();

    final skips = events.whereType<OnboardingSkipped>().toList();
    expect(skips, hasLength(1));
    expect(skips.single.atScreenId, 'welcome');
    expect(skips.single.stepIndex, 0);
    // The host still receives the declared skip custom event (additive).
    expect(
      events.whereType<FlowCustomEvent>().where((e) => e.eventName == 'skip'),
      hasLength(1),
    );
  });
}

const _proofRef = OnboardingFlowRef<_ProofResult>(
  id: 'proof',
  version: 1,
  minClient: _refFloorMinClient,
  decodeResult: _decodeProofResult,
);

_ProofResult _decodeProofResult(Map<String, Object?> result) =>
    const _ProofResult();

final class _ProofResult {
  const _ProofResult();
}

const _grantedResultSchema = FlowActionSchema.object({
  'granted': FlowActionSchemaField(
    required: true,
    schema: FlowActionSchema.bool(),
  ),
});

final class _PermissionResult {
  const _PermissionResult({required this.granted});

  final bool granted;
}

FlowActionRegistry _permissionRegistry({required bool granted}) {
  return TestActionRegistry({
    'requestNotifications': FlowActionBinding<void, _PermissionResult>(
      descriptor: const FlowActionDescriptor<void, _PermissionResult>(
        actionName: 'requestNotifications',
        contractVersion: 1,
        argsSchema: FlowActionSchema.object({}),
        resultSchema: _grantedResultSchema,
        minClient: 3,
        idempotent: false,
      ),
      actionName: 'requestNotifications',
      contractVersion: 1,
      argsSchema: const FlowActionSchema.object({}),
      resultSchema: _grantedResultSchema,
      minClient: 3,
      idempotent: false,
      handler: (_, __) => _PermissionResult(granted: granted),
      decodeArgs: (_) {},
      encodeResult: (result) => {'granted': result.granted},
    ),
  });
}

/// welcome --(requestNotifications {granted})--> ready --> done.
Uint8List _permissionEnvelope() {
  final welcome = _blob('welcome');
  final ready = _blob('ready');
  final document = FlowDocument(
    flow: 'proof',
    version: 1,
    schemaVersion: 1,
    minClient: _renderableMinClient,
    initial: 'welcome',
    actions: {
      'requestNotifications': const FlowActionContract(
        actionName: 'requestNotifications',
        contractVersion: 1,
        argsSchema: FlowActionSchema.object({}),
        resultSchema: _grantedResultSchema,
        minClient: 3,
        idempotent: false,
      ),
    },
    legacyTerminalResultPassthrough: true,
    screenArtifacts: {
      'welcome': _artifact(welcome),
      'ready': _artifact(ready),
    },
    states: const {
      'welcome': ScreenFlowState(
        screen: 'welcome',
        on: {
          'grant': ActionFlowTransition(
            action: 'requestNotifications',
            resultPredicate: ObjectBoolFieldEqualsActionResultPredicate(
              field: 'granted',
              value: true,
            ),
            target: 'ready',
          ),
        },
      ),
      'ready': ScreenFlowState(
        screen: 'ready',
        on: {'start': FlowTransition.goto('done')},
      ),
      'done': EndFlowState(result: {'completed': true}),
    },
  );
  return _encode(document, {'welcome': welcome, 'ready': ready});
}

/// welcome (declares a `skip` custom event) --(next)--> ready --> done.
Uint8List _skipEnvelope() {
  final welcome = _blob('welcome');
  final ready = _blob('ready');
  final document = FlowDocument(
    flow: 'proof',
    version: 1,
    schemaVersion: 1,
    minClient: _renderableMinClient,
    initial: 'welcome',
    actions: const {},
    outbound: const FlowOutboundDeclarations(
      customEvents: {'skip': FlowOutboundPayloadDeclaration()},
    ),
    screenArtifacts: {
      'welcome': _artifact(welcome),
      'ready': _artifact(ready),
    },
    states: const {
      'welcome': ScreenFlowState(
        screen: 'welcome',
        on: {'next': FlowTransition.goto('ready')},
      ),
      'ready': ScreenFlowState(
        screen: 'ready',
        on: {'start': FlowTransition.goto('done')},
      ),
      'done': EndFlowState(result: {'completed': true}),
    },
  );
  return _encode(document, {'welcome': welcome, 'ready': ready});
}

ScreenArtifact _artifact(Uint8List blob) => ScreenArtifact(
      path: 'screen.rfw',
      version: 1,
      schemaVersion: 1,
      minClient: _renderableMinClient,
      contentHash: FlowContentHash.compute(blob),
    );

Uint8List _encode(FlowDocument document, Map<String, Uint8List> blobs) {
  final payload =
      FlowSurfacePayload(flowDocument: document, screenBlobs: blobs);
  return SurfaceDocumentCodec.encode(
    SurfaceDocument(
      surfaceType: SurfaceType.onboarding,
      surfaceSlug: document.flow,
      version: document.version,
      minClient: document.minClient,
      payload: payload,
      publishedAt: DateTime.utc(2026),
    ),
  );
}

Uint8List _blob(String label) {
  final source = '''
import restage.core;
widget OnboardingScreen = Text(text: "$label");
''';
  return Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));
}

MockClient _server(Uint8List envelope) {
  return MockClient(
    (_) async => http.Response(
      jsonEncode({'envelope': base64Encode(envelope)}),
      200,
    ),
  );
}
