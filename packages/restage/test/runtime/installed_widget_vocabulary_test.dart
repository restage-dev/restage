import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/flow/flow_experiment_mount.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage/src/runtime/installed_widget_vocabulary.dart';

const int _check = 0xe156;
const int _star = 0xe838;

const SurfaceVocabulary _twoSurfaces = SurfaceVocabulary(
  widgets: RestageWidgetLibraries.fromVocabulary(
    core: <String, LocalWidgetBuilder>{'Text': buildText},
    material: <String, LocalWidgetBuilder>{'Icon': buildIcon},
    cupertino: <String, LocalWidgetBuilder>{
      'CupertinoButton': buildCupertinoButton,
    },
  ),
  icons: RestageIconTable.fromFamilies(families: <String, Map<int, IconData>>{
    RestageIconTable.materialIconsFamily: <int, IconData>{_check: Icons.check},
    RestageIconTable.cupertinoIconsFamily: <int, IconData>{
      _star: CupertinoIcons.star,
    },
  }),
);

void main() {
  setUp(() {
    InstalledWidgetLibraries.reset();
    InstalledIconTable.reset();
  });

  tearDown(() {
    InstalledIconTable.reset();
    InstalledWidgetLibraries.install(RestageWidgetLibraries.builtIn());
  });

  test('nothing installed reports an empty vocabulary', () {
    final vocabulary = installedWidgetVocabulary();

    expect(vocabulary.widgetNames, isEmpty);
    expect(vocabulary.iconCodePoints, isEmpty);
  });

  test('installed widgets are reported under their own namespace', () {
    _twoSurfaces.addToInstalled();

    expect(installedWidgetVocabulary().widgetNames, {
      'restage.core:Text',
      'restage.material:Icon',
      'restage.cupertino:CupertinoButton',
    });
  });

  test('installed icons are reported per font family', () {
    _twoSurfaces.addToInstalled();

    expect(installedWidgetVocabulary().iconCodePoints, {
      RestageIconTable.materialIconsFamily: {_check},
      RestageIconTable.cupertinoIconsFamily: {_star},
    });
  });

  test('the report grows as further surfaces install', () {
    const later = SurfaceVocabulary(
      widgets: RestageWidgetLibraries.fromVocabulary(
        core: <String, LocalWidgetBuilder>{'Column': buildColumn},
      ),
    );

    _twoSurfaces.addToInstalled();
    later.addToInstalled();

    expect(
      installedWidgetVocabulary().widgetNames,
      contains('restage.core:Column'),
    );
    expect(
      installedWidgetVocabulary().widgetNames,
      contains('restage.core:Text'),
    );
  });

  test('the capability the resolver presents carries the vocabulary', () {
    _twoSurfaces.addToInstalled();

    final capability = currentInstalledCapability();

    expect(capability.vocabulary, isNotNull);
    expect(capability.vocabulary!.widgetNames, {
      'restage.core:Text',
      'restage.material:Icon',
      'restage.cupertino:CupertinoButton',
    });
    expect(capability.vocabulary!.iconCodePoints, {
      RestageIconTable.materialIconsFamily: {_check},
      RestageIconTable.cupertinoIconsFamily: {_star},
    });
    expect(capability.toJson()['vocabulary'], isNotNull);
  });

  for (final namespace in ['core', 'material', 'cupertino']) {
    test('vocabulary follows caller-owned $namespace map key changes', () {
      final builders = <String, LocalWidgetBuilder>{'Text': buildText};
      final libraries = RestageWidgetLibraries.fromVocabulary(
        core: namespace == 'core' ? builders : const {},
        material: namespace == 'material' ? builders : const {},
        cupertino: namespace == 'cupertino' ? builders : const {},
      );
      InstalledWidgetLibraries.install(libraries);
      WidgetVocabulary expected(Set<String> names) => WidgetVocabulary(
          widgetNames: {for (final name in names) 'restage.$namespace:$name'});

      _expectVocabularyChange(
          () => builders['Column'] = buildColumn, expected({'Text', 'Column'}));
      _expectVocabularyChange(
          () => builders.remove('Text'), expected({'Column'}));
      _expectVocabularyChange(() {
        builders.remove('Column');
        builders['SizedBox'] = buildSizedBox;
      }, expected({'SizedBox'}));
      _expectVocabularyChange(builders.clear, WidgetVocabulary.empty);
      expect(InstalledWidgetLibraries.current, same(libraries));
      expect(
          switch (namespace) {
            'core' => libraries.core,
            'material' => libraries.material,
            _ => libraries.cupertino,
          },
          same(builders));
    });
  }

  for (final mirrored in [false, true]) {
    test('vocabulary follows caller-owned mirrored=$mirrored icon maps', () {
      final glyphs = <int, IconData>{1: Icons.check};
      final families = <String, Map<int, IconData>>{'HostIcons': glyphs};
      final icons = RestageIconTable.fromFamilies(
        families: mirrored ? const {} : families,
        mirrored: mirrored ? families : const {},
      );
      InstalledIconTable.install(icons);
      WidgetVocabulary expected(Set<int> points) => WidgetVocabulary(
          iconCodePoints: points.isEmpty ? {} : {'HostIcons': points});

      _expectVocabularyChange(() => glyphs[2] = Icons.star, expected({1, 2}));
      _expectVocabularyChange(() => glyphs.remove(1), expected({2}));
      _expectVocabularyChange(() {
        glyphs.remove(2);
        glyphs[3] = Icons.close;
      }, expected({3}));
      _expectVocabularyChange(glyphs.clear, WidgetVocabulary.empty);
      _expectVocabularyChange(
          () => families['HostIcons'] = {4: Icons.check}, expected({4}));
      _expectVocabularyChange(() {
        families.remove('HostIcons');
        families['OtherIcons'] = {4: Icons.check};
      },
          WidgetVocabulary(iconCodePoints: {
            'OtherIcons': {4}
          }));
      _expectVocabularyChange(families.clear, WidgetVocabulary.empty);
      expect(InstalledIconTable.current, same(icons));
      expect(mirrored ? icons.mirrored : icons.families, same(families));
    });
  }

  test('implementation values do not change key vocabulary or lease identity',
      () {
    final builders = <String, LocalWidgetBuilder>{'Text': buildText};
    final glyphs = <int, IconData>{1: Icons.check};
    InstalledWidgetLibraries.install(
        RestageWidgetLibraries.fromVocabulary(core: builders));
    InstalledIconTable.install(
        RestageIconTable.fromFamilies(families: {'HostIcons': glyphs}));

    _expectVocabularyStable(() {
      builders['Text'] = buildColumn;
      glyphs[1] = Icons.star;
    });
    expect(InstalledWidgetLibraries.current.core['Text'], same(buildColumn));
    expect(InstalledIconTable.current.lookUp('HostIcons', 1), same(Icons.star));
  });

  test('mirroring duplicates and empty families share one key vocabulary', () {
    final upright = <int, IconData>{1: Icons.check};
    final mirrored = <int, IconData>{};
    final families = <String, Map<int, IconData>>{'HostIcons': upright};
    InstalledIconTable.install(RestageIconTable.fromFamilies(
      families: families,
      mirrored: {'HostIcons': mirrored},
    ));
    _expectVocabularyStable(() => mirrored[1] = Icons.star);
    _expectVocabularyStable(upright.clear);
    _expectVocabularyStable(() => families['EmptyIcons'] = {});
    _expectVocabularyChange(() {
      mirrored.remove(1);
      mirrored[2] = Icons.close;
    },
        WidgetVocabulary(iconCodePoints: {
          'HostIcons': {2}
        }));
    _expectVocabularyChange(mirrored.clear, WidgetVocabulary.empty);
    _expectVocabularyStable(() => families.remove('EmptyIcons'));
  });

  test('the whole catalog reports every built-in widget name', () {
    InstalledWidgetLibraries.install(RestageWidgetLibraries.builtIn());

    final names = installedWidgetVocabulary().widgetNames;

    expect(names, contains('restage.core:Column'));
    expect(names, contains('restage.material:Icon'));
    expect(names, contains('restage.cupertino:CupertinoButton'));
  });
}

