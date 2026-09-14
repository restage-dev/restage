import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/error/error.dart';
import 'package:build/build.dart';
import 'package:glob/glob.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:restage_codegen/builder.dart';
import 'package:restage_codegen/src/measurement/measurement_route_emission.dart';
import 'package:restage_codegen/src/neutral_part_directive.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart' as fmt;
import 'package:test/test.dart';

import 'helpers.dart';

const _fixtureRoot = 'test/fixtures/explicit_authoring';

void main() {
  group('old/new exact parity', () {
    for (final scenario in <String>[
      'linear',
      'branching',
      'completion',
      'cycle',
      'action',
      'subflow',
      'paywall',
      'compatibility',
    ]) {
      test('$scenario preserves canonical artifacts and identities', () async {
        final oldResult = await _compileScenario('$scenario/old');
        final newResult = await _compileScenario('$scenario/new');

        _expectSuccessful(oldResult, '$scenario old authoring');
        _expectSuccessful(newResult, '$scenario new authoring');

        final oldOutputs = _outputs(oldResult);
        final newOutputs = _outputs(newResult);

        final oldCanonical = _canonicalArtifacts(oldOutputs);
        final newCanonical = _canonicalArtifacts(newOutputs);
        expect(newCanonical.keys, orderedEquals(oldCanonical.keys));

        // The deprecated fixtures have no resolved Measurement source, so
        // their blobs remain unmeasured while all other bytes stay exact.
        var sawMeasuredBlob = false;
        final measurementBlobPaths = <String>{};
        for (final path in oldCanonical.keys) {
          if (path.endsWith('.rfw')) {
            expect(
              _measurementSegments(oldCanonical[path]!),
              isEmpty,
              reason: 'unresolved deprecated fixture must carry no Measurement '
                  'at $path',
            );
            if (_measurementSegments(newCanonical[path]!).isNotEmpty) {
              sawMeasuredBlob = true;
              if (newCanonical[path] != oldCanonical[path]) {
                measurementBlobPaths.add(path);
              }
            }
          }
        }
        final normalization = _MeasurementParityNormalization(
          oldArtifacts: oldCanonical,
          newArtifacts: newCanonical,
          measurementBlobPaths: measurementBlobPaths,
        );
        for (final path in oldCanonical.keys) {
          expect(
            normalization.artifact(
              path,
              newCanonical[path]!,
              newAuthoring: true,
            ),
            normalization.artifact(
              path,
              oldCanonical[path]!,
              newAuthoring: false,
            ),
            reason: 'canonical artifact drift at $path',
          );
        }
        expect(
          sawMeasuredBlob,
          isTrue,
          reason: 'canonical authoring must carry Measurement somewhere',
        );

        final oldDescriptors = _descriptorArtifacts(oldOutputs);
        final newDescriptors = _descriptorArtifacts(newOutputs);
        expect(newDescriptors.keys, orderedEquals(oldDescriptors.keys));
        for (final path in oldDescriptors.keys) {
          final oldIdentity = _stableDescriptorIdentity(oldDescriptors[path]!);
          final newIdentity = _stableDescriptorIdentity(newDescriptors[path]!);
          expect(
            newIdentity,
            containsAll(oldIdentity),
            reason: 'descriptor identity drift at $path',
          );
        }

        _expectFlowDocumentsAgree(oldCanonical, newCanonical);
      });
    }
  });

  group('Dart 3.13 primary constructors', () {
    test('fixture resolver honors explicit language overrides', () async {
      const source = 'class Point { final int x; const new(this.x); }';
      final probes = await _languageProbes({
        'at313': '// @dart=3.13\n$source',
        'at35': '// @dart=3.5\n$source',
      });

      expect(probes['at313']!.overrideLanguage, '3.13.0');
      expect(probes['at35']!.overrideLanguage, '3.5.0');
      expect(
        probes['at35']!.syntacticCodes,
        anyElement(startsWith('experiment_not_enabled')),
      );
      expect(
        probes['at313']!.syntacticCodes,
        primaryConstructorsSupported ? isEmpty : isNotEmpty,
      );
    });

    test('below-floor guarded inputs fail loudly on the shipping analyzer',
        () async {
      if (primaryConstructorsSupported) {
        markTestSkipped('only applies below analyzer 13.1.0');
        return;
      }

      for (final MapEntry(key: scenario, value: shape)
          in _primaryConstructorScenarios.entries) {
        final pair = await _compilePrimaryConstructorPair(scenario);
        _expectSuccessful(pair.classic, '$scenario classic authoring');
        final classicOutputs = _productOutputs(pair.classic);
        _expectConcretePrimaryConstructorOutput(scenario, classicOutputs);

        expect(
          pair.primary.succeeded,
          isFalse,
          reason:
              '$scenario primary authoring must fail below the parser floor',
        );
        final malformedDiagnostics = (_logs[pair.primary] ?? '')
            .split('\n')
            .where((line) => line.contains('[malformedSourceInput]'))
            .toList();
        expect(
          malformedDiagnostics,
          isNotEmpty,
          reason: '$scenario primary authoring must fail loudly',
        );
        expect(
          malformedDiagnostics,
          everyElement(
            allOf(
              contains('[malformedSourceInput] ${shape.primarySource}@'),
              contains("'primary-constructors' language feature"),
            ),
          ),
          reason: '$scenario must fail only for its primary constructor',
        );

        final primaryOutputs = _productOutputs(pair.primary);
        expect(
          primaryOutputs.keys.where((path) => path.endsWith(shape.product)),
          isEmpty,
          reason: '$scenario must not emit its product below the floor',
        );
        if (scenario == 'flow') {
          final classicScreens = _retainedFlowScreens(classicOutputs);
          final primaryScreens = _retainedFlowScreens(primaryOutputs);
          expect(classicScreens.keys, orderedEquals(_retainedFlowScreenPaths));
          expect(
            primaryScreens,
            classicScreens,
            reason: 'flow primary authoring changed a retained screen product',
          );
        }
      }
    });

    test('above-floor guarded inputs preserve product artifacts', () async {
      if (!primaryConstructorsSupported) {
        markTestSkipped(
          'requires analyzer 13.1.0 primary-constructor support',
        );
        return;
      }

      for (final scenario in _primaryConstructorScenarios.keys) {
        final pair = await _compilePrimaryConstructorPair(scenario);
        _expectPrimaryConstructorParity(scenario, pair);
      }
    });

    test('configuration controls measurement', () async {
      final disabled = await _compileScenario(
        'primary_constructor/configuration/classic',
        builders: _configurationBuilders,
      );
      _expectSuccessful(disabled, 'disabled configuration');
      final disabledOutputs = _productOutputs(disabled);
      _expectConcretePrimaryConstructorOutput('configuration', disabledOutputs);
      expect(_measurementEntries(disabledOutputs), isEmpty);

      final enabled = await _compileScenario(
        'primary_constructor/configuration/enabled',
        builders: _configurationBuilders,
      );
      _expectSuccessful(enabled, 'enabled configuration');
      final enabledOutputs = _productOutputs(enabled);
      _expectConcretePrimaryConstructorOutput('configuration', enabledOutputs);
      expect(_measurementEntries(enabledOutputs), hasLength(1));
      expect(
        enabledOutputs[_measurementIndexPath],
        isNot(disabledOutputs[_measurementIndexPath]),
      );
    });
  });
}

