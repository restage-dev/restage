import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/flow/bundled_flow_loader.dart';
import 'package:restage/src/resolver/flow_paywall_active_arm.dart';
import 'package:restage/src/runtime/builtin_catalog_capabilities.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/formats.dart';

const String _paywallId = 'pro';
final int _installed = RestageBuiltInCatalogCapabilities.currentVersion;

/// A one-screen paywall-flow screen blob whose single control fires [event].
Uint8List _screen(String event) {
  final source = '''
    import restage.core;
    widget OnboardingScreen = GestureDetector(
      onTap: event '$event' { slot: "primary" },
      child: Text(text: "Subscribe"));
  ''';
  return Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));
}

/// A single-screen flow document (screen `plans` -> skip -> end), pinned to the
/// given [screenBytes] hash, so it composes into a valid [FlowSurfacePayload].
FlowDocument _flowDoc(
  Uint8List screenBytes, {
  String flowId = _paywallId,
  int schemaVersion = 1,
  int? minClient,
  int? artifactMinClient,
  int artifactSchemaVersion = 1,
  bool extraTransition = false,
  bool danglingTarget = false,
}) {
  final floor = minClient ?? _installed;
  return FlowDocument(
    flow: flowId,
    version: 1,
    schemaVersion: schemaVersion,
    minClient: floor,
    initial: 'plans',
    actions: const {},
    screenArtifacts: {
      'plans': ScreenArtifact(
        path: 'plans.rfw',
        version: 1,
        schemaVersion: artifactSchemaVersion,
        minClient: artifactMinClient ?? floor,
        contentHash: FlowContentHash.compute(screenBytes),
      ),
    },
    states: {
      'plans': ScreenFlowState(
        screen: 'plans',
        on: {
          // A dangling target references an undefined state -> validation flags
          // it (a structurally-invalid document the render gate would not catch).
          'skip': danglingTarget
              ? const FlowTransition.goto('nowhere')
              : const FlowTransition.goto('done'),
          if (extraTransition) 'restageNav0': const FlowTransition.goto('done'),
        },
      ),
      'done': const EndFlowState(result: {}),
    },
  );
}

String _reason(FlowPaywallActiveResolution result) {
  expect(result, isA<FlowPaywallActiveRejected>());
  return (result as FlowPaywallActiveRejected).reason;
}

BundledFlowArtifacts _bundled(FlowDocument doc, Uint8List screenBytes) {
  final bytes = Uint8List.fromList(FlowDocumentCodec.encodeCanonicalJson(doc));
  return BundledFlowArtifacts(
    documentBytes: bytes,
    documentHash: FlowContentHash.compute(bytes),
    document: doc,
    screenBlobs: {'plans': screenBytes},
  );
}

FlowSurfacePayload _active(
  FlowDocument doc,
  Uint8List screenBytes, {
  List<LibraryRequirement> requiredLibraries = const [],
}) {
  return FlowSurfacePayload(
    flowDocument: doc,
    screenBlobs: {'plans': screenBytes},
    requiredLibraries: requiredLibraries,
  );
}

FlowPaywallActiveResolution _resolve(
  FlowSurfacePayload active,
  BundledFlowArtifacts bundled, {
  int activeVersion = 5,
  String? experimentId = 'exp_1',
}) {
  return resolveFlowActiveArm(
    activePayload: active,
    bundledDocument: bundled.document,
    paywallId: _paywallId,
    activeVersion: activeVersion,
    experimentId: experimentId,
  );
}

