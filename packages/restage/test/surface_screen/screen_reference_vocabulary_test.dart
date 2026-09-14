import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_shared/restage_shared.dart';

const int _checkCodePoint = 0xe156;

const SurfaceVocabulary _welcomeVocabulary = SurfaceVocabulary(
  widgets: RestageWidgetLibraries.fromVocabulary(
    core: <String, LocalWidgetBuilder>{'Text': buildText},
  ),
  icons: RestageIconTable.fromFamilies(families: <String, Map<int, IconData>>{
    RestageIconTable.materialIconsFamily: <int, IconData>{
      _checkCodePoint: Icons.check,
    },
  }),
);

SurfaceScreenRef<Never> _buildReference() {
  final provenance = SurfaceScreenRuntimeProvenance(
    surface: Surface.onboarding,
    slug: 'welcome',
    contractVersion: 1,
    capabilities: CapabilityManifest(
      builtInFloor: 1,
      requiredLibraries: const [],
    ),
    eventSchema: SurfaceScreenEventSchema(events: const <SurfaceScreenEvent>[]),
    vocabulary: _welcomeVocabulary,
  );
  return SurfaceScreenRef<Never>.generated(
    provenance: provenance,
    eventContract: SurfaceScreenEventContract<Never>.none(
      hash: provenance.eventContractHash,
    ),
  );
}

/// The shape generated code emits: a lazy top-level reference, first read when
/// the application names the screen.
final SurfaceScreenRef<Never> _welcomeScreen = _buildReference();

void main() {
  setUp(() {
    InstalledWidgetLibraries.reset();
    InstalledIconTable.reset();
  });

  tearDown(() {
    InstalledIconTable.reset();
    InstalledWidgetLibraries.install(RestageWidgetLibraries.builtIn());
  });

  test('reading a screen reference installs the screen vocabulary', () {
    expect(InstalledWidgetLibraries.current.isEmpty, isTrue);
    expect(InstalledIconTable.current.isEmpty, isTrue);

    expect(_welcomeScreen.slug, 'welcome');

    expect(InstalledWidgetLibraries.current.core.keys, {'Text'});
    expect(
      InstalledIconTable.current.lookUp(
        RestageIconTable.materialIconsFamily,
        _checkCodePoint,
      ),
      Icons.check,
    );
  });

  test('a reference carrying no vocabulary installs nothing', () {
    final provenance = SurfaceScreenRuntimeProvenance(
      surface: Surface.onboarding,
      slug: 'plain',
      contractVersion: 1,
      capabilities: CapabilityManifest(
        builtInFloor: 1,
        requiredLibraries: const [],
      ),
      eventSchema:
          SurfaceScreenEventSchema(events: const <SurfaceScreenEvent>[]),
    );

    final reference = SurfaceScreenRef<Never>.generated(
      provenance: provenance,
      eventContract: SurfaceScreenEventContract<Never>.none(
        hash: provenance.eventContractHash,
      ),
    );

    expect(reference.slug, 'plain');
    expect(InstalledWidgetLibraries.current, same(RestageWidgetLibraries.none));
    expect(InstalledIconTable.current, same(RestageIconTable.none));
  });
}