const _catalogPath = 'lib/src/widget_catalog/catalog.json';
const _measurementIndexPath = 'lib/generated/restage.measurement.index.json';
// Each scenario's primary-constructor source and the product it must not
// emit when that source is refused.
const _primaryConstructorScenarios =
    <String, ({String primarySource, String product})>{
  'annotated_widget': (
    primarySource: 'lib/notice_card.dart',
    product: _catalogPath,
  ),
  'flow': (
    primarySource: 'lib/onboarding/flows/welcome_flow.dart',
    product: '.flow.json',
  ),
  'structured_colocated': (
    primarySource: 'lib/notice_card.dart',
    product: _catalogPath,
  ),
  'structured_imported': (
    primarySource: 'lib/badge.dart',
    product: _catalogPath,
  ),
  'configuration': (
    primarySource: 'lib/config/bootstrap.dart',
    product: '/measurement_configuration.restage.g.dart',
  ),
};
const _retainedFlowScreenPaths = <String>[
  'assets/onboarding/screens/profile.capability.json',
  'assets/onboarding/screens/profile.rfw',
  'assets/onboarding/screens/profile.rfwtxt',
  'assets/onboarding/screens/welcome.capability.json',
  'assets/onboarding/screens/welcome.rfw',
  'assets/onboarding/screens/welcome.rfwtxt',
];

