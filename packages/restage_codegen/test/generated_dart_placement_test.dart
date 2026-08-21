import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:path/path.dart' as p;
import 'package:restage_codegen/src/authored_library_predicate.dart';
import 'package:restage_codegen/src/generated_dart_builder.dart';
import 'package:restage_codegen/src/neutral_part_directive.dart';
import 'package:restage_codegen/src/surface_publication/output_placement.dart';
import 'package:restage_codegen/src/surface_publication/package_surface_compiler_builder.dart';
import 'package:restage_codegen/src/widgetbook/widgetbook_story_builder.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'helpers.dart';

/// The three placement modes the frozen contract names, with the exact
/// generated-Dart path each produces for one authored library.
const String _library = 'lib/features/welcome.dart';

RestageOutputPlacementPlan _plan(Map<String, dynamic> config) =>
    RestageOutputPlacementPlan.fromBuilderOptions(BuilderOptions(config));

final Map<String, RestageOutputPlacementPlan> _plans = {
  'default': _plan(const {}),
  'adjacent': _plan(const {'source_output_layout': 'adjacent'}),
  'centralized': _plan(const {'dart_output_root': 'lib/generated/restage'}),
};

const Map<String, String> _expectedPartPath = {
  'default': 'lib/features/restage.generated/welcome.restage.g.dart',
  'adjacent': 'lib/features/welcome.restage.g.dart',
  'centralized': 'lib/generated/restage/features/welcome.restage.g.dart',
};

const Map<String, String> _expectedPartUri = {
  'default': 'restage.generated/welcome.restage.g.dart',
  'adjacent': 'welcome.restage.g.dart',
  'centralized': '../generated/restage/features/welcome.restage.g.dart',
};

