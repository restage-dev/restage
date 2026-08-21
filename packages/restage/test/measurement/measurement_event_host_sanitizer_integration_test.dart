import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_shared/restage_shared.dart';

import '../flow/flow_test_support.dart' show StaticFlowResolver;
import '../surface_screen/surface_screen_test_support.dart';

const _routeKey = '__restage_measurement_route_v1';
const _reservedPrefix = '__restage_measurement_';
const _carrier =
    'mrv1.ZWRnZS5jaGVja291dC1yb290.AAECAwQFBgcICQoLDA0ODxAREhMUFRYX';

const _flowRef = SurfaceFlowRef<Map<String, Object?>>(
  id: 'measurement_host_sanitizer',
  version: 1,
  minClient: 3,
  surface: Surface.onboarding,
  decodeResult: _decodeFlowResult,
);

Map<String, Object?> _decodeFlowResult(Map<String, Object?> value) =>
    Map<String, Object?>.unmodifiable(value);

void main() {
  setUp(Restage.debugReset);

  testWidgets(
    'standalone strict schemas and generated typed callbacks receive only '
    'business arguments while Measurement is disabled',
    (tester) async {
      Restage.configure(apiKey: 'rs_pk_test', analyticsEnabled: false);
      final decoded = <String, Map<String, Object?>>{};
      final callbacks = <String>[];
      final fixture = stringScreenFixture(
        text: 'unused fixture text',
        schema: SurfaceScreenEventSchema(
          events: <SurfaceScreenEvent>[
            SurfaceScreenEvent(
              id: 'none',
              arguments: const SurfaceScreenEventNoArguments(),
            ),
            SurfaceScreenEvent(
              id: 'value',
              arguments: const SurfaceScreenEventValueArguments(
                SurfaceScreenEventScalarShapeV1(
                  SurfaceScreenEventScalarKind.string,
                ),
              ),
            ),
            SurfaceScreenEvent(
              id: 'object',
              arguments: SurfaceScreenEventObjectArguments(
                const SurfaceScreenEventMapShapeV1(
                  SurfaceScreenEventScalarShapeV1(
                    SurfaceScreenEventScalarKind.jsonValue,
                  ),
                ),
              ),
            ),
          ],
        ),
        blob: rfwSourceBlob(_standaloneSource()),
        decoder: (name, arguments) {
          decoded[name] = Map<String, Object?>.from(arguments);
          return name;
        },
      );

      await tester.pumpWidget(
        _screenHost(fixture: fixture, onEvent: callbacks.add),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('no arguments'));
      await tester.tap(find.text('scalar value'));
      await tester.tap(find.text('object value'));
      await tester.pumpAndSettle();

      expect(callbacks, <String>['none', 'value', 'object']);
      expect(decoded['none'], isEmpty);
      expect(decoded['value'], <String, Object?>{'value': 'seven'});
      expect(decoded['object'], <String, Object?>{
        'cta': 'primary',
        'nested': <String, Object?>{_routeKey: 'top-level-only business data'},
      });
      _expectNoReservedTopLevelKey(decoded['none']!);
      _expectNoReservedTopLevelKey(decoded['value']!);
      _expectNoReservedTopLevelKey(decoded['object']!);
    },
  );

  testWidgets(
    'malformed future and multiple reserved values leave a valid standalone '
    'business event deliverable',
    (tester) async {
      final decoded = <String, Map<String, Object?>>{};
      final fixture = stringScreenFixture(
        text: 'unused fixture text',
        schema: SurfaceScreenEventSchema(
          events: <SurfaceScreenEvent>[
            for (final name in <String>['malformed', 'future', 'multiple'])
              SurfaceScreenEvent(
                id: name,
                arguments: SurfaceScreenEventObjectArguments(
                  const SurfaceScreenEventMapShapeV1(
                    SurfaceScreenEventScalarShapeV1(
                      SurfaceScreenEventScalarKind.string,
                    ),
                  ),
                ),
              ),
          ],
        ),
        blob: rfwSourceBlob(_standaloneInvalidCarrierSource()),
        decoder: (name, arguments) {
          decoded[name] = Map<String, Object?>.from(arguments);
          return name;
        },
      );

      await tester.pumpWidget(_screenHost(fixture: fixture, onEvent: (_) {}));
      await tester.pumpAndSettle();
      for (final label in <String>['malformed', 'future', 'multiple']) {
        expect(find.text(label), findsOneWidget);
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
      }

      expect(decoded, <String, Map<String, Object?>>{
        'malformed': <String, Object?>{'business': 'malformed'},
        'future': <String, Object?>{'business': 'future'},
        'multiple': <String, Object?>{'business': 'multiple'},
      });
      for (final value in decoded.values) {
        _expectNoReservedTopLevelKey(value);
      }
      expect(find.textContaining('fallback:'), findsNothing);
    },
  );

  testWidgets(
    'RestageScreenView strips before its controller and capture path',
    (tester) async {
      final completed = <Map<String, Object?>>[];
      final controller = _flowController(
        _resolvedCaptureFlow(
          rfwSourceBlob(_flowScreenSource(label: 'screen view')),
        ),
        onComplete: completed.add,
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: RestageScreenView<Map<String, Object?>>(
            controller: controller,
          ),
        ),
      );
      unawaited(controller.load());
      await tester.pumpAndSettle();
      await tester.tap(find.text('screen view'));
      await tester.pumpAndSettle();

      expect(completed, <Map<String, Object?>>[
        <String, Object?>{'captured': 'captured'},
      ]);
    },
  );

  testWidgets(
    'RestageFlowView strips before its interceptor and controller capture',
    (tester) async {
      final completed = <Map<String, Object?>>[];
      final intercepted = <Map<String, Object?>>[];
      final controller = _flowController(
        _resolvedCaptureFlow(
          rfwSourceBlob(_flowScreenSource(label: 'flow view')),
        ),
        onComplete: completed.add,
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: RestageFlowView<Map<String, Object?>>(
            controller: controller,
            onScreenEvent: (name, args) {
              expect(name, 'submit');
              intercepted.add(Map<String, Object?>.from(args));
              return false;
            },
          ),
        ),
      );
      unawaited(controller.load());
      await tester.pumpAndSettle();
      await tester.tap(find.text('flow view'));
      await tester.pumpAndSettle();

      expect(intercepted, <Map<String, Object?>>[
        <String, Object?>{'value': 'captured', 'business': 'visible'},
      ]);
      _expectNoReservedTopLevelKey(intercepted.single);
      expect(completed, <Map<String, Object?>>[
        <String, Object?>{'captured': 'captured'},
      ]);
    },
  );

  testWidgets(
    'RestageSurfaceFlow defensively strips local authored-event values before '
    'normalization and capture',
    (tester) async {
      Restage.registerWidgetLibrary(
        _authoredProbeLibrary,
        widgets: <RestageWidgetFactory>[
          RestageWidgetFactory(
            name: 'AuthoredProbe',
            builder: (_, __) => const _AuthoredProbe(),
          ),
        ],
      );
      final completed = <Map<String, Object?>>[];
      final blob = rfwSourceBlob('''
import acme.measurement;
widget OnboardingScreen = AuthoredProbe();
''');

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: RestageSurfaceFlow<Map<String, Object?>>(
            flow: _flowRef,
            resolver: StaticFlowResolver(
              _resolvedCaptureFlow(blob, captureKey: 'business'),
            ),
            unavailable: const FlowUnavailablePolicy.hide(),
            onComplete: completed.add,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('authored event'));
      await tester.pumpAndSettle();

      expect(completed, <Map<String, Object?>>[
        <String, Object?>{'captured': 'from local'},
      ]);
    },
  );

  testWidgets(
    'paywall demux, custom callbacks, purchase, and restore never receive the '
    'reserved namespace',
    (tester) async {
      final gateway = _RecordingGateway();
      Restage.configure(
        apiKey: 'rs_pk_test',
        analyticsEnabled: false,
        products: const <RestageProduct>[
          RestageProduct(
            id: 'pro_monthly',
            slot: 'primary',
            entitlement: 'pro',
          ),
        ],
        billingGateway: gateway,
      );
      final received = <RestageEvent>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RestagePaywall(
              id: 'measurement_paywall',
              resolver: _StaticPaywallResolver(rfwSourceBlob(_paywallSource())),
              onEvent: received.add,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (final label in <String>[
        'purchase',
        'restore',
        'custom exact',
        'custom malformed',
        'custom future',
        'custom multiple',
      ]) {
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
      }

      expect(gateway.purchaseCalls, <String>['pro_monthly']);
      expect(gateway.restoreCalls, 1);
      final initiated = received.whereType<PurchaseInitiated>().single;
      expect(initiated.productId, 'pro_monthly');
      final customs = received.whereType<PaywallCustomEvent>().toList();
      expect(
        customs.map((event) => event.eventName),
        <String>[
          'customExact',
          'customMalformed',
          'customFuture',
          'customMultiple',
        ],
      );
      final expectedBusinessValues = <String, String>{
        'customExact': 'exact',
        'customMalformed': 'malformed',
        'customFuture': 'future',
        'customMultiple': 'multiple',
      };
      for (final event in customs) {
        expect(event.args, <String, Object?>{
          'business': expectedBusinessValues[event.eventName],
        });
        _expectNoReservedTopLevelKey(event.args);
      }
    },
  );
}