typedef _PrimaryConstructorPair = ({
  TestBuilderResult classic,
  TestBuilderResult primary,
});

typedef _LanguageProbe = ({
  String? overrideLanguage,
  List<String> syntacticCodes,
});

Future<_PrimaryConstructorPair> _compilePrimaryConstructorPair(
  String scenario,
) async {
  final builders =
      scenario == 'configuration' ? _configurationBuilders : _catalogBuilders;
  return (
    classic: await _compileScenario(
      'primary_constructor/$scenario/classic',
      builders: scenario == 'flow' ? null : builders,
    ),
    primary: await _compileScenario(
      'primary_constructor/$scenario/primary',
      builders: scenario == 'flow' ? null : builders,
    ),
  );
}

const _bundledOptions = BuilderOptions({'bundled_runtime': true});
final _catalogBuilders = <Builder>[
  userCatalogJsonBuilder(BuilderOptions.empty),
];
final _configurationBuilders = <Builder>[
  restageSourceRosterBuilder(_bundledOptions),
  userCatalogJsonBuilder(BuilderOptions.empty),
  restagePackageSurfaceCompilerBuilder(_bundledOptions),
  restageGeneratedDartBuilder(_bundledOptions),
  restageOutputsBuilder(_bundledOptions),
];

void _expectPrimaryConstructorParity(
  String scenario,
  _PrimaryConstructorPair pair,
) {
  _expectSuccessful(pair.classic, '$scenario classic authoring');
  _expectSuccessful(pair.primary, '$scenario primary authoring');
  final classicOutputs = _productOutputs(pair.classic);
  final primaryOutputs = _productOutputs(pair.primary);
  _expectConcretePrimaryConstructorOutput(scenario, classicOutputs);
  expect(primaryOutputs.keys, orderedEquals(classicOutputs.keys));
  expect(
    primaryOutputs,
    classicOutputs,
    reason: '$scenario primary authoring changed a product artifact',
  );
}

void _expectConcretePrimaryConstructorOutput(
  String scenario,
  Map<String, String> outputs,
) {
  expect(outputs, isNotEmpty, reason: '$scenario emitted no product artifacts');
  switch (scenario) {
    case 'annotated_widget':
      expect(_widgetPropertyNames(outputs, 'NoticeCard'), [
        'a',
        'onTap',
        'style',
        'analyticsId',
      ]);
    case 'flow':
      final flowPath = outputs.keys.singleWhere(
        (path) => path.endsWith('/welcome_flow.flow.json'),
      );
      final document = FlowDocumentCodec.decodeJson(
        _textProduct(outputs, flowPath),
      );
      expect(document.initial, 'welcome');
      expect(document.states.keys, ['done', 'profile', 'welcome']);
      expect(document.screenArtifacts.keys, ['profile', 'welcome']);
      expect(
        outputs.keys.where((path) => path.endsWith('.g.dart')),
        hasLength(3),
      );
    case 'structured_colocated' || 'structured_imported':
      final catalog = _jsonProduct(outputs, _catalogPath);
      final structured = catalog['structuredTypes']! as List<Object?>;
      final badge = structured.cast<Map<String, dynamic>>().singleWhere(
            (entry) => entry['name'] == 'Badge',
          );
      final fields = badge['fields']! as List<Object?>;
      expect(
        fields.cast<Map<String, dynamic>>().map((field) => field['name']),
        ['label', 'count'],
      );
    case 'configuration':
      expect(
        outputs.keys.any(
          (path) => path.endsWith('/measurement_configuration.rsbundle'),
        ),
        isTrue,
      );
      final descriptorPath = outputs.keys.singleWhere(
        (path) => path.endsWith('/measurement_configuration.restage.g.dart'),
      );
      expect(
        _textProduct(outputs, descriptorPath),
        contains('MeasurementConfigurationScreenSurface'),
      );
    default:
      fail('no concrete product assertion for $scenario');
  }
}

