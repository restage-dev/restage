import 'dart:convert';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:build/build.dart';
import 'package:restage_codegen/src/surface_publication/app_widget_mount_install.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  test('merging sidecars renames import prefixes without changing literals',
      () {
    final first = _factories('alpha', 'Badge');
    final second = _factories('zeta', 'Mark');
    final merged =
        AppWidgetMountFactories.merge({'zeta': second, 'alpha': first});
    final json = merged.toJson();
    expect(json['libraries'], {
      r'_$restageLibrary0': 'package:alpha/widgets.dart',
      r'_$restageLibrary1': 'package:zeta/widgets.dart',
    });
    final factories = json['factories']! as Map<String, Object?>;
    final mark = factories['zeta.widgets:Mark']! as Map<String, Object?>;
    expect(mark['source'], contains(r'_$restageLibrary1.Mark('));
    expect(mark['source'], contains(r"label: r'_$restageLibrary0'"));
    final startup = merged.registrationSource();
    expect(startup.registrations, contains('Restage.registerWidgetLibrary('));
    expect(
        startup.registrations,
        contains(
          "RestageWidgetFactory(name: 'Mark', "
          r"builder: _restage$zeta$widgets$$Mark),",
        ));
    expect(
      startup.registrations,
      contains("WidgetLibrary.custom('zeta.widgets')"),
    );
    expect(startup.registrations, contains('capabilityVersion: 3'));
    expect(startup.registrations, contains('compatibleSince: 2'));
    expect(startup.registrations, isNot(contains('builtIn')));
    expect(startup.declarations, contains(r'_restage$zeta$widgets$$Mark'));
    expect(AppWidgetMountFactories.fromJson(json).toJson(), json);
  });

  test('a single sidecar is returned unchanged', () {
    final sidecar = _factories('alpha', 'Badge');
    expect(AppWidgetMountFactories.merge({'alpha': sidecar}), same(sidecar));
  });

  test('two sidecars report both owners of a duplicate library', () {
    expect(
      () => AppWidgetMountFactories.merge(
        {
          'alpha': _factories('alpha', 'Badge', namespace: 'shared.widgets'),
          'beta': _factories('beta', 'Mark', namespace: 'shared.widgets'),
        },
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.toString(),
          'message',
          allOf(contains('shared.widgets'), contains('alpha and beta')),
        ),
      ),
    );
  });

  for (final since in [null, 1, 2]) {
    test('standalone registrations keep version defaults for $since', () {
      final registrations = _factories(
        'alpha',
        'Badge',
        compatibleSince: since,
      ).registrationSource().registrations;
      expect(registrations, contains('capabilityVersion: 3,'));
      expect(registrations.contains('compatibleSince:'), since == 2);
      expect(registrations, isNot(contains('],);')));
      expect(
        parseString(content: 'void install() { $registrations }').errors,
        isEmpty,
      );
    });
  }

  for (final since in [null, 1, 2]) {
    test('mount registrations keep version defaults for $since', () async {
      await resolveSources(
        const {
          'flutter|lib/widgets.dart': 'class Widget {} class BuildContext {}',
          'restage|lib/restage.dart': 'class DataSource {}',
          'alpha|lib/widgets.dart': 'class Badge {}',
          'app|lib/surface.dart': """
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';
import 'package:alpha/widgets.dart';
""",
        },
        (resolver) async {
          final library =
              await resolver.libraryFor(AssetId('app', 'lib/surface.dart'));
          final plan =
              _factories('alpha', 'Badge', compatibleSince: since).plan(
            ['alpha.widgets:Badge'],
            library,
            sdkPrefix: 'sdk.',
            takenNames: {},
          );
          expect(plan.problem, isNull);
          expect(
            plan.libraries,
            contains('RestageWidgetLibraryRegistration.constant('),
          );
          expect(
            plan.libraries,
            contains("library: sdk.WidgetLibrary.custom('alpha.widgets')"),
          );
          expect(plan.libraries, contains('capabilityVersion: 3,'));
          expect(plan.libraries!.contains('compatibleSince:'), since == 2);
          expect(
            parseString(content: 'const libraries = ${plan.libraries};').errors,
            isEmpty,
          );
        },
        resolverFor: 'app|lib/surface.dart',
      );
    });
  }

  test('loader reports the packages owning duplicate sidecars', () async {
    final sources = {
      'app|lib/input.dart': '',
      'app|pubspec.yaml':
          'name: app\ndependencies:\n  alpha: any\n  beta: any\n',
      'alpha|pubspec.yaml': 'name: alpha\n',
      'beta|pubspec.yaml': 'name: beta\n',
      'alpha|$kAppWidgetFactoriesPath': jsonEncode(
        _factories('constructor_types', 'Badge', namespace: 'shared.widgets')
            .toJson(),
      ),
      'beta|$kAppWidgetFactoriesPath': jsonEncode(
        _factories('constructor_types', 'Mark', namespace: 'shared.widgets')
            .toJson(),
      ),
    };
    final logs = <String>[];
    final result = await testBuilders(
      [_LoaderProbe()],
      sources,
      rootPackage: 'app',
      onLog: (record) => logs.add(record.message),
    );
    expect(result.succeeded, isFalse);
    expect(
      logs.join('\n'),
      contains('shared.widgets is declared by packages alpha and beta'),
    );
  });

  test('loader can exclude the consuming package sidecar', () async {
    final sources = {
      'app|lib/input.dart': '',
      'app|pubspec.yaml': 'name: app\ndependencies:\n  alpha: any\n',
      'alpha|pubspec.yaml': 'name: alpha\n',
      'app|$kAppWidgetFactoriesPath':
          jsonEncode(_factories('app', 'Own').toJson()),
      'alpha|$kAppWidgetFactoriesPath':
          jsonEncode(_factories('alpha', 'Badge').toJson()),
    };
    final result = await testBuilders(
      [_LoaderProbe(includeRoot: false)],
      sources,
      rootPackage: 'app',
      flattenOutput: true,
    );
    expect(result.succeeded, isTrue);
    final json = jsonDecode(
      result.readerWriter.testing
          .readString(AssetId('app', 'lib/input.output')),
    ) as Map<String, Object?>;
    expect((json['factories']! as Map).keys, ['alpha.widgets:Badge']);
  });
}

AppWidgetMountFactories _factories(
  String package,
  String name, {
  String? namespace,
  int? compatibleSince = 2,
}) {
  namespace ??= '$package.widgets';
  return AppWidgetMountFactories.fromJson({
    'libraries': {r'_$restageLibrary0': 'package:$package/widgets.dart'},
    'capabilityVersions': {namespace: 3},
    'compatibleSince': {
      if (compatibleSince != null) namespace: compatibleSince,
    },
    'factories': {
      '$namespace:$name': {
        'function': 'build$name',
        'source':
            'Widget build$name(BuildContext context, DataSource source) => '
                "_\$restageLibrary0.$name(label: r'_\$restageLibrary0');",
      },
    },
  });
}

final class _LoaderProbe implements Builder {
  _LoaderProbe({this.includeRoot = true});
  final bool includeRoot;

  @override
  Map<String, List<String>> get buildExtensions => const {
        '.dart': ['.output'],
      };

  @override
  Future<void> build(BuildStep step) async {
    final factories =
        await loadAppWidgetFactories(step, includeRoot: includeRoot);
    await step.writeAsString(
      step.inputId.changeExtension('.output'),
      jsonEncode(factories.toJson()),
    );
  }
}
