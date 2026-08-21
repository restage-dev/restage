import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/flow/flow_resolver.dart' show ActiveArmFlowResolver;
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/formats.dart';

/// Controller-side proof that the active version-pin skip is active-SCOPED (the
/// `_validateResolved(active:)` private param) and that every OTHER retained
/// runtime validity check still runs on the active document. A fake
/// `ActiveArmFlowResolver` injects a chosen `ResolvedFlow`, bypassing the
/// resolver's own gate — so these tests isolate the controller's backstop from
/// the resolver's.
void main() {
  setUp(Restage.debugReset);

  const flowRef = OnboardingFlowRef<Map<String, Object?>>(
    id: 'first_run',
    version: 1,
    minClient: 5,
    surface: Surface.onboarding,
    decodeResult: _decodeMapResult,
  );

  RestageFlowController<Map<String, Object?>> controllerFor(
    FlowResolver resolver, {
    void Function(FlowUnavailableError)? onUnavailable,
  }) {
    return RestageFlowController<Map<String, Object?>>(
      flow: flowRef,
      resolver: resolver,
      actions: null,
      onEvent: (_) {},
      onComplete: (_) {},
      onUnavailable: onUnavailable ?? (_) {},
    );
  }

  test(
      'skip-B is active-scoped: an active-resolved doc whose version != '
      'flow.version RENDERS (the version pin is replaced by the gate upstream)',
      () async {
    final controller = controllerFor(
      _FakeActiveResolver(_resolved(_doc(version: 9))),
    );
    addTearDown(controller.dispose);

    await controller.load();

    // Check B (version pin) is skipped for the active arm; the doc renders.
    expect(controller.currentScreenId, 'welcome');
    expect(controller.isUnavailable, isFalse);
  });

  test('exact resolve still version-pins (check B runs when not active)',
      () async {
    FlowUnavailableError? error;
    final controller = controllerFor(
      _FakeExactResolver(_resolved(_doc(version: 9))),
      onUnavailable: (e) => error = e,
    );
    addTearDown(controller.dispose);

    await controller.load();

    expect(controller.isUnavailable, isTrue);
    expect(error?.reason, 'version_mismatch');
  });

  test(
      'backstop (controller): a gate-bypassing active doc with schemaVersion 2 '
      'is still rejected (retained check C)', () async {
    FlowUnavailableError? error;
    final controller = controllerFor(
      _FakeActiveResolver(_resolved(_doc(schemaVersion: 2))),
      onUnavailable: (e) => error = e,
    );
    addTearDown(controller.dispose);

    await controller.load();

    expect(controller.isUnavailable, isTrue);
    expect(error?.reason, 'unsupported_schema_version');
  });

  test(
      'backstop (controller): an active doc with a per-artifact minClient above '
      'the ref floor is still rejected (retained check F)', () async {
    FlowUnavailableError? error;
    final controller = controllerFor(
      _FakeActiveResolver(_resolved(_doc(artifactMinClient: 99))),
      onUnavailable: (e) => error = e,
    );
    addTearDown(controller.dispose);

    await controller.load();

    expect(controller.isUnavailable, isTrue);
    expect(error?.reason, 'unsupported_min_client');
  });

  test(
      'active-resolved lifecycle events carry resolvedVersion (the rendered '
      'active version), keeping flowVersion as the contract id', () async {
    final events = <RestageEvent>[];
    final controller = RestageFlowController<Map<String, Object?>>(
      flow: flowRef,
      resolver: _FakeActiveResolver(_resolved(_doc(version: 9))),
      actions: null,
      onEvent: events.add,
      onComplete: (_) {},
      onUnavailable: (_) {},
    );
    addTearDown(controller.dispose);

    await controller.load();

    final started = events.whereType<FlowStarted>().single;
    expect(started.flowVersion, 1); // the stable contract version
    expect(started.resolvedVersion, 9); // the rendered active version
    expect(started.toMap()['resolvedVersion'], 9);
  });

  test('exact-resolved lifecycle events omit resolvedVersion', () async {
    final events = <RestageEvent>[];
    final controller = RestageFlowController<Map<String, Object?>>(
      flow: flowRef,
      resolver: _FakeExactResolver(_resolved(_doc())),
      actions: null,
      onEvent: events.add,
      onComplete: (_) {},
      onUnavailable: (_) {},
    );
    addTearDown(controller.dispose);

    await controller.load();

    final started = events.whereType<FlowStarted>().single;
    expect(started.resolvedVersion, isNull);
    expect(started.toMap().containsKey('resolvedVersion'), isFalse);
  });
}

Map<String, Object?> _decodeMapResult(Map<String, Object?> result) => result;

ResolvedFlow _resolved(FlowDocument document) {
  return ResolvedFlow(
    document: document,
    screenBlobs: {'welcome': _welcomeBlob()},
    contentHash: FlowContentHash.compute(
      FlowDocumentCodec.encodeCanonicalJson(document),
    ),
    cacheHit: false,
  );
}

/// A valid RFW screen blob (a single `Text`), so `_decodeScreenBlob` decodes it
/// and its hash matches the document artifact below.
Uint8List _welcomeBlob() {
  return Uint8List.fromList(
    encodeLibraryBlob(
      parseLibraryFile(
        'import restage.core; widget OnboardingScreen = Text(text: "Welcome");',
      ),
    ),
  );
}

FlowDocument _doc({
  int version = 1,
  int schemaVersion = 1,
  int minClient = 0,
  int artifactMinClient = 0,
}) {
  final welcome = _welcomeBlob();
  return FlowDocument(
    flow: 'first_run',
    version: version,
    schemaVersion: schemaVersion,
    minClient: minClient,
    initial: 'welcome',
    actions: const {},
    screenArtifacts: {
      'welcome': ScreenArtifact(
        path: 'welcome.rfw',
        version: 1,
        schemaVersion: 1,
        minClient: artifactMinClient,
        contentHash: FlowContentHash.compute(welcome),
      ),
    },
    states: const {
      'welcome': ScreenFlowState(
        screen: 'welcome',
        on: {'next': FlowTransition.goto('done')},
      ),
      'done': EndFlowState(result: {'completed': true}),
    },
  );
}

/// A fake active-capable resolver: `activeArmEnabled` is true and
/// `resolveActiveRoot` returns a fixed doc (bypassing the real gate), so the
/// controller's retained backstop is isolated from the resolver's.
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

/// A plain (non-active-capable) resolver — the controller routes it through the
/// exact path, so check B runs.
final class _FakeExactResolver implements FlowResolver {
  const _FakeExactResolver(this._flow);

  final ResolvedFlow _flow;

  @override
  Future<ResolvedFlow> resolve<R>(OnboardingFlowRef<R> flow) async => _flow;
}