List<Object?> _measurementEntries(Map<String, String> outputs) =>
    _jsonProduct(outputs, _measurementIndexPath)['entries']! as List<Object?>;

Iterable<Object?> _widgetPropertyNames(
  Map<String, String> outputs,
  String widgetName,
) {
  final catalog = _jsonProduct(outputs, _catalogPath);
  final widgets = catalog['widgets']! as List<Object?>;
  final widget = widgets.cast<Map<String, dynamic>>().singleWhere(
        (entry) => entry['name'] == widgetName,
      );
  final properties = widget['properties']! as List<Object?>;
  return properties.cast<Map<String, dynamic>>().map(
        (property) => property['name'],
      );
}

Map<String, dynamic> _jsonProduct(
  Map<String, String> outputs,
  String path,
) =>
    jsonDecode(_textProduct(outputs, path))! as Map<String, dynamic>;

String _textProduct(Map<String, String> outputs, String path) {
  final value = outputs[path];
  if (value == null) throw StateError('Missing product artifact $path.');
  return utf8.decode(base64Decode(value));
}

Map<String, String> _retainedFlowScreens(Map<String, String> outputs) => {
      for (final entry in outputs.entries)
        if (entry.key.startsWith('assets/onboarding/screens/'))
          entry.key: entry.value,
    };

const _internalCompilerArtifacts = <String>{
  'assets/restage/source-index.json',
  'assets/restage/output-roster.json',
  'lib/src/surface_publication/surface_publication.compiler.json',
  'lib/src/measurement/restage.measurement.compiler.json',
  'lib/src/measurement/restage.analytics-id.control.json',
};

Map<String, String> _productOutputs(TestBuilderResult result) =>
    _encodedOutputs(
      result,
      (path) =>
          !_internalCompilerArtifacts.contains(path) &&
          (path == _catalogPath ||
              path.startsWith('lib/generated/') ||
              path.endsWith(kNeutralGeneratedPartSuffix) ||
              path.startsWith('assets/')),
    );

Map<String, String> _encodedOutputs(
  TestBuilderResult result,
  bool Function(String path) where,
) =>
    {
      for (final id in _sortedOutputs(result, where))
        id.path: base64Encode(result.readerWriter.testing.readBytes(id)),
    };

List<AssetId> _sortedOutputs(
  TestBuilderResult result,
  bool Function(String path) where,
) =>
    result.readerWriter.testing.assets
        .where((id) => id.package == 'apps_examples' && where(id.path))
        .toList()
      ..sort((left, right) => left.path.compareTo(right.path));

Future<Map<String, _LanguageProbe>> _languageProbes(
  Map<String, String> sources,
) async {
  final probes = <String, _LanguageProbe>{};
  await resolveSources<void>(
    {
      for (final name in sources.keys)
        'apps_examples|lib/$name.dart': sources[name]!,
    },
    (resolver) async {
      for (final name in sources.keys) {
        final library = await resolver.libraryFor(
          AssetId('apps_examples', 'lib/$name.dart'),
          allowSyntaxErrors: true,
        );
        final result =
            await library.session.getResolvedLibraryByElement(library);
        if (result is! ResolvedLibraryResult) {
          throw StateError('Could not resolve the language control $name.');
        }
        probes[name] = (
          overrideLanguage: library.languageVersion.override?.toString(),
          syntacticCodes: [
            for (final unit in result.units)
              for (final diagnostic in unit.diagnostics)
                if (diagnostic.diagnosticCode.type ==
                    DiagnosticType.SYNTACTIC_ERROR)
                  diagnostic.diagnosticCode.lowerCaseName,
          ],
        );
      }
    },
    resolverFor: 'apps_examples|lib/${sources.keys.first}.dart',
    rootPackage: 'apps_examples',
  );
  return probes;
}