void _expectVocabularyChange(
    void Function() change, WidgetVocabulary expected) {
  final before = currentInstalledCapability();
  final beforeJson = before.toJson();
  final beforeHash = before.contentHash;
  final seed = _captureSeed();
  change();
  final after = currentInstalledCapability();
  final nextSeed = _captureSeed();
  expect(after.vocabulary, expected);
  expect(after.contentHash, isNot(beforeHash));
  expect(nextSeed.sameIdentityAs(seed), isFalse);
  expect(before.toJson(), beforeJson);
  expect(before.contentHash, beforeHash);
  expect(currentInstalledCapability().vocabulary, same(after.vocabulary));
  expect(_captureSeed().sameIdentityAs(nextSeed), isTrue);
}

void _expectVocabularyStable(void Function() change) {
  final before = currentInstalledCapability();
  final seed = _captureSeed();
  change();
  final after = currentInstalledCapability();
  expect(after.vocabulary, same(before.vocabulary));
  expect(after.contentHash, before.contentHash);
  expect(_captureSeed().sameIdentityAs(seed), isTrue);
}

FlowMountLeaseSeed _captureSeed() => FlowMountLeaseSeed.capture(
      flow: const OnboardingFlowRef<void>(
        id: 'vocabulary-test',
        surface: Surface.onboarding,
        version: 1,
        minClient: 1,
        decodeResult: _decodeVoid,
      ),
      deliveryMode: FlowDeliveryMode.typed,
      assignmentKeyProviderGeneration: 1,
      analyticsIdentityGeneration: 1,
      configurationGeneration: 1,
      libraryGeneration: 1,
      actionGeneration: 1,
      signalGeneration: 1,
      builtInCatalogVersion: 1,
      installedLibraries: const [],
      actionBindings: const {},
      installedSignals: const {},
    );

void _decodeVoid(Map<String, dynamic> _) {}
