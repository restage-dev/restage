import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_core/library_registration.dart' as restage_core;
import 'package:restage/src/flow/flow_runtime_support.dart';
import 'package:restage/src/measurement/measurement_rfw_presentation.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:rfw/formats.dart';
import 'package:rfw/rfw.dart' hide WidgetLibrary;

final class _StaticResolver implements VariantResolver {
  const _StaticResolver(this.bytes);

  final Uint8List bytes;

  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) async =>
      ResolvedVariant(bytes: bytes, paywallId: id);
}

void main() {
  setUp(Restage.debugReset);

  testWidgets('flow runtime renders MeasurementPresented without a scope', (
    tester,
  ) async {
    final runtime = FlowScreenLibraries().runtimeFor(
      parseLibraryFile(_screenSource('flow child')),
    );
    addTearDown(runtime.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RemoteWidget(
            runtime: runtime,
            data: DynamicContent(),
            widget: kFlowScreenWidget,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('flow child'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'direct paywall blob runtime renders MeasurementPresented without a scope',
    (tester) async {
      final bytes = Uint8List.fromList(
        encodeLibraryBlob(parseLibraryFile(_paywallSource('paywall child'))),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RestagePaywall(
              id: 'measurement-paywall',
              resolver: _StaticResolver(bytes),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('paywall child'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'private installation replaces a stale same-namespace runtime entry',
    (tester) async {
      const rootLibrary = LibraryName(<String>['acme', 'surface']);
      final runtime = Runtime()
        ..update(
          const LibraryName(<String>['restage', 'core']),
          restage_core.buildCoreWidgetLibrary(),
        )
        ..update(
          kMeasurementRfwPresentationLibrary,
          LocalWidgetLibrary(<String, LocalWidgetBuilder>{
            'MeasurementPresented': (_, __) => const Text('stale entry'),
          }),
        )
        ..update(
          rootLibrary,
          parseLibraryFile(_paywallSource('private child')),
        );
      installMeasurementRfwPresentationLibrary(runtime);
      addTearDown(runtime.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RemoteWidget(
              runtime: runtime,
              data: DynamicContent(),
              widget: const FullyQualifiedWidgetName(rootLibrary, 'Paywall'),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('private child'), findsOneWidget);
      expect(find.text('stale entry'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

String _screenSource(String label) => '''
import restage.core;
import restage.measurement;
widget OnboardingScreen = MeasurementPresented(
  carriers: ["${_carrier('reference.flow-renderer-install')}"],
  child: Text(text: "$label"),
);
''';

String _paywallSource(String label) => '''
import restage.core;
import restage.measurement;
widget Paywall = MeasurementPresented(
  carriers: ["${_carrier('reference.paywall-renderer-install')}"],
  child: Text(text: "$label"),
);
''';

String _carrier(String reference) =>
    MeasurementPublicationRouteCarrierV1.derive(
      routeDraftClosureDigest: CanonicalDigest('a' * 64),
      artifactOccurrenceEdgeToken: ArtifactOccurrenceEdgeToken(
        'edge.renderer-library-install',
      ),
      generatedReferenceId: GeneratedReferenceId(reference),
    ).value;