Future<TestBuilderResult> _compileScenario(
  String scenario, {
  List<Builder>? builders,
}) async {
  final sources = _loadScenario(scenario);
  final readerWriter = await _readerWriterWith(sources);
  final logs = <LogRecord>[];
  final result = await testBuilders(
    builders ??
        [
          restageCodegenBuilder(BuilderOptions.empty),
          paywallFlowBuilder(BuilderOptions.empty),
          onboardingScreenBuilder(BuilderOptions.empty),
          onboardingFlowBuilder(BuilderOptions.empty),
          messageScreenBuilder(BuilderOptions.empty),
          messageFlowBuilder(BuilderOptions.empty),
          surveyScreenBuilder(BuilderOptions.empty),
          surveyFlowBuilder(BuilderOptions.empty),
          // The one owner of per-library generated Dart. Without it the
          // scenario emits no `.restage.g.dart` at all and every descriptor
          // assertion below passes vacuously over an empty set.
          // Produces the compiler handoff the generated-Dart builder reads;
          // without it that builder silently emits nothing.
          restagePackageSurfaceCompilerBuilder(BuilderOptions.empty),
          restageGeneratedDartBuilder(BuilderOptions.empty),
        ],
    sources,
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
    flattenOutput: true,
    onLog: logs.add,
  );
  if (!result.succeeded && logs.isNotEmpty) {
    // Keep the raw build log attached to the result for a useful assertion
    // failure without converting expected builder diagnostics into a skip.
    _logs[result] = logs.map((entry) => entry.message).join('\n');
  }
  return result;
}

final _logs = <TestBuilderResult, String>{};

void _expectSuccessful(TestBuilderResult result, String label) {
  expect(
    result.succeeded,
    isTrue,
    reason: '$label failed:\n${_logs[result] ?? '<no build log>'}',
  );
}

Map<String, String> _loadScenario(String scenario) {
  final root = Directory('$_fixtureRoot/$scenario/lib');
  expect(
    root.existsSync(),
    isTrue,
    reason: 'missing fixture root ${root.path}',
  );

  final result = <String, String>{};
  for (final entity in root.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    if (entity.path.endsWith('.g.dart')) continue;
    final relative = p.relative(entity.path, from: root.path);
    result['apps_examples|lib/$relative'] = entity.readAsStringSync();
  }
  return result;
}

Future<TestReaderWriter> _readerWriterWith(Map<String, String> sources) async {
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: 'apps_examples',
  );
  for (final entry in sources.entries) {
    readerWriter.testing.writeString(AssetId.parse(entry.key), entry.value);
  }
  return readerWriter;
}

Map<String, String> _outputs(TestBuilderResult result) => {
      ..._encodedOutputs(result, Glob('assets/**').matches),
      for (final id in _sortedOutputs(result, Glob('lib/**/*.g.dart').matches))
        id.path: result.readerWriter.testing.readString(id),
    };

Map<String, String> _canonicalArtifacts(Map<String, String> outputs) =>
    outputs.entries
        .where(
      (entry) =>
          entry.key.endsWith('.flow.json') ||
          entry.key.endsWith('.rfwtxt') ||
          entry.key.endsWith('.rfw') ||
          entry.key.endsWith('.capability.json'),
    )
        .fold(<String, String>{}, (result, entry) {
      result[entry.key] = entry.value;
      return result;
    });

Map<String, String> _descriptorArtifacts(Map<String, String> outputs) =>
    outputs.entries
        .where(
      (entry) => entry.key.endsWith(kNeutralGeneratedPartSuffix),
    )
        .fold(<String, String>{}, (result, entry) {
      result[entry.key] = entry.value;
      return result;
    });

