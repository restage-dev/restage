import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/measurement/bundled_measurement_publication_binding_read_port.dart';
import 'package:restage_shared/restage_shared.dart';

import 'admitted_bundled_publication_fixture.dart';

typedef _Extra = ({
  String path,
  SurfacePublicationArtifactRole role,
  String? id,
  List<int> bytes,
});

const _sections = <_Extra>[
  (
    path: 'screen.icon-fonts/MaterialIcons.otf',
    role: SurfacePublicationArtifactRole.iconFont,
    id: 'MaterialIcons',
    bytes: [0, 1, 0, 0, 7],
  ),
  (
    path: 'screen.local.json',
    role: SurfacePublicationArtifactRole.localSeeds,
    id: 'fixture',
    bytes: [123, 125],
  ),
];

MeasurementBundledGeneratedArtifact _blob() =>
    MeasurementBundledGeneratedArtifact.fromBytes(
      logicalPath: 'screen.rfw',
      role: SurfacePublicationArtifactRole.screenBlob,
      id: 'fixture-artifact',
      bytes: AdmittedBundledPublicationFixture.artifactBytes,
    );

void main() {
  test('a bundled paywall with an icon font and seeds binds its Measurement',
      () async {
    final fixture = AdmittedBundledPublicationFixture.build(
      extraArtifacts: _sections,
    );

    final locator =
        await fixture.port.resolveExactGeneratedArtifactClosureCarrier(
      MeasurementBundledGeneratedArtifactClosureCarrier(artifacts: [_blob()]),
    );

    expect(locator, fixture.entry.generatedPublicationLocator);
  });

  test('a bundled flow with an icon font and seeds binds its Measurement',
      () async {
    const flowDocument = [123, 34, 102, 125];
    final fixture = AdmittedBundledPublicationFixture.build(
      extraArtifacts: [
        (
          path: 'flow.json',
          role: SurfacePublicationArtifactRole.flowDocument,
          id: null,
          bytes: flowDocument,
        ),
        ..._sections,
      ],
    );

    final locator =
        await fixture.port.resolveExactGeneratedArtifactClosureCarrier(
      MeasurementBundledGeneratedArtifactClosureCarrier(
        artifacts: [
          MeasurementBundledGeneratedArtifact.fromBytes(
            logicalPath: 'flow.json',
            role: SurfacePublicationArtifactRole.flowDocument,
            id: null,
            bytes: flowDocument,
          ),
          _blob(),
        ],
      ),
    );

    expect(locator, fixture.entry.generatedPublicationLocator);
  });

  test('a carrier whose blob differs still does not bind', () async {
    final fixture = AdmittedBundledPublicationFixture.build(
      extraArtifacts: _sections,
    );

    final locator =
        await fixture.port.resolveExactGeneratedArtifactClosureCarrier(
      MeasurementBundledGeneratedArtifactClosureCarrier(
        artifacts: [
          MeasurementBundledGeneratedArtifact.fromBytes(
            logicalPath: 'screen.rfw',
            role: SurfacePublicationArtifactRole.screenBlob,
            id: 'fixture-artifact',
            bytes: const [9, 9, 9],
          ),
        ],
      ),
    );

    expect(locator, isNull);
  });
}
