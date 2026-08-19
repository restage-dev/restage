import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart'
    show AssetBundle, ByteData, CachingAssetBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/flow/flow_resolver.dart' show ActiveArmFlowResolver;
import 'package:restage/src/runtime/builtin_catalog_capabilities.dart';
import 'package:restage_shared/restage_shared.dart';

import 'flow_test_support.dart' show screenBlob;

/// General-surface proof slice (restage half): a hand-authored GENERAL flow
/// document resolves through the general render gate and renders end-to-end; the
/// capability cap composes downstream (a general document declaring an action
/// verb with no installed binding fails closed); and the general surface delivers
/// its terminal result to the host untyped but outbound-filtered. (The
/// gate-selection invariant — a typed document is never evaluated permissively —
/// is proven in server_flow_resolver_general_gate_test.dart and
/// general_render_gate_test.dart.)
const int _installed = RestageBuiltInCatalogCapabilities.currentVersion;
const int _refFloor = _installed + 2;

const flowRef = OnboardingFlowRef<Map<String, Object?>>(
  id: 'first_run',
  version: 1,
  minClient: _refFloor,
  surface: Surface.general,
  decodeResult: _decodeMapResult,
);

void main() {
  const baseUrl = 'https://surfaces.example.com';
  const apiKey = 'rs_pk_test_abc123';

  setUp(Restage.debugReset);

  test(
      'a general active document resolves through the general gate AND renders '
      'end-to-end', () async {
    final welcome = screenBlob('Welcome', 'next');
    final events = <RestageEvent>[];
    final controller = RestageFlowController<Map<String, Object?>>(
      flow: flowRef,
      resolver: ServerFlowResolver(
        baseUrl: baseUrl,
        apiKey: apiKey,
        active: true,
        bundle: _bundleFor(
          _generalDoc(screenBytes: welcome),
          welcome,
        ),
        httpClient: _server(
          _envelope(
            // A structural change (a terminal-result expansion) the content-only
            // gate rejects; the general gate accepts it.
            _generalDoc(
              screenBytes: welcome,
              version: 2,
              terminalResult: const {'completed': true, 'extra': 1},
            ),
            welcome,
          ),
        ),
      ),
      actions: null,
      onEvent: events.add,
      onComplete: (_) {},
      onUnavailable: (_) {},
    );
    addTearDown(controller.dispose);

    await controller.load();

    expect(controller.isUnavailable, isFalse);
    expect(controller.currentScreenId, 'welcome');
    // resolvedVersion == 2 proves the ACTIVE (structurally-changed) document was
    // served through the general gate and rendered, not the bundled fallback.
    expect(events.whereType<FlowStarted>().single.resolvedVersion, 2);
  });

  test(
      'the delivery-mode marker survives the resolver freeze '
      '(ResolvedFlow._freezeDocument preserves it)', () {
    // Regression: the resolver freezes its document by rebuilding it
    // field-by-field; the delivery-mode marker must survive so a consumer that
    // reads the resolved document's mode is not misled (a general document must
    // not silently revert to typed). Non-vacuous: fails if the freeze omits
    // deliveryMode.
    final welcome = screenBlob('Welcome', 'next');
    final resolved = ResolvedFlow(
      document: _generalDoc(screenBytes: welcome),
      screenBlobs: {'welcome': welcome},
      cacheHit: false,
    );

    expect(resolved.document.deliveryMode, FlowDeliveryMode.general);
  });

  test(
      'a general document declaring an action verb with no installed binding '
      'fails closed (the capability cap composes downstream)', () async {
    FlowUnavailableError? error;
    final welcome = screenBlob('Welcome', 'request');
    final controller = RestageFlowController<Map<String, Object?>>(
      flow: flowRef,
      // The fake resolver injects the general document directly, isolating the
      // controller's action-contract cap from the resolver's gate.
      resolver: _FakeActiveResolver(_resolved(_generalDocWithAction(welcome))),
      actions: null,
      onEvent: (_) {},
      onComplete: (_) {},
      onUnavailable: (e) => error = e,
    );
    addTearDown(controller.dispose);

    await controller.load();

    expect(controller.isUnavailable, isTrue);
    expect(error?.reason, 'action_contract_mismatch');
  });

  test(
      'a general surface delivers the outbound-FILTERED terminal result to the '
      'host untyped — a non-allowlisted key is dropped (filter authoritative)',
      () async {
    // The untyped host boundary is the identity-decoded (`_decodeMapResult`)
    // terminal result — but it is the outbound-ALLOWLISTED map, never the raw
    // `EndFlowState.result`. Here `outbound.terminalResult` allowlists only
    // `completed`; the raw result also carries `secret`, which must NOT reach the
    // host. This locks "untyped ergonomics = undecoded, still filtered" and
    // proves the general path cannot become an egress bypass.
    Map<String, Object?>? received;
    final welcome = screenBlob('Welcome', 'next');
    final doc = _generalDoc(
      screenBytes: welcome,
      outbound: const FlowOutboundDeclarations(
        terminalResult: FlowOutboundPayloadDeclaration(
          fields: {
            'completed': FlowOutboundField(
              type: FlowDataType.bool,
              ref: EventFlowOutboundRef(key: 'completed'),
            ),
          },
        ),
      ),
      terminalResult: const {'completed': true, 'secret': 'do-not-emit'},
    );
    final resolved = ResolvedFlow(
      document: doc,
      screenBlobs: {'welcome': welcome},
      cacheHit: false,
    );
    final controller = RestageFlowController<Map<String, Object?>>(
      flow: flowRef,
      resolver: _FakeActiveResolver(resolved),
      actions: null,
      onEvent: (_) {},
      onComplete: (result) => received = result,
      onUnavailable: (_) {},
    );
    addTearDown(controller.dispose);

    await controller.load();
    controller.handleEvent('next', const <String, Object?>{});
    await Future<void>.delayed(Duration.zero);

    // Untyped Map (identity decode), filtered to the allowlist — `secret` gone.
    expect(received, {'completed': true});
    expect(received, isNot(contains('secret')));
  });

  test(
      'a general surface never legacy-raw-passes the terminal result — an empty '
      'outbound filters to {} rather than delivering the raw result', () async {
    // legacyTerminalResultPassthrough is a backward-compat flag for pre-outbound
    // TYPED docs (the codec infers it when a doc has no flowState and no
    // outbound). A GENERAL surface must NEVER take the raw-passthrough branch —
    // it always filters through outbound (empty ⇒ {}), so the untyped result
    // stays filtered-not-raw and the allowlist stays uniformly authoritative.
    Map<String, Object?>? received;
    final welcome = screenBlob('Welcome', 'next');
    final doc = FlowDocument(
      flow: 'first_run',
      version: 1,
      schemaVersion: 1,
      minClient: _installed,
      initial: 'welcome',
      legacyTerminalResultPassthrough: true,
      screenArtifacts: {
        'welcome': ScreenArtifact(
          path: 'welcome.rfw',
          version: 1,
          schemaVersion: 1,
          minClient: _installed,
          contentHash: FlowContentHash.compute(welcome),
        ),
      },
      states: const {
        'welcome': ScreenFlowState(
          screen: 'welcome',
          on: {'next': FlowTransition.goto('done')},
        ),
        'done':
            EndFlowState(result: {'completed': true, 'secret': 'do-not-emit'}),
      },
      deliveryMode: FlowDeliveryMode.general,
    );
    final controller = RestageFlowController<Map<String, Object?>>(
      flow: flowRef,
      resolver: _FakeActiveResolver(
        ResolvedFlow(
          document: doc,
          screenBlobs: {'welcome': welcome},
          cacheHit: false,
        ),
      ),
      actions: null,
      onEvent: (_) {},
      onComplete: (result) => received = result,
      onUnavailable: (_) {},
    );
    addTearDown(controller.dispose);

    await controller.load();
    controller.handleEvent('next', const <String, Object?>{});
    await Future<void>.delayed(Duration.zero);

    // Filtered to {} (outbound is empty) — the raw result is NOT delivered.
    expect(received, <String, Object?>{});
  });

  test(
      'a general surface declaring an OTA custom-event name with no installed '
      'handler fails closed (the both-channel cap — the second vocabulary '
      'channel)', () async {
    // The general surface caps BOTH channels: action verbs (via
    // _validateActionContracts, proven above) AND custom-event / host-signal
    // NAMES. An `outbound.customEvents` name the app did not ship a handler for
    // is a capability the OTA document invented — a governing-invariant
    // violation — so the document is rejected at load (fail closed to bundled),
    // never silently dropping signals at runtime.
    FlowUnavailableError? error;
    final welcome = screenBlob('Welcome', 'next');
    final doc = _generalDoc(
      screenBytes: welcome,
      outbound: const FlowOutboundDeclarations(
        customEvents: {'unlockPro': FlowOutboundPayloadDeclaration()},
      ),
    );
    final controller = RestageFlowController<Map<String, Object?>>(
      flow: flowRef,
      resolver: _FakeActiveResolver(
        ResolvedFlow(
          document: doc,
          screenBlobs: {'welcome': welcome},
          cacheHit: false,
        ),
      ),
      actions: null,
      installedSignalNames: const {},
      onEvent: (_) {},
      onComplete: (_) {},
      onUnavailable: (e) => error = e,
    );
    addTearDown(controller.dispose);

    await controller.load();

    expect(controller.isUnavailable, isTrue);
    expect(error?.reason, 'signal_not_installed');
  });

  test(
      'a general surface emits a custom event whose NAME is installed (the cap '
      'permits the composed vocabulary)', () async {
    final events = <RestageEvent>[];
    final welcome = screenBlob('Welcome', 'next');
    final doc = _generalDoc(
      screenBytes: welcome,
      outbound: const FlowOutboundDeclarations(
        customEvents: {'submitAnswer': FlowOutboundPayloadDeclaration()},
      ),
    );
    final controller = RestageFlowController<Map<String, Object?>>(
      flow: flowRef,
      resolver: _FakeActiveResolver(
        ResolvedFlow(
          document: doc,
          screenBlobs: {'welcome': welcome},
          cacheHit: false,
        ),
      ),
      actions: null,
      installedSignalNames: const {'submitAnswer'},
      onEvent: events.add,
      onComplete: (_) {},
      onUnavailable: (_) {},
    );
    addTearDown(controller.dispose);

    await controller.load();
    expect(controller.isUnavailable, isFalse);
    controller.handleEvent('submitAnswer', const <String, Object?>{});
    await Future<void>.delayed(Duration.zero);

    expect(
      events
          .whereType<FlowCustomEvent>()
          .where((e) => e.eventName == 'submitAnswer'),
      hasLength(1),
    );
  });

  test(
      'a TYPED surface is NOT subject to the custom-event-name cap (the cap is '
      'general-surface-only)', () async {
    final events = <RestageEvent>[];
    final welcome = screenBlob('Welcome', 'next');
    // A typed document with a custom-event name and NO installed signal set: the
    // typed path keeps its existing behavior (the dev owns the reviewed handler).
    final doc = _generalDoc(
      screenBytes: welcome,
      deliveryMode: FlowDeliveryMode.typed,
      outbound: const FlowOutboundDeclarations(
        customEvents: {'unlockPro': FlowOutboundPayloadDeclaration()},
      ),
    );
    final controller = RestageFlowController<Map<String, Object?>>(
      flow: flowRef,
      resolver: _FakeActiveResolver(
        ResolvedFlow(
          document: doc,
          screenBlobs: {'welcome': welcome},
          cacheHit: false,
        ),
      ),
      actions: null,
      installedSignalNames: const {},
      onEvent: events.add,
      onComplete: (_) {},
      onUnavailable: (_) {},
    );
    addTearDown(controller.dispose);

    await controller.load();
    expect(controller.isUnavailable, isFalse);
    controller.handleEvent('unlockPro', const <String, Object?>{});
    await Future<void>.delayed(Duration.zero);

    expect(
      events
          .whereType<FlowCustomEvent>()
          .where((e) => e.eventName == 'unlockPro'),
      hasLength(1),
    );
  });
}

