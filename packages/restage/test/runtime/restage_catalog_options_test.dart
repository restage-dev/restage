import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_core/library_registration.dart' as core;
import 'package:restage_cupertino/icon_table.dart' as cupertino_catalog;
import 'package:restage_cupertino/library_registration.dart'
    as cupertino_catalog;
import 'package:restage_material/icon_table.dart' as material_catalog;
import 'package:restage_material/library_registration.dart' as material_catalog;
import 'package:shared_preferences/shared_preferences.dart';

import '../support/restage_runtime_test_support.dart';
import '../surface_screen/surface_screen_test_support.dart';
import 'fixtures/catalog_options_derived.g.dart' as derived;
import 'fixtures/catalog_options_full.g.dart' as full;

Widget _customIcon(BuildContext context, DataSource source) =>
    const Text('custom icon');

void main() {
  installRestageRuntimeTestSupport();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    InstalledWidgetLibraries.reset();
    InstalledIconTable.reset();
  });
  tearDown(() {
    InstalledWidgetLibraries.reset();
    InstalledIconTable.reset();
  });

  test('no-argument helpers and configuration retain full defaults', () {
    _expectCompleteFamilies(
        RestageWidgetLibraries.builtIn(), builtInIconTable(),
        material: true, cupertino: true);
    Restage.configure(analyticsEnabled: false, measurementEnabled: false);
    _expectCompleteFamilies(
        InstalledWidgetLibraries.current, InstalledIconTable.current,
        material: true, cupertino: true);
  });

  for (final includeMaterial in [false, true]) {
    for (final includeCupertino in [false, true]) {
      final flags = 'material=$includeMaterial cupertino=$includeCupertino';
      final expectedFlags = (includeMaterial, includeCupertino);

      test('direct helpers select complete families $flags', () {
        _expectCompleteFamilies(
          RestageWidgetLibraries.builtIn(
            includeMaterial: includeMaterial,
            includeCupertino: includeCupertino,
          ),
          builtInIconTable(
            includeMaterial: includeMaterial,
            includeCupertino: includeCupertino,
          ),
          material: includeMaterial,
          cupertino: includeCupertino,
        );
      });

      test('configuration without registration selects families $flags', () {
        Restage.configure(
          analyticsEnabled: false,
          measurementEnabled: false,
          includeMaterial: includeMaterial,
          includeCupertino: includeCupertino,
        );
        _expectCompleteFamilies(
            InstalledWidgetLibraries.current, InstalledIconTable.current,
            material: includeMaterial, cupertino: includeCupertino);
      });

      test(
          'callback receives exact flags after configuration before bootstrap $flags',
          () {
        final previousGeneration = Restage.configurationGeneration;
        var calls = 0;
        Restage.configure(
          analyticsEnabled: false,
          measurementEnabled: false,
          includeMaterial: includeMaterial,
          includeCupertino: includeCupertino,
          registerWidgets: _RegistrationCallback((
              {required includeMaterial, required includeCupertino}) {
            calls++;
            expect((includeMaterial, includeCupertino), expectedFlags);
            expect(Restage.configurationGeneration, previousGeneration + 1);
            expect(InstalledWidgetLibraries.current,
                same(RestageWidgetLibraries.none));
            expect(InstalledIconTable.current, same(RestageIconTable.none));
            expect(InstalledWidgetLibraries.hasSelection, isFalse);
            expect(InstalledIconTable.hasSelection, isFalse);
            SurfaceVocabulary.none.addToInstalled(explicitSelection: true);
          }),
        );
        expect(calls, 1);
        expect(InstalledWidgetLibraries.current,
            same(RestageWidgetLibraries.none));
        expect(InstalledIconTable.current, same(RestageIconTable.none));
      });

      test('actual full registration retains required entries $flags', () {
        Restage.configure(
          analyticsEnabled: false,
          measurementEnabled: false,
          includeMaterial: includeMaterial,
          includeCupertino: includeCupertino,
          registerWidgets: full.kRestageWidgetRegistration,
        );
        final widgets = InstalledWidgetLibraries.current;
        expect(widgets.core, equals(core.kCoreLibraryFactories));
        expect(widgets.material.containsKey('Chip'), includeMaterial);
        expect(
            widgets.cupertino.containsKey('CupertinoButton'), includeCupertino);
        expect(widgets.material['Icon'], same(buildIcon));
        expect(
            InstalledIconTable.current
                .lookUp('MaterialIcons', Icons.star.codePoint),
            equals(Icons.star));
        expect(
            InstalledIconTable.current
                .lookUp('CupertinoIcons', CupertinoIcons.star.codePoint),
            equals(CupertinoIcons.star));
        expect(
            InstalledIconTable.current
                .lookUp('MaterialIcons', Icons.check.codePoint),
            includeMaterial ? same(Icons.check) : isNull);
        expect(
            InstalledIconTable.current
                .lookUp('CupertinoIcons', CupertinoIcons.heart.codePoint),
            includeCupertino ? same(CupertinoIcons.heart) : isNull);
      });

      test('actual derived registration remains derived $flags', () {
        Restage.configure(
          analyticsEnabled: false,
          measurementEnabled: false,
          includeMaterial: includeMaterial,
          includeCupertino: includeCupertino,
          registerWidgets: derived.kRestageWidgetRegistration,
        );
        expect(InstalledWidgetLibraries.current.core.keys, ['Text']);
        expect(InstalledWidgetLibraries.current.material.keys, ['Icon']);
        expect(InstalledWidgetLibraries.current.cupertino, isEmpty);
        expect(InstalledIconTable.current.families['MaterialIcons']!.keys,
            [Icons.star.codePoint]);
        expect(InstalledIconTable.current.families['CupertinoIcons']!.keys,
            [CupertinoIcons.star.codePoint]);
      });
    }
  }

  for (final selectWidgets in [false, true]) {
    for (final empty in [false, true]) {
      test(
          'no callback preserves independent ${selectWidgets ? 'widget' : 'icon'} selection empty=$empty',
          () {
        final customWidgets = RestageWidgetLibraries.fromVocabulary(
            material: empty ? const {} : {'Icon': _customIcon});
        final glyphs = <int, IconData>{if (!empty) 7: Icons.check};
        final customIcons =
            RestageIconTable.fromFamilies(families: {'HostIcons': glyphs});
        if (selectWidgets) {
          InstalledWidgetLibraries.install(customWidgets);
        } else {
          InstalledIconTable.install(customIcons);
        }
        Restage.configure(
          analyticsEnabled: false,
          measurementEnabled: false,
          includeMaterial: false,
          includeCupertino: true,
        );
        if (selectWidgets) {
          expect(InstalledWidgetLibraries.current, same(customWidgets));
          expect(customWidgets.material.keys, empty ? isEmpty : ['Icon']);
          expect(InstalledIconTable.current.families.keys, ['CupertinoIcons']);
        } else {
          expect(InstalledIconTable.current, same(customIcons));
          glyphs[8] = Icons.star;
          expect(InstalledIconTable.current.lookUp('HostIcons', 8),
              same(Icons.star));
          expect(InstalledWidgetLibraries.current.material, isEmpty);
          expect(InstalledWidgetLibraries.current.cupertino,
              same(cupertino_catalog.kCupertinoLibraryFactories));
        }
      });
    }
  }

  test(
      'additive callback preserves custom collisions and unrelated mutable families',
      () {
    const customStar =
        IconData(0xf81f, fontFamily: 'CupertinoIcons', fontPackage: 'host');
    final customGlyphs = <int, IconData>{7: Icons.check};
    final mirrored = material_catalog.kMirroredMaterialIconTable.entries.first;
    const customMirrored = IconData(7,
        fontFamily: 'MaterialIcons',
        fontPackage: 'host',
        matchTextDirection: true);
    InstalledWidgetLibraries.install(
        const RestageWidgetLibraries.fromVocabulary(
            material: {'Icon': _customIcon}));
    InstalledIconTable.install(RestageIconTable.fromFamilies(families: {
      'CupertinoIcons': {CupertinoIcons.star.codePoint: customStar},
      'HostIcons': customGlyphs,
    }, mirrored: {
      'MaterialIcons': {mirrored.key: customMirrored},
    }));
    Restage.configure(
      analyticsEnabled: false,
      measurementEnabled: false,
      includeMaterial: true,
      includeCupertino: false,
      registerWidgets: full.kRestageWidgetRegistration,
    );
    expect(
        InstalledWidgetLibraries.current.material['Icon'], same(_customIcon));
    expect(InstalledWidgetLibraries.current.material['Chip'], same(buildChip));
    expect(
        InstalledIconTable.current
            .lookUp('CupertinoIcons', CupertinoIcons.star.codePoint),
        same(customStar));
    expect(
        InstalledIconTable.current
            .lookUp('MaterialIcons', mirrored.key, matchTextDirection: true),
        same(customMirrored));
    expect(
        InstalledIconTable.current.families['HostIcons'], same(customGlyphs));
    customGlyphs[8] = Icons.star;
    expect(InstalledIconTable.current.lookUp('HostIcons', 8), same(Icons.star));
  });

  test('earlier no-argument full registration cannot be narrowed', () {
    full.registerRestageWidgets();
    final widgets = InstalledWidgetLibraries.current;
    final icons = InstalledIconTable.current;
    Restage.configure(
      analyticsEnabled: false,
      measurementEnabled: false,
      includeMaterial: false,
      includeCupertino: false,
    );
    expect(InstalledWidgetLibraries.current, same(widgets));
    expect(InstalledIconTable.current, same(icons));
    expect(widgets.material.containsKey('Chip'), isTrue);
    expect(widgets.cupertino.containsKey('CupertinoButton'), isTrue);
  });

  test(
      'callback errors propagate once after shared configuration without bootstrap',
      () {
    final failure = StateError('registration failed');
    final generation = Restage.configurationGeneration;
    var calls = 0;
    expect(
      () => Restage.configure(
        analyticsEnabled: false,
        measurementEnabled: false,
        registerWidgets: _RegistrationCallback((
            {required includeMaterial, required includeCupertino}) {
          calls++;
          expect(Restage.configurationGeneration, generation + 1);
          const SurfaceVocabulary(
            widgets: RestageWidgetLibraries.fromVocabulary(
                core: {'Text': buildText}),
          ).addToInstalled();
          throw failure;
        }),
      ),
      throwsA(same(failure)),
    );
    expect(calls, 1);
    expect(Restage.configurationGeneration, generation + 1);
    expect(InstalledWidgetLibraries.current.core.keys, ['Text']);
    expect(InstalledWidgetLibraries.current.material, isEmpty);
    expect(InstalledWidgetLibraries.current.cupertino, isEmpty);
    expect(InstalledWidgetLibraries.hasSelection, isFalse);
    expect(InstalledIconTable.current, same(RestageIconTable.none));
  });

  test('invalid shared configuration never invokes registration', () {
    var calls = 0;
    expect(
      () => Restage.configure(
        governedMeasurementTransportEnabled: true,
        governedMeasurementTransport: _UnusedTransport(),
        registerWidgets: _RegistrationCallback(
            ({required includeMaterial, required includeCupertino}) => calls++),
      ),
      throwsArgumentError,
    );
    expect(calls, 0);
  });

  testWidgets(
      'disabled full families still render a required Cupertino glyph through Material Icon',
      (tester) async {
    final fixture = stringScreenFixture(blob: rfwSourceBlob('''
import restage.material;
widget OnboardingScreen = Icon(iconCodepoint: ${CupertinoIcons.star.codePoint}, iconFontFamily: "CupertinoIcons");
'''));
    await tester.runAsync(() async {
      Restage.configure(
        analyticsEnabled: false,
        measurementEnabled: false,
        includeMaterial: false,
        includeCupertino: false,
        registerWidgets: full.kRestageWidgetRegistration,
        surfaceScreenResolver: FixedScreenResolver(fixture.hosted()),
      );
    });
    expect(InstalledWidgetLibraries.current.material.keys, ['Icon']);
    expect(InstalledWidgetLibraries.current.cupertino, isEmpty);
    await tester.pumpWidget(MaterialApp(
      home: RestageScreen<String>(
        screen: fixture.ref,
        unavailable: SurfaceScreenUnavailablePolicy.fallback(
          builder: (_, error) => Text('fallback:${error.reason.name}'),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('fallback:'), findsNothing);
    expect(find.byIcon(CupertinoIcons.star), findsOneWidget);
  });
}

void _expectCompleteFamilies(
    RestageWidgetLibraries widgets, RestageIconTable icons,
    {required bool material, required bool cupertino}) {
  expect(widgets.core, same(core.kCoreLibraryFactories));
  expect(widgets.material,
      material ? same(material_catalog.kMaterialLibraryFactories) : isEmpty);
  expect(widgets.cupertino,
      cupertino ? same(cupertino_catalog.kCupertinoLibraryFactories) : isEmpty);
  final expectedFamilies = [
    if (material) 'MaterialIcons',
    if (cupertino) 'CupertinoIcons'
  ];
  expect(icons.families.keys, expectedFamilies);
  expect(icons.mirrored.keys, expectedFamilies);
  for (final (included, family, upright, mirrored) in [
    (
      material,
      'MaterialIcons',
      material_catalog.kMaterialIconTable,
      material_catalog.kMirroredMaterialIconTable
    ),
    (
      cupertino,
      'CupertinoIcons',
      cupertino_catalog.kCupertinoIconTable,
      cupertino_catalog.kMirroredCupertinoIconTable
    ),
  ]) {
    if (!included) continue;
    expect(
        upright.keys.toSet().difference(icons.families[family]!.keys.toSet()),
        isEmpty);
    expect(icons.mirrored[family]!.keys, mirrored.keys);
    for (final entry in [upright.entries.first, upright.entries.last]) {
      expect(icons.lookUp(family, entry.key), same(entry.value));
    }
    if (mirrored.isNotEmpty) {
      final entry = mirrored.entries.first;
      expect(icons.lookUp(family, entry.key, matchTextDirection: true),
          same(entry.value));
    }
  }
}

class _RegistrationCallback implements RestageWidgetRegistration {
  _RegistrationCallback(this._callback);

  final void Function(
      {required bool includeMaterial,
      required bool includeCupertino}) _callback;

  @override
  void call({required bool includeMaterial, required bool includeCupertino}) =>
      _callback(
        includeMaterial: includeMaterial,
        includeCupertino: includeCupertino,
      );
}

class _UnusedTransport implements RestageGovernedMeasurementTransport {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