void main() {
  group('canonical filename family', () {
    for (final mode in _plans.keys) {
      test('$mode places the one neutral part at its canonical name', () {
        expect(
          neutralPartPath(_plans[mode]!, _library),
          _expectedPartPath[mode],
        );
        expect(
          neutralPartPath(_plans[mode]!, _library),
          endsWith('/welcome$kNeutralGeneratedPartSuffix'),
          reason: 'the filename is identical in every placement mode; only '
              'the parent path changes',
        );
      });
    }
  });

  group('declared build extensions', () {
    for (final mode in _plans.keys) {
      test('$mode resolves the same path the plan resolves', () {
        final extensions =
            RestageGeneratedDartBuilder(BuilderOptions(_configFor(mode)))
                .buildExtensions;
        expect(extensions, hasLength(1));
        final input = extensions.keys.single;
        final output = extensions.values.single.single;
        expect(
          _applyTemplate(input: input, output: output, source: _library),
          _expectedPartPath[mode],
          reason: 'the declared template and the resolved placement must not '
              'drift; build_runner reads the template, emitters read the plan',
        );
      });

      test('$mode references each capture group exactly once per output', () {
        final extensions =
            RestageGeneratedDartBuilder(BuilderOptions(_configFor(mode)))
                .buildExtensions;
        final output = extensions.values.single.single;
        for (final group in const ['{{dir}}', '{{file}}', '{{source}}']) {
          expect(
            group.allMatches(output).length,
            lessThanOrEqualTo(1),
            reason: 'package:build rejects an output template that references '
                'one capture group more than once',
          );
        }
      });
    }
  });

  group('exact part-URI diagnostics', () {
    for (final mode in _plans.keys) {
      test('$mode names the exact required URI when the part is missing', () {
        final issues = neutralPartDirectiveIssues(
          unit: parseUnit("import 'package:restage/restage.dart';\n"),
          libraryPath: _library,
          plan: _plans[mode]!,
        );
        expect(issues, hasLength(1));
        expect(
          issues.single.message,
          "Missing `part '${_expectedPartUri[mode]}';` directive.",
        );
      });

      test('$mode accepts the exact required URI', () {
        final issues = neutralPartDirectiveIssues(
          unit: parseUnit("part '${_expectedPartUri[mode]}';\n"),
          libraryPath: _library,
          plan: _plans[mode]!,
        );
        expect(issues, isEmpty);
      });
    }

    test('a superseded per-kind part names its replacement', () {
      final issues = neutralPartDirectiveIssues(
        unit: parseUnit("part 'welcome.rsscreen.g.dart';\n"),
        libraryPath: _library,
        plan: _plans['default']!,
      );
      expect(issues, hasLength(1));
      expect(
        issues.single.message,
        allOf(
          contains("part 'welcome.rsscreen.g.dart'"),
          contains("part 'restage.generated/welcome.restage.g.dart'"),
        ),
      );
    });
  });

  group('Widgetbook story placement', () {
    for (final mode in _plans.keys) {
      test('$mode places story source beside the neutral part', () {
        final story = widgetbookStoryPath(
          _plans[mode]!,
          declarationSourcePath: _library,
          className: 'PromoBanner',
        );
        expect(
          story,
          '${_expectedPartPath[mode]!.substring(
            0,
            _expectedPartPath[mode]!.lastIndexOf('/'),
          )}/promo_banner.stories.dart',
        );
      });
    }
  });

  group('reserved input exclusion', () {
    test('no source inside a collection directory is an authored input', () {
      expect(
        isAuthoredDartLibraryAsset(
          AssetId('app', 'lib/features/restage.generated/welcome.dart'),
        ),
        isFalse,
      );
      expect(
        isAuthoredDartLibraryAsset(AssetId('app', _library)),
        isTrue,
        reason: 'an ordinary authored library is unaffected',
      );
    });

    test('a directory merely named generated stays an authored input', () {
      expect(
        isAuthoredDartLibraryAsset(
          AssetId('app', 'lib/generated/welcome.dart'),
        ),
        isTrue,
      );
    });
  });

  test('exactly one declared builder owns the generated Dart family', () {
    final root = loadYaml(File('build.yaml').readAsStringSync()) as YamlMap;
    final builders = root['builders'] as YamlMap;
    final owners = <String>[
      for (final builder in builders.entries)
        for (final extension
            in ((builder.value as YamlMap)['build_extensions'] as YamlMap)
                .entries)
          for (final output in extension.value as YamlList)
            if ((output as String).endsWith(kNeutralGeneratedPartSuffix))
              builder.key as String,
    ];
    expect(
      owners,
      ['generated_dart'],
      reason: 'two builders claiming one generated part is a build_runner '
          'conflict, not a runtime race',
    );
  });

  group('materialization', () {
    for (final mode in const ['default', 'adjacent']) {
      test('$mode writes one part carrying screen and flow content', () async {
        const screen = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@Screen(surface: Surface.general)
final class FeatureAnnouncement extends StatelessWidget {
  const FeatureAnnouncement({super.key});

  static const dismiss = SurfaceEvent<void>('dismiss');

  @override
  Widget build(BuildContext context) => const Text('Announcement');
}
''';
        const flow = '''
import 'package:restage/restage.dart';

import '../features/announcement.dart';

@FlowGraph(surface: Surface.general)
const launch = FlowDefinition(
  start: FeatureAnnouncement,
  transitions: [
    Transition.complete(FeatureAnnouncement.dismiss),
  ],
);
''';
        final plan = _plans[mode]!;
        final sources = <String, String>{
          'apps_examples|lib/features/announcement.dart':
              _withPart(screen, plan, 'lib/features/announcement.dart'),
          'apps_examples|lib/journeys/launch.dart':
              _withPart(flow, plan, 'lib/journeys/launch.dart'),
        };
        final readerWriter = await readerWriterWithFilesystemSources(
          rootPackage: 'apps_examples',
        );
        final options = BuilderOptions(_configFor(mode));

        final compiled = await testBuilder(
          PackageSurfaceCompilerBuilder(options),
          sources,
          rootPackage: 'apps_examples',
          readerWriter: readerWriter,
          flattenOutput: true,
        );
        expect(compiled.succeeded, isTrue, reason: compiled.errors.join('\n'));

        final generated = await testBuilder(
          RestageGeneratedDartBuilder(options),
          sources,
          rootPackage: 'apps_examples',
          readerWriter: readerWriter,
          flattenOutput: true,
        );
        expect(
          generated.succeeded,
          isTrue,
          reason: generated.errors.join('\n'),
        );

        final screenPart = await readerWriter.readAsString(
          AssetId(
            'apps_examples',
            neutralPartPath(plan, 'lib/features/announcement.dart'),
          ),
        );
        expect(
          screenPart,
          startsWith(
            "part of '${_partOfUri(plan, 'lib/features/announcement.dart')}';",
          ),
          reason: 'the `part of` URI is resolved relative to the part file, '
              'so it changes with placement',
        );
        // The categorized screen's generated handle. Was `contains('Descriptor')`,
        // which named the neutral holder a categorized screen no longer emits;
        // the handle is both present today and specific to this screen.
        expect(screenPart, contains('featureAnnouncementRef'));

        final flowPart = await readerWriter.readAsString(
          AssetId(
            'apps_examples',
            neutralPartPath(plan, 'lib/journeys/launch.dart'),
          ),
        );
        expect(
          flowPart,
          startsWith(
            "part of '${_partOfUri(plan, 'lib/journeys/launch.dart')}';",
          ),
        );
      });
    }
  });
}

/// The `part of` URI a generated part must declare to point back at its
/// authored library, resolved relative to the part's own directory.
String _partOfUri(RestageOutputPlacementPlan plan, String libraryPath) {
  final part = neutralPartPath(plan, libraryPath);
  final relative = p.posix.relative(
    libraryPath,
    from: p.posix.dirname(part),
  );
  return relative;
}

CompilationUnit parseUnit(String source) =>
    parseString(content: source, throwIfDiagnostics: false).unit;

Map<String, dynamic> _configFor(String mode) => switch (mode) {
      'adjacent' => const {'source_output_layout': 'adjacent'},
      'centralized' => const {'dart_output_root': 'lib/generated/restage'},
      _ => const <String, dynamic>{},
    };

String _withPart(
  String source,
  RestageOutputPlacementPlan plan,
  String libraryPath,
) {
  final lines = source.split('\n');
  final lastImport = lines.lastIndexWhere((line) => line.startsWith('import '));
  lines.insert(
    lastImport + 1,
    "\npart '${neutralPartUri(plan, libraryPath)}';",
  );
  return lines.join('\n');
}

/// Applies a `package:build` extension template pair to one source path.
String _applyTemplate({
  required String input,
  required String output,
  required String source,
}) {
  if (input == 'lib/{{source}}.dart') {
    final captured = source.substring(
      'lib/'.length,
      source.length - '.dart'.length,
    );
    return output.replaceAll('{{source}}', captured);
  }
  final separator = source.lastIndexOf('/');
  return output
      .replaceAll('{{dir}}', source.substring(0, separator))
      .replaceAll(
        '{{file}}',
        source.substring(separator + 1, source.length - '.dart'.length),
      );
}