Map<String, Object?> _decodeMapResult(Map<String, Object?> result) => result;

FlowDocument _generalDoc({
  required Uint8List screenBytes,
  int version = 1,
  Map<String, Object?> terminalResult = const {'completed': true},
  FlowOutboundDeclarations outbound = const FlowOutboundDeclarations(),
  FlowDeliveryMode deliveryMode = FlowDeliveryMode.general,
}) {
  return FlowDocument(
    flow: 'first_run',
    version: version,
    schemaVersion: 1,
    minClient: _installed,
    initial: 'welcome',
    outbound: outbound,
    screenArtifacts: {
      'welcome': ScreenArtifact(
        path: 'welcome.rfw',
        version: 1,
        schemaVersion: 1,
        minClient: _installed,
        contentHash: FlowContentHash.compute(screenBytes),
      ),
    },
    states: {
      'welcome': const ScreenFlowState(
        screen: 'welcome',
        on: {'next': FlowTransition.goto('done')},
      ),
      'done': EndFlowState(result: terminalResult),
    },
    deliveryMode: deliveryMode,
  );
}

FlowDocument _generalDocWithAction(Uint8List screenBytes) {
  return FlowDocument(
    flow: 'first_run',
    version: 1,
    schemaVersion: 1,
    minClient: _installed,
    initial: 'welcome',
    actions: const {
      'requestNotifications': FlowActionContract(
        actionName: 'requestNotifications',
        contractVersion: 1,
        argsSchema: FlowActionSchema.object({}),
        resultSchema: FlowActionSchema.bool(),
        minClient: 1,
        idempotent: false,
      ),
    },
    screenArtifacts: {
      'welcome': ScreenArtifact(
        path: 'welcome.rfw',
        version: 1,
        schemaVersion: 1,
        minClient: _installed,
        contentHash: FlowContentHash.compute(screenBytes),
      ),
    },
    states: const {
      'welcome': ScreenFlowState(
        screen: 'welcome',
        on: {
          'request': ActionFlowTransition(
            action: 'requestNotifications',
            resultPredicate: BoolEqualsActionResultPredicate(value: true),
            target: 'done',
          ),
        },
      ),
      'done': EndFlowState(result: {'completed': true}),
    },
    deliveryMode: FlowDeliveryMode.general,
  );
}