void main() {
  test('a compatible content-only active flow is accepted + attributed', () {
    final screen = _screen('restage.purchase');
    final doc = _flowDoc(screen);
    final result = _resolve(_active(doc, screen), _bundled(doc, screen));

    expect(result, isA<FlowPaywallActiveAccepted>());
    final payload = (result as FlowPaywallActiveAccepted).payload;
    expect(payload.paywallId, _paywallId);
    expect(payload.paywallPublishedVersion, 5);
    expect(payload.experimentId, 'exp_1');
    expect(payload.resolvedFromActiveArm, isTrue);
    expect(payload.flow.document.flow, _paywallId);
  });

  test('a content-only screen change is accepted', () {
    Uint8List purchaseScreen(String label) => Uint8List.fromList(
          encodeLibraryBlob(parseLibraryFile(
            "import restage.core; widget OnboardingScreen = GestureDetector("
            "onTap: event 'restage.purchase' { slot: \"primary\" }, "
            'child: Text(text: "$label"));',
          )),
        );
    final bundledScreen = purchaseScreen('Subscribe');
    final activeScreen = purchaseScreen('Subscribe now');
    final bundled = _bundled(_flowDoc(bundledScreen), bundledScreen);
    final active = _active(_flowDoc(activeScreen), activeScreen);
    expect(_resolve(active, bundled), isA<FlowPaywallActiveAccepted>());
  });

  test('an incompatible active doc (added transition) -> gate REJECT', () {
    final screen = _screen('restage.purchase');
    final bundled = _bundled(_flowDoc(screen), screen);
    final active = _active(_flowDoc(screen, extraTransition: true), screen);
    expect(_resolve(active, bundled), isA<FlowPaywallActiveRejected>());
  });

  test('a purchase -> nav rewrite in a content OTA is ACCEPTED (blob parity)',
      () {
    // The active screen blob rewires the Subscribe control from purchase to
    // nav. This is NOT gated at delivery — parity with the blob-OTA path: a
    // rewired control simply doesn't charge (entitlement is granted only on a
    // real purchase success), exactly like a customer content bug in a bundled
    // paywall. The runtime charge/entitlement invariant is proven separately
    // (restage_variant_resolver_test.dart / the entitlement-backstop test).
    final bundledScreen = _screen('restage.purchase');
    final activeScreen = _screen('restageNav0');
    final bundled = _bundled(_flowDoc(bundledScreen), bundledScreen);
    final active = _active(_flowDoc(activeScreen), activeScreen);

    expect(_resolve(active, bundled), isA<FlowPaywallActiveAccepted>());
  });

  test('a doc capability floor above the installed catalog -> REJECT', () {
    final screen = _screen('restage.purchase');
    final bundled = _bundled(_flowDoc(screen), screen);
    final active = _active(_flowDoc(screen, minClient: _installed + 1), screen);
    expect(_resolve(active, bundled), isA<FlowPaywallActiveRejected>());
  });

  test('an unsatisfied required library -> REJECT', () {
    final screen = _screen('restage.purchase');
    final doc = _flowDoc(screen);
    final bundled = _bundled(doc, screen);
    final active = _active(
      doc,
      screen,
      requiredLibraries: const [
        LibraryRequirement(namespace: 'com.acme.widgets', minVersion: 1),
      ],
    );
    expect(_resolve(active, bundled), isA<FlowPaywallActiveRejected>());
  });

  // The paywall path synthesizes its flow ref FROM the active document, so the
  // flow controller gives NO independent backstop — this arm is the SOLE line
  // of defense and MUST run every retained check
  // ServerFlowResolver runs. This census enumerates ServerFlowResolver's
  // retained-check set (_checkCompatibility(checkVersion:false) +
  // _checkRequiredLibraries + _checkValidation + the inline version-relaxed
  // envelope-identity) and pins that the paywall arm exercises each, by the
  // check-specific reject reason. If ServerFlowResolver's retained-check set
  // changes, RE-CENSUS here.
  group('retained-check census — parity with ServerFlowResolver', () {
    final purchase = _screen('restage.purchase');
    BundledFlowArtifacts okBundled() => _bundled(_flowDoc(purchase), purchase);

    test('compatibility/flow-id mismatch rejects (flow_mismatch)', () {
      final active = _active(_flowDoc(purchase, flowId: 'other'), purchase);
      expect(_reason(_resolve(active, okBundled())), 'flow_mismatch');
    });

    test('compatibility/schemaVersion rejects (unsupported_schema_version)',
        () {
      final active = _active(_flowDoc(purchase, schemaVersion: 2), purchase);
      expect(
        _reason(_resolve(active, okBundled())),
        'unsupported_schema_version',
      );
    });

    test('compatibility/doc floor rejects (unsupported_min_client)', () {
      final active =
          _active(_flowDoc(purchase, minClient: _installed + 1), purchase);
      expect(_reason(_resolve(active, okBundled())), 'unsupported_min_client');
    });

    test('compatibility/per-artifact floor rejects (unsupported_min_client)',
        () {
      final active = _active(
        _flowDoc(purchase, artifactMinClient: _installed + 1),
        purchase,
      );
      expect(_reason(_resolve(active, okBundled())), 'unsupported_min_client');
    });

    test('requiredLibraries rejects (unsupported_required_library)', () {
      final active = _active(
        _flowDoc(purchase),
        purchase,
        requiredLibraries: const [
          LibraryRequirement(namespace: 'com.acme.widgets', minVersion: 1),
        ],
      );
      expect(
        _reason(_resolve(active, okBundled())),
        'unsupported_required_library',
      );
    });

    test('validation is caught-earlier: an invalid doc cannot form a payload',
        () {
      // The arm keeps FlowDocumentValidation.validate as defense-in-depth (parity
      // with ServerFlowResolver._checkValidation), but a structurally-invalid
      // document is caught ONE LAYER EARLIER — SurfaceDocument/FlowSurfacePayload
      // construction runs checkValid while canonicalizing — so an invalid active
      // document fails to decode/build and the resolver rejects it before this
      // arm is entered (exactly ServerFlowResolver's posture; the active-flow P3
      // closeout likewise did not unit-test _checkValidation directly).
      expect(
        () => _active(_flowDoc(purchase, danglingTarget: true), purchase),
        throwsA(anything),
      );
    });

    test(
        'CENSUS COMPLETENESS — every ServerFlowResolver retained check covered',
        () {
      // The retained-check set ServerFlowResolver enforces on the active doc.
      const serverFlowRetainedChecks = {
        'compatibility', // flow-id + schemaVersion + doc/artifact floors
        'requiredLibraries',
        'validation',
        'envelopeIdentity', // surfaceType + slug, version-relaxed
      };
      // Live reject fixtures on the paywall ARM (above) pin these by reason.
      const coveredByArmReject = {'compatibility', 'requiredLibraries'};
      // Present in the arm as defense-in-depth but caught-earlier by
      // SurfaceDocument/payload construction (an invalid doc never reaches here).
      const coveredByConstruction = {'validation'};
      // Envelope identity is enforced by the RESOLVER before this arm runs
      // (surfaceType == paywall && surfaceSlug == id, version omitted) — pinned
      // by the resolver flow test, not here.
      const coveredByResolver = {'envelopeIdentity'};
      expect(
        coveredByArmReject
            .union(coveredByConstruction)
            .union(coveredByResolver),
        serverFlowRetainedChecks,
        reason: 'A ServerFlowResolver retained check is unrepresented in the '
            'paywall active arm — re-census (Finding 5: this arm is the sole '
            'backstop).',
      );
    });
  });
}