Widget _screenHost({
  required ScreenFixture<String> fixture,
  ValueChanged<String>? onEvent,
}) =>
    MaterialApp(
      home: Scaffold(
        body: RestageSurfaceScreen<String>(
          screen: fixture.ref,
          resolver: FixedScreenResolver(fixture.bundled()),
          unavailable: SurfaceScreenUnavailablePolicy.fallback(
            builder: (_, error) => Text('fallback:${error.reason.name}'),
          ),
          onEvent: onEvent,
        ),
      ),
    );

RestageFlowController<Map<String, Object?>> _flowController(
  ResolvedFlow resolved, {
  required void Function(Map<String, Object?> value) onComplete,
}) =>
    RestageFlowController<Map<String, Object?>>(
      flow: _flowRef,
      resolver: StaticFlowResolver(resolved),
      actions: null,
      onEvent: (_) {},
      onComplete: onComplete,
      onUnavailable: (error) =>
          fail('unexpected flow failure: ${error.reason}'),
    );

ResolvedFlow _resolvedCaptureFlow(
  Uint8List blob, {
  String captureKey = 'value',
}) {
  final document = FlowDocument(
    flow: _flowRef.id,
    version: _flowRef.version,
    schemaVersion: 1,
    minClient: _flowRef.minClient,
    initial: 'screen',
    flowState: const <String, FlowStateDeclaration>{
      'captured': FlowStateDeclaration(
        type: FlowDataType.string,
        classification: FlowStateClassification.internal,
      ),
    },
    outbound: const FlowOutboundDeclarations(
      terminalResult: FlowOutboundPayloadDeclaration(
        fields: <String, FlowOutboundField>{
          'captured': FlowOutboundField(
            type: FlowDataType.string,
            ref: StateFlowOutboundRef(key: 'captured'),
          ),
        },
      ),
    ),
    screenArtifacts: <String, ScreenArtifact>{
      'screen': ScreenArtifact(
        path: 'screen.rfw',
        version: 1,
        schemaVersion: 1,
        minClient: _flowRef.minClient,
        contentHash: FlowContentHash.compute(blob),
      ),
    },
    states: <String, FlowState>{
      'screen': ScreenFlowState(
        screen: 'screen',
        on: <String, FlowTransition>{
          'submit': GotoFlowTransition(
            'done',
            stateWrites: <String, FlowStateWrite>{
              'captured': FlowStateWrite(
                type: FlowDataType.string,
                value: EventFlowValueSource(key: captureKey),
              ),
            },
          ),
        },
      ),
      'done': const EndFlowState(result: <String, Object?>{}),
    },
  );
  return ResolvedFlow(
    document: document,
    screenBlobs: <String, Uint8List>{'screen': blob},
    cacheHit: false,
  );
}