ResolvedFlow _resolved(FlowDocument document) {
  return ResolvedFlow(
    document: document,
    screenBlobs: {'welcome': screenBlob('Welcome', 'request')},
    contentHash: FlowContentHash.compute(
      FlowDocumentCodec.encodeCanonicalJson(document),
    ),
    cacheHit: false,
  );
}

Uint8List _envelope(FlowDocument document, Uint8List screenBytes) {
  final payload = FlowSurfacePayload(
    flowDocument: document,
    screenBlobs: {'welcome': screenBytes},
  );
  final surface = SurfaceDocument(
    surfaceType: Surface.general,
    surfaceSlug: document.flow,
    version: document.version,
    minClient: document.minClient,
    payload: payload,
    publishedAt: DateTime.utc(2026),
  );
  return SurfaceDocumentCodec.encode(surface);
}

AssetBundle _bundleFor(FlowDocument document, Uint8List screenBytes) {
  return _TestBundle({
    'assets/general/flows/first_run.flow.json':
        Uint8List.fromList(FlowDocumentCodec.encodeCanonicalJson(document)),
    'assets/general/screens/welcome.rfw': screenBytes,
  });
}

MockClient _server(Uint8List envelope) {
  return MockClient((request) async {
    return http.Response(jsonEncode({'envelope': base64Encode(envelope)}), 200);
  });
}

final class _FakeActiveResolver implements FlowResolver, ActiveArmFlowResolver {
  const _FakeActiveResolver(this._flow);

  final ResolvedFlow _flow;

  @override
  bool get activeArmEnabled => true;

  @override
  Future<ResolvedFlow> resolveActiveRoot<R>(OnboardingFlowRef<R> flow) async =>
      _flow;

  @override
  Future<ResolvedFlow> resolve<R>(OnboardingFlowRef<R> flow) async => _flow;
}

final class _TestBundle extends CachingAssetBundle {
  _TestBundle(this._assets);

  final Map<String, Uint8List> _assets;

  @override
  Future<ByteData> load(String key) async {
    final bytes = _assets[key];
    if (bytes == null) {
      throw FlutterError('Unable to load asset: $key');
    }
    return ByteData.view(Uint8List.fromList(bytes).buffer);
  }
}
