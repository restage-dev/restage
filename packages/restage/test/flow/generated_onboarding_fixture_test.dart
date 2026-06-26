import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
// The single event-arg normalization funnel both render paths share. Imported
// directly so the dual-path consistency test can assert the two render paths'
// event-arg shapes converge here (it is an internal runtime detail, not part of
// the public surface).
import 'package:restage/src/flow/flow_runtime_support.dart'
    show normalizeEventArgs;
import 'package:restage_shared/restage_shared.dart'
    show
        EndFlowState,
        FlowContentHash,
        FlowDocument,
        FlowDocumentCodec,
        GotoFlowTransition,
        ScreenArtifact,
        ScreenFlowState,
        kCapturedEventValueKey;
import 'package:rfw/formats.dart';

void main() {
  setUp(Restage.debugReset);

  testWidgets('generated first_run fixture traverses to typed completion',
      (tester) async {
    FirstRunResult? completed;
    final globalEvents = <RestageEvent>[];
    final sub = Restage.events.listen(globalEvents.add);
    addTearDown(sub.cancel);
    final document = _generatedDocument();
    final assets = _generatedAssets();

    _expectDescriptorMatchesDocument(document);
    _expectBlobHashesMatchDocument(document, assets);

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageOnboarding<FirstRunResult>(
        flow: FirstRunFlowDescriptor.ref,
        resolver: AssetFlowResolver(
          bundle: _GeneratedFixtureBundle(assets),
        ),
        actions: _generatedActions(),
        unavailable: FlowUnavailablePolicy.fallback(
          builder: fallbackBuilder,
        ),
        onComplete: (result) => completed = result,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('WelcomeScreen'), findsOneWidget);
    expect(find.text('AnalyticsTap'), findsOneWidget);

    await tester.tap(find.text('AnalyticsTap'));
    await tester.pumpAndSettle();

    final customEvent = globalEvents.whereType<FlowCustomEvent>().single;
    expect(customEvent.eventName, 'analyticsTap');
    expect(customEvent.fields, {'ctaId': 'primary'});

    await tester.tap(find.text('WelcomeScreen'));
    await tester.pumpAndSettle();

    expect(find.text('PermissionsScreen'), findsOneWidget);

    await tester.tap(find.text('PermissionsScreen'));
    await tester.pumpAndSettle();

    expect(find.text('ReadyScreen'), findsOneWidget);

    await tester.tap(find.text('ReadyScreen'));
    await tester.pumpAndSettle();

    expect(completed, const FirstRunResult(completed: true));
    expect(globalEvents.whereType<FlowUnavailable>(), isEmpty);
    expect(globalEvents.whereType<PaywallCustomEvent>(), isEmpty);
  });

  testWidgets(
      'a scalar onboardingEvent value is captured end-to-end into flow-state',
      (tester) async {
    // The full producer->consumer chain a `.capture()` relies on: a rendered
    // screen fires a scalar event carrying its value under the reserved key,
    // and the flow captures it into flow-state (no injected payload).
    int? capturedResult;
    final globalEvents = <RestageEvent>[];
    final sub = Restage.events.listen(globalEvents.add);
    addTearDown(sub.cancel);

    final fixture = _buildCaptureFixture();

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageOnboarding<int>(
        flow: fixture.ref,
        resolver:
            AssetFlowResolver(bundle: _GeneratedFixtureBundle(fixture.assets)),
        unavailable: FlowUnavailablePolicy.hide(),
        onComplete: (result) => capturedResult = result,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('RateScreen'), findsOneWidget);

    await tester.tap(find.text('RateScreen'));
    await tester.pumpAndSettle();

    // The rendered screen emitted `event "submit" { value: 42 }`; capture read
    // the reserved value key into flow-state 'captured', which the terminal
    // result projected — proving the screen actually delivers the captured
    // field (the gap that a hand-injected payload would have hidden).
    final unavailable = globalEvents.whereType<FlowUnavailable>();
    expect(
      unavailable,
      isEmpty,
      reason: unavailable.map((u) => u.reason).join(','),
    );
    expect(capturedResult, 42);
  });

  testWidgets(
      'a scalar authored-event value is captured identically via local-Dart '
      'composition as via the RFW blob', (tester) async {
    // The dual-path consistency guard. The test above lands the captured value
    // by rendering the screen blob (which emits the value already wrapped under
    // the reserved key) and tapping it — the RFW render path. This drives the
    // SAME capture flow through the *other* render path: a local-Dart widget
    // firing the authored-event helper, whose dispatcher delivers the raw scalar
    // value. Both funnel through normalizeEventArgs before the controller, so a
    // `.capture()` must resolve to the identical flow-state value (42) — the
    // exact equivalence that failed closed on the local path until the
    // normalization point was shared.
    final fixture = _buildCaptureFixture();
    int? localCaptured;
    String? unavailableReason;
    const submitEvent = OnboardingEvent<int>('submit');

    final controller = RestageFlowController<int>(
      flow: fixture.ref,
      resolver:
          AssetFlowResolver(bundle: _GeneratedFixtureBundle(fixture.assets)),
      actions: null,
      onEvent: (_) {},
      onComplete: (result) => localCaptured = result,
      onUnavailable: (error) => unavailableReason = error.reason,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageOnboardingEventDispatcher(
        // The exact wiring RestageOnboarding applies for a local-Dart
        // composition: normalize the authored value through the shared funnel,
        // then dispatch to the controller's current screen.
        onEvent: (id, value) =>
            controller.handleEvent(id, normalizeEventArgs(value)),
        child: Builder(
          builder: (context) => GestureDetector(
            onTap: onboardingEvent(submitEvent, 42),
            child: const Text('LocalRate'),
          ),
        ),
      ),
    ));

    // Drive the load the same way RestageOnboarding does — kicked off, then
    // settled by pumping — rather than awaiting it directly (a direct await
    // would freeze under the test's fake-async clock).
    unawaited(controller.load());
    await tester.pumpAndSettle();
    expect(unavailableReason, isNull);
    expect(controller.currentScreenId, 'rate');

    await tester.tap(find.text('LocalRate'));
    await tester.pumpAndSettle();

    // Identical to the RFW render path's `expect(capturedResult, 42)` above.
    expect(localCaptured, 42);
  });

  test('normalizeEventArgs converges both render paths\' event-arg shapes', () {
    // The by-construction structural guard behind the dual-path equivalence: the
    // single funnel both render surfaces pass through. The RFW blob emits the
    // value already wrapped ({value: v}); the local-Dart dispatcher passes the
    // raw scalar. Both must reduce to the SAME reserved-key shape so a
    // `.capture()` reads one value on either path.
    expect(
      normalizeEventArgs(42),
      normalizeEventArgs(const {kCapturedEventValueKey: 42}),
    );
    expect(normalizeEventArgs(42), const {kCapturedEventValueKey: 42});
    // A map of named fields passes through untouched.
    expect(
      normalizeEventArgs(const {'ctaId': 'primary'}),
      const {'ctaId': 'primary'},
    );
    // A value-less event normalizes to an empty args map.
    expect(normalizeEventArgs(null), const <String, Object?>{});
  });

  testWidgets('broken generated fixture emits FlowUnavailable through fallback',
      (tester) async {
    final globalEvents = <RestageEvent>[];
    final sub = Restage.events.listen(globalEvents.add);
    addTearDown(sub.cancel);
    final document = _generatedDocument();

    _expectDescriptorMatchesDocument(document);

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageOnboarding<FirstRunResult>(
        flow: FirstRunFlowDescriptor.ref,
        resolver: AssetFlowResolver(
          bundle: _GeneratedFixtureBundle.missingReadyBlob(),
        ),
        actions: _generatedActions(),
        unavailable: FlowUnavailablePolicy.fallback(
          builder: fallbackBuilder,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('fallback:missing_screen_blob'), findsOneWidget);
    expect(
      globalEvents.whereType<FlowUnavailable>().single.reason,
      'missing_screen_blob',
    );
    expect(globalEvents.whereType<PaywallCustomEvent>(), isEmpty);
  });
}

