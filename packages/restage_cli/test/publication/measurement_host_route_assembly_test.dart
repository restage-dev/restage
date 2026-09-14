import 'dart:io';
import 'package:restage_cli/src/publication/publication_assembler.dart';
import 'package:restage_cli/src/publication/publication_errors.dart';
import 'package:restage_cli/src/publication/publication_manifest.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:test/test.dart';
import '../_helpers/publication_fixtures.dart';

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('host_route_');
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });
  Future<void> assemble() async {
    final loaded = await SurfacePublicationManifestLoader().load(
      projectRoot: root,
    );
    await SurfacePublicationAssembler().assemble(
      loaded: loaded,
      entry: loaded.manifest.publications.single,
    );
  }

  MeasurementOrderedCaptureDeclarationV1 lifecycle() =>
      MeasurementOrderedCaptureDeclarationV1(
        channels: [
          MeasurementOccurrenceChannelV1.presentation,
          MeasurementOccurrenceChannelV1.dismiss,
        ],
        lifecycleChannel: MeasurementOccurrenceChannelV1.dismiss,
      );
  test(
    'declared root lifecycle route needs no physical callback carrier',
    () async {
      await seedMeasurementPaywall(
        root,
        orderedCapture: lifecycle(),
        omitPhysicalCarrier: true,
      );
      await assemble();
    },
  );
  test('ordinary callbacks still require their exact carrier', () async {
    await seedMeasurementPaywall(root, omitPhysicalCarrier: true);
    await expectLater(assemble(), throwsA(isA<PublicationAssemblyException>()));
  });
  test('declared lifecycle cannot borrow sidecar ownership', () async {
    await seedMeasurementPaywall(
      root,
      orderedCapture: lifecycle(),
      omitPhysicalCarrier: true,
      routeOnSidecar: true,
    );
    await expectLater(assemble(), throwsA(isA<PublicationAssemblyException>()));
  });
  test('host route cannot masquerade as a physical callback', () async {
    await seedMeasurementPaywall(root, orderedCapture: lifecycle());
    await expectLater(assemble(), throwsA(isA<PublicationAssemblyException>()));
  });
}