Set<String> _stableDescriptorIdentity(String source) {
  final values = <String>{};
  final fields = RegExp(
    r'\b(id|slug|artifactPath|path|version|minClient|contractVersion|'
    r'surfaceType|surface|deliveryMode):\s*([^,\n)]+)',
  );
  for (final match in fields.allMatches(source)) {
    final key = match.group(1)!;
    final value = match.group(2)!.trim();
    final normalizedKey = switch (key) {
      'id' || 'slug' => 'identity',
      'artifactPath' || 'path' => 'artifact',
      'version' || 'contractVersion' => 'version',
      'surfaceType' || 'surface' => 'surface',
      _ => key,
    };
    values.add('$normalizedKey=$value');
  }
  return values;
}

void _expectFlowDocumentsAgree(
  Map<String, String> oldOutputs,
  Map<String, String> newOutputs,
) {
  final oldFlows = oldOutputs.entries.where(
    (entry) => entry.key.endsWith('.flow.json'),
  );
  for (final oldFlow in oldFlows) {
    final newFlow = newOutputs[oldFlow.key];
    expect(
      newFlow,
      isNotNull,
      reason: 'missing new flow ${oldFlow.key}',
    );
    final oldDocument = FlowDocumentCodec.decodeJson(
      utf8.decode(base64Decode(oldFlow.value)),
    );
    final newDocument = FlowDocumentCodec.decodeJson(
      utf8.decode(base64Decode(newFlow!)),
    );
    expect(newDocument.flow, oldDocument.flow);
    expect(newDocument.initial, oldDocument.initial);
    expect(newDocument.states.keys, orderedEquals(oldDocument.states.keys));
    expect(
      newDocument.screenArtifacts.keys,
      orderedEquals(oldDocument.screenArtifacts.keys),
    );
  }
}

/// The Measurement constructor names an artifact may carry.
const _measurementPresentationConstructors = <String>{
  'MeasurementPresented',
  'MeasurementSourcePresented',
};

/// Measurement presentation constructors found in an encoded RFW blob.
List<String> _measurementSegments(String base64Blob) {
  final library = fmt.decodeLibraryBlob(
    Uint8List.fromList(base64Decode(base64Blob)),
  );
  final found = <String>[];
  void visit(Object? node) {
    switch (node) {
      case final fmt.ConstructorCall call:
        if (_measurementPresentationConstructors.contains(call.name)) {
          found.add(call.name);
        }
        visit(call.arguments);
      case final fmt.EventHandler handler:
        visit(handler.eventArguments);
      case final fmt.WidgetBuilderDeclaration builder:
        visit(builder.widget);
      case final fmt.Loop loop:
        visit(loop.input);
        visit(loop.output);
      case final fmt.Switch node:
        visit(node.input);
        node.outputs.values.forEach(visit);
      case final Map<Object?, Object?> map:
        map.values.forEach(visit);
      case final List<Object?> list:
        list.forEach(visit);
      default:
        break;
    }
  }

  for (final widget in library.widgets) {
    visit(widget.initialState);
    visit(widget.root);
  }
  return found;
}

const _measurementDerivedHash = '<measurement-derived-hash>';
const _comparisonJson = JsonEncoder.withIndent('  ');

final class _MeasurementParityNormalization {
  _MeasurementParityNormalization({
    required Map<String, String> oldArtifacts,
    required Map<String, String> newArtifacts,
    required Set<String> measurementBlobPaths,
  })  : _oldArtifacts = oldArtifacts,
        _newArtifacts = newArtifacts,
        _measurementBlobPaths = Set.unmodifiable(measurementBlobPaths) {
    _oldFlowDocuments = _flowDocuments(_oldArtifacts);
    _newFlowDocuments = _flowDocuments(_newArtifacts);
    _measurementFlowPaths = _findMeasurementFlowPaths();
  }

