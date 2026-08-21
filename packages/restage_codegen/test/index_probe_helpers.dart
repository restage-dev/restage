// Shared fixtures for the tests that exercise the native screen source index:
// the probe that drives it, and the package-graph metadata it reads.
//
// This lives beside `helpers.dart` rather than inside it on purpose:
// `helpers.dart` is about loading workspace sources and is imported by nearly
// every test in the package, while these are used by a handful. Keeping them
// apart leaves that hot file's surface unchanged and makes the dependency
// visible at the import. Only the two names other files actually call are
// public; the rest support them from here.

import 'dart:convert';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/src/native_screen_source_index.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

import 'helpers.dart';

Future<({TestBuilderResult result, List<String> logs, String output})>
    runIndexProbe(
  Map<String, String> dartSources, {
  NativeScreenSourceConsumer consumer = NativeScreenSourceConsumer.widgetbook,
  bool validateA2uiNamespace = false,
  String? pubspec,
  Set<String> dependencies = const {
    'flutter',
    'restage',
    'rfw_catalog_schema',
  },
  bool addGeneratedPartDirective = true,
}) async {
  final pubspecBuffer = StringBuffer()
    ..writeln('name: apps_examples')
    ..writeln('dependencies:');
  for (final dependency in dependencies.toList()..sort()) {
    pubspecBuffer.writeln('  $dependency: any');
  }
  final admittedDartSources = <String, String>{
    for (final entry in dartSources.entries)
      entry.key: addGeneratedPartDirective
          ? _withGeneratedPartDirective(entry.key, entry.value)
          : entry.value,
  };
  final sources = <String, String>{
    'apps_examples|pubspec.yaml': pubspec ?? pubspecBuffer.toString(),
    'apps_examples|.dart_tool/package_graph.json': nativeScreenPackageGraph(
      dependencies,
    ),
    for (final entry in admittedDartSources.entries)
      'apps_examples|${entry.key}': entry.value,
  };
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: 'apps_examples',
  );
  for (final entry in sources.entries) {
    readerWriter.testing.writeString(AssetId.parse(entry.key), entry.value);
  }
  final logs = <String>[];
  final result = await runWithNativeScreenPackageGraphForTesting(
    packageGraphSource: nativeScreenPackageGraph(dependencies),
    body: () => testBuilder(
      _NativeScreenIndexProbeBuilder(
        consumer: consumer,
        validateA2uiNamespace: validateA2uiNamespace,
      ),
      sources,
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
      onLog: (record) => logs.add(record.message),
    ),
  );
  final outputId = AssetId(
    'apps_examples',
    'lib/native_screen_source_index.txt',
  );
  final output = result.readerWriter.testing.exists(outputId)
      ? utf8.decode(result.readerWriter.testing.readBytes(outputId))
      : '';
  return (result: result, logs: logs, output: output);
}

String _withGeneratedPartDirective(String path, String source) {
  final match = RegExp(
    r'^lib/(?:onboarding|message|survey)/screens/([^/]+)\.dart$',
  ).firstMatch(path);
  if (match == null) return source;
  final stem = match.group(1)!;
  if (source.contains('$stem.rsscreen.g.dart')) return source;
  final imports = RegExp(
    r'''^import\s+['"][^'"]+['"][^;]*;''',
    multiLine: true,
  ).allMatches(source).toList(growable: false);
  if (imports.isEmpty) return source;
  final offset = imports.last.end;
  return source.replaceRange(
    offset,
    offset,
    "\n\npart 'restage.generated/$stem.restage.g.dart';",
  );
}

String nativeScreenPackageGraph(Set<String> dependencies) => jsonEncode({
      'roots': ['apps_examples'],
      'packages': [
        {
          'name': 'apps_examples',
          'version': '0.0.0',
          'dependencies': dependencies.toList()..sort(),
          'devDependencies': <String>[],
        },
      ],
    });

final class _NativeScreenIndexProbeBuilder implements Builder {
  const _NativeScreenIndexProbeBuilder({
    required this.consumer,
    required this.validateA2uiNamespace,
  });

  final NativeScreenSourceConsumer consumer;
  final bool validateA2uiNamespace;

  @override
  Map<String, List<String>> get buildExtensions => const {
        r'$lib$': ['native_screen_source_index.txt'],
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    final index = await loadNativeScreenSourceIndex(
      buildStep,
      consumer: consumer,
      validateA2uiNamespace: validateA2uiNamespace,
    );
    final output = StringBuffer();
    for (final screen in index.screens) {
      final widgetbookAllValues = screen
          .widgetbookTargetConfig.properties.entries
          .where((entry) => entry.value.allValues)
          .map((entry) => entry.key)
          .join(',');
      final events = screen.events
          .map(
            (event) => '${event.fieldName}:${event.id}:'
                '${event.payloadType.getDisplayString()}',
          )
          .join(',');
      output
        ..writeln('id=${screen.id}')
        ..writeln('version=${screen.version}')
        ..writeln('minClient=${screen.minClient}')
        ..writeln('identity=${screen.classIdentity}')
        ..writeln('source=${screen.sourceAsset.path}')
        ..writeln('declaration=${screen.declarationSourcePath}')
        ..writeln('import=${screen.importUri}')
        ..writeln('imports=${screen.importUris.join(',')}')
        ..writeln(
          'description=${screen.description?.replaceAll('\n', r'\n')}',
        )
        ..writeln(
          'inputs=${screen.constructorFacts.inputs.map((input) {
            return '${input.name}:${input.required ? 'required' : 'optional'}';
          }).join(',')}',
        )
        ..writeln(
          'defaults=${screen.constructorFacts.inputs.map((input) {
                final value = input.constructorDefault.reconstructedValue;
                return value == null
                    ? null
                    : '${input.name}:${_displayDefault(value)}';
              }).whereType<String>().join(',')}',
        )
        ..writeln('a2uiUsage=${screen.a2uiTargetConfig.usage}')
        ..writeln(
          'widgetbookMaxStories=${screen.widgetbookTargetConfig.maxStories}',
        )
        ..writeln(
          'widgetbookAllValues=$widgetbookAllValues',
        )
        ..writeln('events=$events');
    }
    await buildStep.writeAsString(
      AssetId(
        buildStep.inputId.package,
        'lib/native_screen_source_index.txt',
      ),
      output.toString(),
    );
  }
}

String _displayDefault(DartConstValue value) => switch (value) {
      DartConstNull() => 'null',
      DartConstScalar(:final value) => '$value',
      DartConstReference(:final owner, :final member) =>
        owner == null ? member : '$owner.$member',
      _ => value.runtimeType.toString(),
    };