String _standaloneSource() => '''
import restage.core;
widget OnboardingScreen = Column(children: [
  GestureDetector(
    onTap: event "none" { $_routeKey: "$_carrier" },
    child: Text(text: "no arguments"),
  ),
  GestureDetector(
    onTap: event "value" { value: "seven", $_routeKey: "$_carrier" },
    child: Text(text: "scalar value"),
  ),
  GestureDetector(
    onTap: event "object" {
      cta: "primary",
      nested: { $_routeKey: "top-level-only business data" },
      $_routeKey: "$_carrier"
    },
    child: Text(text: "object value"),
  ),
]);
''';

String _standaloneInvalidCarrierSource() => '''
import restage.core;
widget OnboardingScreen = Column(children: [
  GestureDetector(
    onTap: event "malformed" { business: "malformed", $_routeKey: 7 },
    child: Text(text: "malformed"),
  ),
  GestureDetector(
    onTap: event "future" {
      business: "future",
      ${_reservedPrefix}route_v2: "future"
    },
    child: Text(text: "future"),
  ),
  GestureDetector(
    onTap: event "multiple" {
      business: "multiple",
      $_routeKey: "$_carrier",
      ${_reservedPrefix}future: "future"
    },
    child: Text(text: "multiple"),
  ),
]);
''';