  final Map<String, String> _oldArtifacts;
  final Map<String, String> _newArtifacts;
  final Set<String> _measurementBlobPaths;
  late final Map<String, FlowDocument> _oldFlowDocuments;
  late final Map<String, FlowDocument> _newFlowDocuments;
  late final Set<String> _measurementFlowPaths;

  String artifact(
    String path,
    String value, {
    required bool newAuthoring,
  }) {
    final artifacts = newAuthoring ? _newArtifacts : _oldArtifacts;
    final flowDocuments = newAuthoring ? _newFlowDocuments : _oldFlowDocuments;
    if (path.endsWith('.rfw')) {
      return _withoutMeasurementRfw(value);
    }
    if (path.endsWith('.capability.json')) {
      return _capabilitySidecar(path, value, artifacts);
    }
    if (path.endsWith('.flow.json')) {
      return _flowDocument(path, value, artifacts, flowDocuments);
    }
    return value;
  }

  Set<String> _findMeasurementFlowPaths() {
    final paths = <String>{};
    var found = true;
    while (found) {
      found = false;
      for (final entry in _oldFlowDocuments.entries) {
        final path = entry.key;
        if (paths.contains(path) ||
            _oldArtifacts[path] == _newArtifacts[path]) {
          continue;
        }
        final document = entry.value;
        final measuredScreen = document.screenArtifacts.values.any(
          (artifact) => _measurementBlobPaths.contains(
            _flowScreenBlobPath(path, artifact.path, _oldArtifacts.keys),
          ),
        );
        final measuredSubFlow =
            document.states.values.whereType<SubFlowState>().any(
                  (state) => paths.contains(
                    _subFlowArtifactPath(path, state.flow, _oldArtifacts.keys),
                  ),
                );
        if (measuredScreen || measuredSubFlow) {
          paths.add(path);
          found = true;
        }
      }
    }
    return Set.unmodifiable(paths);
  }

  String _capabilitySidecar(
    String path,
    String value,
    Map<String, String> artifacts,
  ) {
    final json = _jsonObject(value, path);
    final sidecar = CapabilitySidecar.fromJson(json);
    final blobPath = _singleArtifactPath(
      artifacts.keys,
      path.replaceFirst(RegExp(r'\.capability\.json$'), '.rfw'),
    );
    if (!_measurementBlobPaths.contains(blobPath)) {
      return _comparisonJson.convert(json);
    }
    final expectedHash = CapabilitySidecar.hashBlob(
      base64Decode(artifacts[blobPath]!),
    );
    expect(
      sidecar.blobSha256,
      expectedHash,
      reason: '$path must hash its exact blob $blobPath',
    );
    json['blobSha256'] = _measurementDerivedHash;
    return _comparisonJson.convert(json);
  }

  String _flowDocument(
    String path,
    String value,
    Map<String, String> artifacts,
    Map<String, FlowDocument> flowDocuments,
  ) {
    final document = flowDocuments[path];
    if (document == null) {
      throw StateError('Missing decoded flow document $path.');
    }
    final json = _jsonObject(value, path);
    final screenArtifacts = _jsonObjectValue(
      json['screenArtifacts'],
      '$path screenArtifacts',
    );
    for (final entry in document.screenArtifacts.entries) {
      final blobPath = _flowScreenBlobPath(
        path,
        entry.value.path,
        artifacts.keys,
      );
      if (!_measurementBlobPaths.contains(blobPath)) continue;
      final expectedHash = FlowContentHash.compute(
        base64Decode(artifacts[blobPath]!),
      );
      expect(
        entry.value.contentHash,
        expectedHash,
        reason: '$path screen ${entry.key} must hash $blobPath',
      );
      _jsonObjectValue(
        screenArtifacts[entry.key],
        '$path screenArtifacts.${entry.key}',
      )['contentHash'] = _measurementDerivedHash;
    }

    final states = _jsonObjectValue(json['states'], '$path states');
    for (final entry in document.states.entries) {
      final state = entry.value;
      if (state is! SubFlowState) continue;
      final childPath = _subFlowArtifactPath(
        path,
        state.flow,
        artifacts.keys,
      );
      if (!_measurementFlowPaths.contains(childPath)) continue;
      final expectedHash = FlowContentHash.compute(
        base64Decode(artifacts[childPath]!),
      );
      expect(
        state.contentHash,
        expectedHash,
        reason: '$path sub-flow ${entry.key} must hash $childPath',
      );
      _jsonObjectValue(
        states[entry.key],
        '$path states.${entry.key}',
      )['contentHash'] = _measurementDerivedHash;
    }
    return _comparisonJson.convert(json);
  }
}