Widget fallbackBuilder(BuildContext context, FlowUnavailableError error) {
  return Text(
    'fallback:${error.reason}',
    textDirection: TextDirection.ltr,
  );
}

abstract final class FirstRunFlowDescriptor {
  static const ref = OnboardingFlowRef<FirstRunResult>(
    id: 'first_run',
    version: 1,
    minClient: 3,
    decodeResult: _decodeResult,
  );

  static FirstRunResult _decodeResult(Map<String, Object?> result) {
    if (result.length != 1 || !result.containsKey('completed')) {
      throw const FormatException('Unexpected first_run result shape.');
    }
    final completed = result['completed'];
    if (completed is! bool) {
      throw const FormatException('Expected completed to be a bool.');
    }
    return FirstRunResult(completed: completed);
  }
}

final class FirstRunResult {
  const FirstRunResult({required this.completed});

  final bool completed;

  @override
  bool operator ==(Object other) {
    return other is FirstRunResult && other.completed == completed;
  }

  @override
  int get hashCode => completed.hashCode;
}

final class NotificationResult {
  const NotificationResult({required this.granted});

  final bool granted;
}

final class FirstRunActions implements FlowActionRegistry {
  FirstRunActions({
    required FlowActionHandler<void, NotificationResult> requestNotifications,
  }) : flowActionBindings =
            Map<String, FlowActionBinding<dynamic, dynamic>>.unmodifiable({
          'requestNotifications': FlowActionBinding<void, NotificationResult>(
            descriptor: requestNotificationsDescriptor,
            actionName: requestNotificationsDescriptor.actionName,
            contractVersion: requestNotificationsDescriptor.contractVersion,
            argsSchema: requestNotificationsDescriptor.argsSchema,
            resultSchema: requestNotificationsDescriptor.resultSchema,
            minClient: requestNotificationsDescriptor.minClient,
            idempotent: requestNotificationsDescriptor.idempotent,
            handler: requestNotifications,
            decodeArgs: (_) {},
            encodeResult: (value) => {'granted': value.granted},
          ),
        });