String _flowScreenSource({required String label}) => '''
import restage.core;
widget OnboardingScreen = GestureDetector(
  onTap: event "submit" {
    value: "captured",
    business: "visible",
    $_routeKey: "$_carrier"
  },
  child: Text(text: "$label"),
);
''';

String _paywallSource() => '''
import restage.core;
import restage.material;
widget Paywall = Column(children: [
  TextButton(
    onPressed: event "restage.purchase" {
      productId: "pro_monthly",
      $_routeKey: "$_carrier"
    },
    child: Text(text: "purchase"),
  ),
  TextButton(
    onPressed: event "restage.restore" { $_routeKey: "$_carrier" },
    child: Text(text: "restore"),
  ),
  TextButton(
    onPressed: event "customExact" {
      business: "exact",
      $_routeKey: "$_carrier"
    },
    child: Text(text: "custom exact"),
  ),
  TextButton(
    onPressed: event "customMalformed" {
      business: "malformed",
      $_routeKey: 7
    },
    child: Text(text: "custom malformed"),
  ),
  TextButton(
    onPressed: event "customFuture" {
      business: "future",
      ${_reservedPrefix}route_v2: "future"
    },
    child: Text(text: "custom future"),
  ),
  TextButton(
    onPressed: event "customMultiple" {
      business: "multiple",
      $_routeKey: "$_carrier",
      ${_reservedPrefix}future: "future"
    },
    child: Text(text: "custom multiple"),
  ),
]);
''';

void _expectNoReservedTopLevelKey(Map<String, Object?> arguments) {
  expect(
    arguments.keys.where((key) => key.startsWith(_reservedPrefix)),
    isEmpty,
  );
}

final _authoredProbeLibrary = WidgetLibrary.custom('acme.measurement');

class _AuthoredProbe extends StatelessWidget {
  const _AuthoredProbe();

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: surfaceEvent<Map<String, Object?>, Map<String, Object?>>(
          const SurfaceEvent<Map<String, Object?>>('submit'),
          const <String, Object?>{
            'business': 'from local',
            'nested': <String, Object?>{_routeKey: 'nested business data'},
            _routeKey: _carrier,
          },
        ),
        child: const Text('authored event'),
      );
}

final class _StaticPaywallResolver implements VariantResolver {
  const _StaticPaywallResolver(this.bytes);

  final Uint8List bytes;

  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) async =>
      ResolvedVariant(bytes: bytes, paywallId: id);
}

final class _RecordingGateway implements BillingGateway {
  final purchaseCalls = <String>[];
  var restoreCalls = 0;

  @override
  Future<PurchaseOutcome> purchase(
    String productId, {
    String? basePlanId,
  }) async {
    purchaseCalls.add(productId);
    return PurchaseOutcome.succeeded(
      productId: productId,
      transactionId: 'transaction',
      verificationData: null,
      priceMicros: 1000000,
      currency: 'USD',
    );
  }

  @override
  Future<RestoreOutcome> restore() async {
    restoreCalls += 1;
    return RestoreOutcome.noPurchases();
  }
}
