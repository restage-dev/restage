import 'dart:typed_data';

import 'package:flutter/cupertino.dart' show CupertinoButton, CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/formats.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/restage_runtime_test_support.dart';
import '../surface_screen/surface_screen_test_support.dart';

const _selected = SurfaceVocabulary(
  widgets: RestageWidgetLibraries.fromVocabulary(core: {'Text': buildText}),
);

class _HostedByIdResolver implements VariantResolver {
  @override
  Future<ResolvedVariant> resolve(String id,
      {String? placementId, Locale? locale}) async {
    return ResolvedVariant(
      bytes: Uint8List.fromList(encodeLibraryBlob(parseLibraryFile('''
import restage.core;
import restage.material;
import restage.cupertino;
widget Paywall = Column(children: [
  Chip(label: Text(text: "delivered Material")),
  CupertinoButton(child: Text(text: "delivered Cupertino")),
  Icon(iconCodepoint: ${Icons.check.codePoint}),
  Icon(iconCodepoint: ${CupertinoIcons.star.codePoint}, iconFontFamily: "CupertinoIcons")
]);
'''))),
      surfaceVersion: 'remote-v1',
      paywallId: id,
    );
  }
}

void main() {
  installRestageRuntimeTestSupport();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Restage.debugReset();
    InstalledWidgetLibraries.reset();
    InstalledIconTable.reset();
  });
  tearDown(() {
    InstalledWidgetLibraries.install(RestageWidgetLibraries.builtIn());
    InstalledIconTable.reset();
  });

  testWidgets(
      'ordinary configure renders delivered catalogs and icons with no codegen',
      (tester) async {
    await tester.runAsync(() async {
      Restage.configure(
          resolver: _HostedByIdResolver(), analyticsEnabled: false);
    });
    final libraries = InstalledWidgetLibraries.current;
    expect(
        libraries.core.length +
            libraries.material.length +
            libraries.cupertino.length,
        119);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: RestagePaywall(
                id: 'new-ota-content',
                errorBuilder: (_, error) => Text('ERROR: ${error.message}')))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('ERROR:'), findsNothing);
    expect(find.byType(Chip), findsOneWidget);
    expect(find.byType(CupertinoButton), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.star), findsOneWidget);
  });

  testWidgets(
      'ordinary configure mounts a delivered screen without generated registration',
      (tester) async {
    final fixture = stringScreenFixture(
      blob: rfwSourceBlob('''
import restage.core;
import restage.cupertino;
widget OnboardingScreen = CupertinoButton(child: Text(text: "delivered screen"));
'''),
    );
    expect(InstalledWidgetLibraries.current.isEmpty, isTrue);
    await tester.runAsync(() async {
      Restage.configure(
        analyticsEnabled: false,
        surfaceScreenResolver: FixedScreenResolver(fixture.hosted()),
      );
    });
    await tester.pumpWidget(MaterialApp(
        home: RestageScreen<String>(
      screen: fixture.ref,
      unavailable: SurfaceScreenUnavailablePolicy.fallback(
        builder: (_, error) => Text('fallback:${error.reason.name}'),
      ),
    )));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('delivered screen'), findsOneWidget);
    expect(find.byType(CupertinoButton), findsOneWidget);
    expect(find.textContaining('fallback:'), findsNothing);
  });

  for (final custom in [false, true]) {
    testWidgets(
        'installed catalog renders an explicit ${custom ? 'custom' : 'reduced'} selection',
        (tester) async {
      final libraries = custom
          ? RestageWidgetLibraries.fromVocabulary(core: {
              'CustomLabel': (_, source) => Text(source.v<String>(['text'])!),
            })
          : _selected.widgets;
      InstalledWidgetLibraries.install(libraries);
      InstalledIconTable.install(RestageIconTable.none);
      final fixture = stringScreenFixture(blob: rfwSourceBlob('''
import restage.core;
widget OnboardingScreen = ${custom ? 'CustomLabel' : 'Text'}(text: "selected render");
'''));
      await tester.runAsync(() async {
        Restage.configureWithInstalledCatalog(
          analyticsEnabled: false,
          surfaceScreenResolver: FixedScreenResolver(fixture.hosted()),
        );
      });
      await tester.pumpWidget(MaterialApp(
          home: RestageScreen<String>(
        screen: fixture.ref,
        unavailable: SurfaceScreenUnavailablePolicy.fallback(
          builder: (_, error) => Text('fallback:${error.reason.name}'),
        ),
      )));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('selected render'), findsOneWidget);
      expect(find.textContaining('fallback:'), findsNothing);
      expect(InstalledWidgetLibraries.current, same(libraries));
      expect(libraries.material, isEmpty);
      expect(libraries.cupertino, isEmpty);
      expect(InstalledIconTable.current, same(RestageIconTable.none));
    });
  }

  test('invalid configuration cannot install the default catalogs', () {
    expect(
        () => Restage.configure(
              governedMeasurementTransportEnabled: true,
              governedMeasurementTransport: _UnusedTransport(),
            ),
        throwsArgumentError);
    expect(InstalledWidgetLibraries.current, same(RestageWidgetLibraries.none));
    expect(InstalledIconTable.current, same(RestageIconTable.none));
    expect(InstalledWidgetLibraries.hasSelection, isFalse);
    expect(InstalledIconTable.hasSelection, isFalse);
  });

  for (final installedOnly in [false, true]) {
    void configure() => installedOnly
        ? Restage.configureWithInstalledCatalog(analyticsEnabled: false)
        : Restage.configure(analyticsEnabled: false);

    test(
        'generated reference read before configuration installedOnly=$installedOnly preserves implicit entries',
        () {
      const customIcon = IconData(0xe156,
          fontFamily: 'MaterialIcons', fontPackage: 'host_icons');
      const customMirrored = IconData(0xe67e,
          fontFamily: 'MaterialIcons',
          fontPackage: 'host_icons',
          matchTextDirection: true);
      const vocabulary = SurfaceVocabulary(
        widgets: RestageWidgetLibraries.fromVocabulary(core: {
          'Text': _customLabel,
          'ImplicitLabel': _customLabel,
        }),
        icons: RestageIconTable.fromFamilies(
          families: {
            'MaterialIcons': {0xe156: customIcon},
            'HostIcons': {7: customIcon},
          },
          mirrored: {
            'MaterialIcons': {0xe67e: customMirrored},
          },
        ),
      );
      late final reference = _implicitReference(vocabulary);
      expect(reference.slug, 'implicit-screen');
      expect(InstalledWidgetLibraries.hasSelection, isFalse);
      expect(InstalledIconTable.hasSelection, isFalse);
      final widgets = InstalledWidgetLibraries.current;
      final icons = InstalledIconTable.current;

      configure();
      expect(InstalledWidgetLibraries.current.core['Text'], same(_customLabel));
      expect(InstalledWidgetLibraries.current.core['ImplicitLabel'],
          same(_customLabel));
      expect(InstalledIconTable.current.lookUp('MaterialIcons', 0xe156),
          same(customIcon));
      expect(
          InstalledIconTable.current.lookUp('HostIcons', 7), same(customIcon));
      expect(
          InstalledIconTable.current
              .lookUp('MaterialIcons', 0xe67e, matchTextDirection: true),
          same(customMirrored));
      if (installedOnly) {
        expect(InstalledWidgetLibraries.current, same(widgets));
        expect(InstalledIconTable.current, same(icons));
        expect(widgets.material, isEmpty);
        expect(widgets.cupertino, isEmpty);
        expect(icons.families, isNot(contains('CupertinoIcons')));
      } else {
        expect(
            InstalledWidgetLibraries.current.core['Column'], same(buildColumn));
        expect(
            InstalledWidgetLibraries.current.material['Icon'], same(buildIcon));
        expect(InstalledWidgetLibraries.current.cupertino['CupertinoButton'],
            same(buildCupertinoButton));
        expect(
            InstalledIconTable.current
                .lookUp('CupertinoIcons', CupertinoIcons.star.codePoint),
            same(CupertinoIcons.star));
      }
      final configuredWidgets = InstalledWidgetLibraries.current;
      final configuredIcons = InstalledIconTable.current;
      configure();
      expect(InstalledWidgetLibraries.current, same(configuredWidgets));
      expect(InstalledIconTable.current, same(configuredIcons));
    });

    test(
        'configuration installedOnly=$installedOnly preserves direct additions',
        () {
      InstalledWidgetLibraries.add(_selected.widgets);
      InstalledIconTable.add(const RestageIconTable.fromFamilies(families: {
        'HostIcons': {7: Icons.check},
      }));
      final widgets = InstalledWidgetLibraries.current;
      final icons = InstalledIconTable.current;
      configure();
      expect(InstalledWidgetLibraries.current, same(widgets));
      expect(InstalledIconTable.current, same(icons));
    });

    test(
        'configuration installedOnly=$installedOnly preserves selected widgets and empty icons',
        () {
      _selected.addToInstalled(explicitSelection: true);
      final widgets = InstalledWidgetLibraries.current;
      final icons = InstalledIconTable.current;
      configure();
      configure();
      expect(InstalledWidgetLibraries.current, same(widgets));
      expect(InstalledIconTable.current, same(icons));
      expect(widgets.core.keys, ['Text']);
      expect(icons.isEmpty, isTrue);
    });

    test(
        'configuration installedOnly=$installedOnly preserves explicit empty and later surface additions',
        () {
      SurfaceVocabulary.none.addToInstalled(explicitSelection: true);
      configure();
      expect(
          InstalledWidgetLibraries.current, same(RestageWidgetLibraries.none));
      expect(InstalledIconTable.current, same(RestageIconTable.none));
      _selected.addToInstalled();
      configure();
      expect(InstalledWidgetLibraries.current.core.keys, ['Text']);
      expect(InstalledIconTable.current.isEmpty, isTrue);
    });

    test(
        'configuration installedOnly=$installedOnly preserves custom installed objects',
        () {
      final widgets = RestageWidgetLibraries.fromVocabulary(
          core: {'custom': (_, __) => const Text('custom')});
      const icons = RestageIconTable.fromFamilies(families: {
        'custom': {7: Icons.check}
      });
      InstalledWidgetLibraries.install(widgets);
      InstalledIconTable.install(icons);
      configure();
      expect(InstalledWidgetLibraries.current, same(widgets));
      expect(InstalledIconTable.current, same(icons));
    });
  }

  test(
      'inclusive configuration retains an implicit family emptied by its owner',
      () {
    final glyphs = <int, IconData>{7: Icons.check};
    InstalledIconTable.add(
      RestageIconTable.fromFamilies(families: {'HostIcons': glyphs}),
      explicitSelection: false,
    );
    glyphs.clear();
    Restage.configure(analyticsEnabled: false, measurementEnabled: false);
    expect(InstalledIconTable.current.families['HostIcons'], same(glyphs));
    glyphs[8] = Icons.star;
    expect(InstalledIconTable.current.lookUp('HostIcons', 8), same(Icons.star));
    expect(
        InstalledIconTable.current
            .lookUp('MaterialIcons', Icons.check.codePoint),
        same(Icons.check));
  });

  test(
      'installed entrypoint permits late selection, reset clears selection intent',
      () {
    Restage.configureWithInstalledCatalog(analyticsEnabled: false);
    expect(InstalledWidgetLibraries.hasSelection, isFalse);
    expect(InstalledIconTable.hasSelection, isFalse);
    _selected.addToInstalled(explicitSelection: true);
    Restage.debugReset();
    Restage.configure(analyticsEnabled: false);
    expect(InstalledWidgetLibraries.current.core.keys, ['Text']);
    InstalledWidgetLibraries.reset();
    InstalledIconTable.reset();
    expect(InstalledWidgetLibraries.hasSelection, isFalse);
    expect(InstalledIconTable.hasSelection, isFalse);
    Restage.configure(analyticsEnabled: false);
    final widgets = InstalledWidgetLibraries.current;
    final icons = InstalledIconTable.current;
    expect(widgets.material, isNotEmpty);
    expect(icons.isEmpty, isFalse);
    Restage.configure(analyticsEnabled: false);
    expect(InstalledWidgetLibraries.current, same(widgets));
    expect(InstalledIconTable.current, same(icons));
  });
}

// No operation is invoked: configure must reject the conflicting arguments.
class _UnusedTransport implements RestageGovernedMeasurementTransport {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('not called');
}

Widget _customLabel(BuildContext context, DataSource source) =>
    const Text('custom label');

SurfaceScreenRef<Never> _implicitReference(SurfaceVocabulary vocabulary) {
  final provenance = SurfaceScreenRuntimeProvenance(
    surface: Surface.onboarding,
    slug: 'implicit-screen',
    contractVersion: 1,
    capabilities: CapabilityManifest(builtInFloor: 1, requiredLibraries: []),
    eventSchema: SurfaceScreenEventSchema(events: []),
    vocabulary: vocabulary,
  );
  return SurfaceScreenRef<Never>.generated(
    provenance: provenance,
    eventContract: SurfaceScreenEventContract<Never>.none(
      hash: provenance.eventContractHash,
    ),
  );
}