Map<String, FlowDocument> _flowDocuments(Map<String, String> artifacts) => {
      for (final entry in artifacts.entries)
        if (entry.key.endsWith('.flow.json'))
          entry.key: FlowDocumentCodec.decodeJson(
            utf8.decode(base64Decode(entry.value)),
          ),
    };

String _withoutMeasurementRfw(String value) {
  final library = fmt.decodeLibraryBlob(
    Uint8List.fromList(base64Decode(value)),
  );
  return fmt.RemoteWidgetLibrary(
    library.imports
        .where(
          (import) => import.name.parts.join('.') != 'restage.measurement',
        )
        .toList(),
    [
      for (final widget in library.widgets)
        fmt.WidgetDeclaration(
          widget.name,
          widget.initialState,
          _strippedNode(widget.root)! as fmt.BlobNode,
        ),
    ],
  ).toString();
}

String _flowScreenBlobPath(
  String flowPath,
  String artifactPath,
  Iterable<String> paths,
) {
  final flowDirectory = p.posix.dirname(flowPath);
  final surfaceDirectory = p.posix.basename(flowDirectory) == 'flows'
      ? p.posix.dirname(flowDirectory)
      : flowDirectory;
  final String basePath;
  if (artifactPath.startsWith('assets/')) {
    basePath = artifactPath;
  } else if (isPaywallScreenArtifact(artifactPath)) {
    basePath = p.posix.join(kPaywallScreensAssetDir, artifactPath);
  } else {
    basePath = p.posix.join(surfaceDirectory, 'screens', artifactPath);
  }
  return _singleArtifactPath(paths, basePath);
}

String _subFlowArtifactPath(
  String flowPath,
  String flowId,
  Iterable<String> paths,
) =>
    _singleArtifactPath(
      paths,
      p.posix.join(p.posix.dirname(flowPath), '$flowId.flow.json'),
    );

String _singleArtifactPath(Iterable<String> paths, String basePath) {
  final matches = measurementArtifactPaths(paths, basePath).toList();
  if (matches.length != 1) {
    throw StateError(
      'Expected exactly one emitted artifact for $basePath, '
      'found ${matches.length}.',
    );
  }
  return matches.single;
}

Map<String, dynamic> _jsonObject(String value, String path) {
  final decoded = jsonDecode(utf8.decode(base64Decode(value)));
  return _jsonObjectValue(decoded, path);
}

Map<String, dynamic> _jsonObjectValue(Object? value, String path) {
  if (value is! Map<String, dynamic>) {
    throw StateError('$path must be a JSON object.');
  }
  return value;
}

Object? _strippedNode(Object? node) {
  switch (node) {
    case final fmt.ConstructorCall call:
      if (_measurementPresentationConstructors.contains(call.name)) {
        return _strippedNode(call.arguments['child']);
      }
      return fmt.ConstructorCall(call.name, {
        for (final entry in call.arguments.entries)
          entry.key: _strippedNode(entry.value),
      });
    case final fmt.EventHandler handler:
      return fmt.EventHandler(handler.eventName, {
        for (final entry in handler.eventArguments.entries)
          if (entry.key != kMeasurementRouteArgumentKeyV1)
            entry.key: _strippedNode(entry.value),
      });
    case final Map<Object?, Object?> map:
      return {
        for (final entry in map.entries) entry.key: _strippedNode(entry.value),
      };
    case final List<Object?> list:
      return [for (final item in list) _strippedNode(item)];
    default:
      return node;
  }
}