  @override
  final Map<String, FlowActionBinding<dynamic, dynamic>> flowActionBindings;

  static final FlowActionDescriptor<void, NotificationResult>
      requestNotificationsDescriptor =
      FlowActionDescriptor<void, NotificationResult>(
    actionName: 'requestNotifications',
    contractVersion: 1,
    argsSchema: const FlowActionSchema.object({}),
    resultSchema: const FlowActionSchema.object({
      'granted': FlowActionSchemaField(
        required: true,
        schema: FlowActionSchema.bool(),
      ),
    }),
    minClient: 3,
    idempotent: false,
  );
}

final class _GeneratedFixtureBundle extends CachingAssetBundle {
  _GeneratedFixtureBundle(Map<String, Uint8List> assets) : _assets = assets;

  factory _GeneratedFixtureBundle.missingReadyBlob() {
    return _GeneratedFixtureBundle(
      _generatedAssets()..remove('assets/onboarding/screens/ready.rfw'),
    );
  }

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

Map<String, Uint8List> _generatedAssets() {
  return {
    'assets/onboarding/flows/first_run.flow.json': Uint8List.fromList(
      utf8.encode(_readSharedFirstRunGolden()),
    ),
    'assets/onboarding/screens/welcome.rfw': _generatedBlob(
      '''
import restage.core;
import restage.material;
import restage.cupertino;

widget OnboardingScreen = Center(
  child: Column(
    mainAxisAlignment: "center",
    children: [
      ElevatedButton(
        onPressed: event "analyticsTap" { ctaId: "primary", secret: "internal" },
        child: Text(text: "AnalyticsTap"),
      ),
      ElevatedButton(onPressed: event "next" {}, child: Text(text: "WelcomeScreen")),
    ],
  ),
);
''',
    ),
    'assets/onboarding/screens/permissions.rfw': _generatedBlob(
      '''
import restage.core;
import restage.material;
import restage.cupertino;

widget OnboardingScreen = Center(child: ElevatedButton(onPressed: event "next" {}, child: Text(text: "PermissionsScreen")));
''',
    ),
    'assets/onboarding/screens/ready.rfw': _generatedBlob(
      '''
import restage.core;
import restage.material;
import restage.cupertino;

widget OnboardingScreen = Center(child: ElevatedButton(onPressed: event "start" {}, child: Text(text: "ReadyScreen")));
''',
    ),
  };
}

Uint8List _generatedBlob(String source) {
  return Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));
}

