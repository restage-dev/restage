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
    String label,
  ) async {
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
    for (var i = 0; i < 400 && harness.worker.registrations.isEmpty; i += 1) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
    }
    expect(harness.worker.registrations, isNotEmpty);

    await tester.tap(find.text(label));
    await tester.pump();
    controller.dismiss();
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    bool ended() => harness.worker.appendRecords.any((record) =>
        record.value == MeasurementWorkerAppendValue.completion ||
        record.value == MeasurementWorkerAppendValue.dismiss);
    for (var i = 0; i < 400 && !ended(); i += 1) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
    }

    return [
      for (final record in harness.worker.appendRecords)
        if (record.value == MeasurementWorkerAppendValue.completion ||
            record.value == MeasurementWorkerAppendValue.dismiss)
          record.value,
    ];
  }

  testWidgets('closing after a completing tap records completion',
      (tester) async {
    expect(
      await endAfterTap(tester, 'Buy'),
      [MeasurementWorkerAppendValue.completion],
    );
  });

  testWidgets('closing after an ordinary tap records dismiss', (tester) async {
    expect(
      await endAfterTap(tester, 'Browse'),
      [MeasurementWorkerAppendValue.dismiss],
    );
  });
}
