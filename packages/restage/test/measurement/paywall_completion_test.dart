import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/measurement/bundled_measurement_publication_binding_read_port.dart';
import 'package:restage/src/measurement/measurement_worker_protocol.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:rfw/formats.dart';

import 'admitted_bundled_publication_fixture.dart';
import 'measurement_host_construction_test_support.dart';
import '../support/pump_until.dart';

String _carrier(String letter) {
  final edge =
      base64UrlEncode(utf8.encode('edge.bundled-root')).replaceAll('=', '');
  return 'mrv1.$edge.${letter * 32}';
}

// "Buy" taps the route that completes the surface; "Browse" taps an ordinary one.
final Uint8List _paywallBlob = Uint8List.fromList(encodeLibraryBlob(
  parseLibraryFile('''
    import restage.core;
    widget Paywall = Column(children: [
      GestureDetector(
        onTap: event "buy" { $kMeasurementPublicationRouteArgumentKeyV1: "${_carrier('B')}" },
        child: Text(text: "Buy"),
      ),
      GestureDetector(
        onTap: event "browse" { $kMeasurementPublicationRouteArgumentKeyV1: "${_carrier('A')}" },
        child: Text(text: "Browse"),
      ),
      GestureDetector(
        onTap: event "purchased" {},
        child: Text(text: "Purchased"),
      ),
    ]);
  '''),
));

class _BundledResolver implements VariantResolver {
  _BundledResolver(this.fixture);
  final AdmittedBundledPublicationFixture fixture;

  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) async =>
      attachMeasurementBundledGeneratedSourceCarrier(
        ResolvedVariant(
          bytes: _paywallBlob,
          paywallId: id,
          surfaceVersion: FlowContentHash.compute(_paywallBlob).value,
        ),
        MeasurementBundledGeneratedSourceCarrier(
          measurementPublicationDraftDigest: fixture
              .entry.candidateProof.measurementPublicationDraft.canonicalDigest,
        ),
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<List<MeasurementWorkerAppendValue>> endAfterTap(
    WidgetTester tester,
    String label, {
    Set<String> completesOn = const {},
    Future<void> Function(WidgetTester tester)? before,
  }) async {
    final fixture = AdmittedBundledPublicationFixture.build(
      completingTap: true,
      lifecycleEnds: true,
      artifact: _paywallBlob,
    );
    final profile = Completer<BundledMeasurementTargetProfileLoadResult>();
    final harness = AdmittedConstructionOwnerHostTestHarness.install(
      publicationContext: fixture.publicationContextRef,
      bundledTargetProfileLoader: () => profile.future,
      presentationMetadataAdmitted: true,
    );
    addTearDown(harness.close);
    final controller = RestagePaywallController();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RestagePaywall(
          id: 'pro_upgrade',
          placementBinding: completesOn.isEmpty
              ? null
              : RestagePaywall.generatedPlacementBinding(
                  definition: () => _definition(completesOn)),
          resolver: _BundledResolver(fixture),
          controller: controller,
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
    profile.complete(BundledMeasurementTargetProfileLoadResult(
      target: fixture.target,
      bindingReadPort: fixture.port,
    ));
    // The session opens on real async work; wait for its worker registration.
    await pumpUntil(
      tester,
      () => harness.worker.registrations.isNotEmpty,
      reason: 'a worker registration',
    );

    await before?.call(tester);
    await tester.tap(find.text(label));
    await tester.pump();
    controller.dismiss();
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    bool ended() => harness.worker.appendRecords.any((record) =>
        record.value == MeasurementWorkerAppendValue.completion ||
        record.value == MeasurementWorkerAppendValue.dismiss);
    await pumpUntil(tester, ended, reason: 'the surface end record');

    return [
      for (final record in harness.worker.appendRecords)
        if (record.value == MeasurementWorkerAppendValue.completion ||
            record.value == MeasurementWorkerAppendValue.dismiss)
          record.value,
    ];
  }

  testWidgets('a tap on a route marked as completing still dismisses',
      (tester) async {
    expect(
      await endAfterTap(tester, 'Buy'),
      [MeasurementWorkerAppendValue.dismiss],
    );
  });

  testWidgets(
      'a completesOn event fired by app code completes the paywall, '
      'whatever is tapped after it', (tester) async {
    expect(
      await endAfterTap(
        tester,
        'Browse',
        completesOn: {'purchased'},
        before: (tester) async {
          // App code below the paywall, as after a successful purchase.
          final context = tester.element(find.text('Browse'));
          context.surfaceEvent(const SurfaceEvent<void>('purchased'))();
          await tester.pump();
        },
      ),
      [MeasurementWorkerAppendValue.completion],
    );
  });

  testWidgets(
      'a completesOn event a tap in the design fires does not complete the '
      'paywall', (tester) async {
    expect(
      await endAfterTap(tester, 'Purchased', completesOn: {'purchased'}),
      [MeasurementWorkerAppendValue.dismiss],
    );
  });

  testWidgets('an event the paywall does not complete on still dismisses',
      (tester) async {
    expect(
      await endAfterTap(tester, 'Purchased', completesOn: {'other'}),
      [MeasurementWorkerAppendValue.dismiss],
    );
  });

  testWidgets('closing after an ordinary tap records dismiss', (tester) async {
    expect(
      await endAfterTap(tester, 'Browse'),
      [MeasurementWorkerAppendValue.dismiss],
    );
  });
}

GeneratedPlacementDefinition _definition(Set<String> completesOn) =>
    RestagePaywall.generatedPlacementDefinition(
      id: 'pro_upgrade',
      defaultSurfaceLocatorJson: <String, Object?>{
        'surfaceType': 'paywall',
        'slug': 'pro_upgrade',
        'family': <String, Object?>{'kind': 'general'},
      },
      hostContractJson: <String, Object?>{
        'schemaVersion': 1,
        'hosting': <String, Object?>{
          'contentKind': 'single',
          'presentation': 'inline',
        },
        'providedContext': <String, Object?>{
          'schemaVersion': 1,
          'inputs': <String, Object?>{},
        },
        'handledEvents': <String, Object?>{
          'schemaVersion': 1,
          'events': <Object?>[],
        },
        'flowBoundary': null,
      },
      completesOn: completesOn,
    );