/// Builds the single capture flow shared by both render-path tests: a screen
/// whose `submit` event carries a scalar value (wrapped under the reserved key,
/// the way the SCREEN codegen emits `onPressed: onboardingEvent(rateEvent, 42)`)
/// and a capturing transition that writes that value into exportable flow-state
/// `captured`, projected by the terminal result. Sharing one fixture is what
/// makes the RFW-blob render path and the local-Dart composition path a true
/// apples-to-apples consistency comparison.
({
  FlowDocument document,
  Map<String, Uint8List> assets,
  OnboardingFlowRef<int> ref,
}) _buildCaptureFixture() {
  final screenBlob = _generatedBlob('''
import restage.core;
import restage.material;
import restage.cupertino;

widget OnboardingScreen = Center(
  child: ElevatedButton(
    onPressed: event "submit" { $kCapturedEventValueKey: 42 },
    child: Text(text: "RateScreen"),
  ),
);
''');

  final document = FlowDocument(
    flow: 'cap_flow',
    version: 1,
    schemaVersion: 1,
    minClient: 3,
    initial: 'rate',
    flowState: const {
      'captured': FlowStateDeclaration(
        type: FlowDataType.int,
        classification: FlowStateClassification.exportable,
      ),
    },
    outbound: const FlowOutboundDeclarations(
      terminalResult: FlowOutboundPayloadDeclaration(
        fields: {
          'captured': FlowOutboundField(
            type: FlowDataType.int,
            ref: StateFlowOutboundRef(key: 'captured'),
          ),
        },
      ),
    ),
    screenArtifacts: {
      'rate': ScreenArtifact(
        path: 'rate.rfw',
        version: 1,
        schemaVersion: 1,
        minClient: 3,
        contentHash: FlowContentHash.compute(screenBlob),
      ),
    },
    states: const {
      'rate': ScreenFlowState(
        screen: 'rate',
        on: {
          'submit': GotoFlowTransition(
            'done',
            stateWrites: {
              'captured': FlowStateWrite(
                type: FlowDataType.int,
                value: EventFlowValueSource(key: kCapturedEventValueKey),
              ),
            },
          ),
        },
      ),
      'done': EndFlowState(result: {}),
    },
  );

  final assets = {
    'assets/onboarding/flows/cap_flow.flow.json': Uint8List.fromList(
      FlowDocumentCodec.encodeCanonicalJson(document),
    ),
    'assets/onboarding/screens/rate.rfw': screenBlob,
  };
  final ref = OnboardingFlowRef<int>(
    id: 'cap_flow',
    version: 1,
    minClient: 3,
    decodeResult: (result) => result['captured']! as int,
  );

  return (document: document, assets: assets, ref: ref);
}

FlowDocument _generatedDocument() {
  return FlowDocumentCodec.decodeJson(_readSharedFirstRunGolden());
}

void _expectDescriptorMatchesDocument(FlowDocument document) {
  expect(FirstRunFlowDescriptor.ref.id, document.flow);
  expect(FirstRunFlowDescriptor.ref.version, document.version);
  expect(FirstRunFlowDescriptor.ref.minClient, document.minClient);
  final action = document.actions['requestNotifications'];
  expect(action?.actionName,
      FirstRunActions.requestNotificationsDescriptor.actionName);
  expect(
    action?.resultSchemaHash,
    FirstRunActions.requestNotificationsDescriptor.resultSchemaHash,
  );
}

FirstRunActions _generatedActions() {
  return FirstRunActions(
    requestNotifications: (_, __) => const NotificationResult(granted: true),
  );
}

void _expectBlobHashesMatchDocument(
  FlowDocument document,
  Map<String, Uint8List> assets,
) {
  for (final entry in document.screenArtifacts.entries) {
    final path = 'assets/onboarding/screens/${entry.value.path}';
    final bytes = assets[path];
    expect(bytes, isNotNull, reason: entry.key);
    expect(
      FlowContentHash.compute(bytes!),
      entry.value.contentHash,
      reason: entry.key,
    );
  }
}

String _readSharedFirstRunGolden() {
  const relativePath =
      'packages/restage_shared/test/flow_document/goldens/first_run.flow.json';
  var directory = Directory.current.absolute;
  while (true) {
    final candidate = File('${directory.path}/$relativePath');
    if (candidate.existsSync()) {
      return candidate.readAsStringSync();
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError(
        'Could not find $relativePath from ${Directory.current}',
      );
    }
    directory = parent;
  }
}
