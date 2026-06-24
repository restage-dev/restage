import 'dart:collection';
import 'dart:convert';
import 'dart:isolate';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:package_config/package_config.dart';
import 'package:restage_codegen/src/custom_widget_blueprint.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/onboarding/onboarding_source_visitor.dart';
import 'package:restage_codegen/src/source_visitor.dart';
import 'package:restage_codegen/src/theme_recognition.dart';
import 'package:restage_codegen/src/type_inference.dart' as type_inference;
import 'package:restage_codegen/src/widget_classification.dart';
import 'package:restage_codegen/src/widget_classifier.dart';
import 'package:restage_codegen/src/widget_visitor.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// The library URI under which [parseExpressionFromSourceForTest] mounts a
/// synthetic source — its value-type stubs AND (for the native-decompose
/// tests) its decompose-recipe identities both live here.
const String kSyntheticProbeLibraryUri =
    'package:restage_codegen/_expr_probe.dart';

/// Framework-library predicate for `ExpressionTranslator.forTesting` in the
/// synthetic-catalog tests: the strict framework origins
/// ([isFrameworkValueTypeLibrary] — `dart:` / `package:flutter/`) PLUS the
/// synthetic probe URI ([kSyntheticProbeLibraryUri]). It lets a synthetic test
/// DECLARE that its `_expr_probe.dart` stubs ARE its framework value types —
/// making the framework set explicit rather than relying on the absence of the
/// production value-substitution gate (which the production-constructor sweep
/// tests prove deferring a non-framework look-alike). A customer look-alike in
/// any OTHER package is still rejected.
bool syntheticFrameworkLibrary(Element? element) =>
    isFrameworkValueTypeLibrary(element) ||
    element?.library?.identifier == kSyntheticProbeLibraryUri;

/// Empty merged catalog for translator tests that don't exercise
/// catalog-aware logic.
const Catalog kEmptyCatalog = Catalog(
  schemaVersion: kSupportedSchemaVersion,
  generatedAt: '1970-01-01T00:00:00Z',
  libraries: <WidgetLibrary, LibraryInfo>{},
  widgets: <WidgetEntry>[],
);

/// Builds a [WidgetEntry] with sensible defaults — most tests only
/// vary `name` and `properties`. The default `flutterType` synthesises
/// from the entry name so tests that exercise `flutterType` matching
/// can override explicitly.
WidgetEntry entry({
  required String name,
  required List<PropertyEntry> properties,
  WidgetLibrary library = WidgetLibrary.core,
  WidgetCategory category = WidgetCategory.layout,
  ChildrenSlot childrenSlot = ChildrenSlot.none,
  List<WidgetEventName> fires = const <WidgetEventName>[],
  String? flutterType,
  List<DecompositionRecipe> decomposes = const [],
  int sinceVersion = kBaselineCatalogVersion,
  String? deprecatedSince,
}) =>
    WidgetEntry(
      wireId: WireId.unallocatedWidget,
      name: name,
      library: library,
      category: category,
      description: '',
      flutterType: flutterType ?? 'package:test_fixture/$name.dart#$name',
      childrenSlot: childrenSlot,
      fires: fires,
      properties: properties,
      decomposes: decomposes,
      sinceVersion: sinceVersion,
      deprecatedSince: deprecatedSince,
    );

/// Builds a [PropertyEntry] with the always-required `description`
/// stubbed empty.
PropertyEntry prop(
  String name,
  PropertyType type, {
  bool required = false,
  bool positional = false,
}) =>
    PropertyEntry(
      wireId: WireId.unallocatedProperty,
      name: name,
      type: type,
      description: '',
      required: required,
      positional: positional,
    );

/// Builds a single-library [Catalog] containing `widgets`. Defaults to
/// the `restage.core` library because most tests focus on a single
/// library; cross-library tests pass `library` explicitly.
Catalog catalogWith(
  List<WidgetEntry> widgets, {
  WidgetLibrary library = WidgetLibrary.core,
  List<StructuredEntry> structuredTypes = const [],
}) =>
    Catalog(
      schemaVersion: kSupportedSchemaVersion,
      generatedAt: '1970-01-01T00:00:00Z',
      libraries: <WidgetLibrary, LibraryInfo>{
        library: const LibraryInfo(version: '0.1.0'),
      },
      widgets: widgets,
      structuredTypes: structuredTypes,
    );

/// Builds a minimal [StructuredEntry] for tests that only need the catalog's
/// `structuredTypes` to advertise a decompose-able type by [name] (the
/// classifier recognises a structured-value construction by matching the
/// constructed class name against `catalog.structuredTypes`). Fields and
/// variants are stubbed empty — only `name` is read by the recognition path.
StructuredEntry structuredEntry(
  String name, {
  WidgetLibrary library = WidgetLibrary.core,
}) =>
    StructuredEntry(
      wireId: WireId.unallocatedStructured,
      name: name,
      library: library,
      description: '',
      sourceType: 'package:test_fixture/$name.dart#$name',
      fields: const [],
      variants: const [ConstructorVariant(wireId: WireId.unallocatedVariant)],
    );

/// Stub declarations of `PaywallSource`, `StatelessWidget`, `Widget`, and
/// `BuildContext` for tests that author paywall fixtures inline. The real
/// types live in `restage` and `flutter`; `restage_codegen`
/// identifies them by name only, so a tiny in-file stub is enough to drive
/// the visitor and the translator.
const String kStubAnnotationsAndBases = '''
  class PaywallSource {
    const PaywallSource({required this.id, this.slot});
    final String id;
    final String? slot;
  }

  class StatelessWidget {
    const StatelessWidget();
  }

  class Widget {}
  class BuildContext {}
''';

/// Stub framework base classes for custom-widget classifier fixtures.
/// `restage_codegen` identifies `StatelessWidget` / `StatefulWidget` / `State`
/// by name only, so these tiny stubs are enough to drive the classifier; each
/// fixture adds its own catalog-widget stubs (`Container`, `Text`, …) on top.
const String kClassifierStubs = '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

class Widget { const Widget(); }
class BuildContext {}
abstract class StatelessWidget extends Widget { const StatelessWidget(); }
abstract class StatefulWidget extends Widget { const StatefulWidget(); }
abstract class State<T extends StatefulWidget> {
  late T widget;
  Widget build(BuildContext context);
  void setState(void Function() fn) {}
}
''';

/// Fixture preamble for classifier tests that need to exercise theme reads
/// against the real `package:flutter/material.dart` `Theme` /
/// `DefaultTextStyle` classes. The codegen-side theme-read recognition
/// requires the resolved `.of(...)` method's library URI to start with
/// `package:flutter/` (so a customer's lookalike `class Theme` does not
/// silently produce a wrong `data.theme.*` reference) — synthetic test
/// inputs that stub `Theme` locally cannot satisfy that gate.
const String kFlutterClassifierStubs = '''
import 'package:flutter/material.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
''';

const String _kRootPackage = 'restage_codegen';

/// Runs the source visitor against a map of synthetic source files
/// (keyed `'lib/foo.dart'`-style) and returns the merged [VisitorResult].
///
/// Each test source is expected to define its own stub `class PaywallSource`
/// and `class StatelessWidget` since `restage_codegen` does not depend on
/// `restage`. The visitor identifies these annotations and base
/// classes by string-matching their declared names.
Future<VisitorResult> runVisitorOn(
  Map<String, String> sources, {
  String packageName = 'apps_examples',
}) async {
  final results = await _runOnLibraries<VisitorResult>(
    sources,
    packageName: packageName,
    onLibrary: visitPaywallSources,
  );
  return results.fold<VisitorResult>(
    VisitorResult(sources: const [], issues: const []),
    (acc, r) => VisitorResult(
      sources: [...acc.sources, ...r.sources],
      issues: [...acc.issues, ...r.issues],
    ),
  );
}

/// Runs the onboarding source visitor against a map of synthetic source files
/// (keyed `'lib/foo.dart'`-style) and returns the merged result.
Future<OnboardingVisitorResult> runOnboardingVisitorOn(
  Map<String, String> sources, {
  String packageName = 'apps_examples',
}) async {
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: packageName,
    includeFlutter: _importsFlutter(sources.values),
  );
  final assetMap = <String, String>{
    for (final entry in sources.entries)
      '$packageName|${entry.key}': entry.value,
  };
  for (final entry in assetMap.entries) {
    readerWriter.testing.writeString(AssetId.parse(entry.key), entry.value);
  }
  final allowedAssetIds = {
    for (final key in assetMap.keys) AssetId.parse(key),
  };
  final results = <OnboardingVisitorResult>[];
  await testBuilder(
    _CapturingBuilder(
      (library, assetId) async {
        results.add(await visitOnboardingSources(library, assetId));
      },
      allowedAssetIds: allowedAssetIds,
    ),
    assetMap,
    rootPackage: packageName,
    readerWriter: readerWriter,
  );
  return results.fold<OnboardingVisitorResult>(
    OnboardingVisitorResult(sources: const [], issues: const []),
    (acc, r) => OnboardingVisitorResult(
      sources: [...acc.sources, ...r.sources],
      issues: [...acc.issues, ...r.issues],
    ),
  );
}

/// Runs the customer-widget visitor against a map of synthetic source files
/// (keyed `'lib/foo.dart'`-style) and returns the merged
/// [WidgetVisitorResult].
///
/// Workspace package sources (notably `restage_shared`) are made available
/// to the analyzer so `@RestageWidget` annotations can be const-evaluated.
Future<WidgetVisitorResult> runWidgetVisitorOn(
  Map<String, String> sources, {
  String packageName = 'apps_examples',
}) async {
  final results = await _runOnLibraries<WidgetVisitorResult>(
    sources,
    packageName: packageName,
    onLibrary: (library, assetId) async =>
        visitRestageWidgets(library, assetId),
  );
  return results.fold<WidgetVisitorResult>(
    WidgetVisitorResult(widgets: const [], issues: const []),
    (acc, r) => WidgetVisitorResult(
      widgets: [...acc.widgets, ...r.widgets],
      issues: [...acc.issues, ...r.issues],
    ),
  );
}

/// Resolves [source] as a synthetic Dart library and returns the
/// [PropertyType] inferred for the field named [fieldName] on the first
/// class that declares it.
///
/// Returns `null` if the field is not found or its static type does not
/// map to a supported catalog property type.
Future<PropertyType?> inferTypeFromSource(
  String source, {
  required String fieldName,
}) async {
  PropertyType? result;
  await _runOnLibraries<void>(
    {'lib/_type_probe.dart': source},
    packageName: _kRootPackage,
    onLibrary: (library, assetId) async {
      for (final cls in library.classes) {
        for (final field in cls.fields) {
          if (field.name == fieldName) {
            result = type_inference.inferPropertyType(field.type);
            return;
          }
        }
      }
    },
  );
  return result;
}

/// Runs [onLibrary] on every resolved library produced from [sources] under
/// [packageName]. Shared scaffolding for the per-visitor `runXxxOn`
/// helpers above.
Future<List<T>> _runOnLibraries<T>(
  Map<String, String> sources, {
  required String packageName,
  required Future<T> Function(LibraryElement library, AssetId assetId)
      onLibrary,
}) async {
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: _kRootPackage,
    includeFlutter: _importsFlutter(sources.values),
  );
  final assetMap = <String, String>{
    for (final entry in sources.entries)
      '$packageName|${entry.key}': entry.value,
  };
  for (final entry in assetMap.entries) {
    readerWriter.testing.writeString(AssetId.parse(entry.key), entry.value);
  }
  final allowedAssetIds = {
    for (final key in assetMap.keys) AssetId.parse(key),
  };
  final results = <T>[];
  await testBuilder(
    _CapturingBuilder(
      (library, assetId) async {
        results.add(await onLibrary(library, assetId));
      },
      allowedAssetIds: allowedAssetIds,
    ),
    assetMap,
    rootPackage: packageName,
    readerWriter: readerWriter,
  );
  return results;
}

/// Parses [expression] inside a synthetic top-level function body and
/// returns the parsed, unresolved [Expression] AST node. Used by the expression
/// translator tests to feed real AST nodes through the translator.
Future<Expression> parseExpressionForTest(String expression) {
  return Future.sync(() {
    final parsed = parseString(
      content: 'Object x() => $expression;',
      path: 'lib/_expr_probe.dart',
    );
    final declaration = parsed.unit.declarations
        .whereType<FunctionDeclaration>()
        .firstWhere((declaration) => declaration.name.lexeme == 'x');
    final body = declaration.functionExpression.body;
    if (body is ExpressionFunctionBody) {
      return body.expression;
    }
    throw StateError('Failed to parse expression: $expression');
  });
}

/// Parses a complete [source] file and returns the **resolved** expression
/// returned by the top-level function named `x`. Allows tests to inline stub
/// declarations (e.g. helper-function stubs) so that the analyzer resolves
/// calls to those stubs within the `package:restage_codegen` library URI,
/// making `element.library.identifier` available on resolved AST nodes.
///
/// The [source] must define `Object x() => <expression>;` (expression body).
/// The returned node is fully type-resolved: element references on AST
/// nodes (e.g. `MethodInvocation.methodName.element`) are populated.
///
/// [rootPackage] mounts the synthetic source under that package's asset
/// namespace; defaults to `restage_codegen` (pure Dart). Tests that need
/// real `package:flutter/...` resolution must override to `apps_examples`
/// (which has Flutter in its pubspec) — the codegen-side theme-read
/// recognition requires resolved `Theme.of` / `DefaultTextStyle.of` to
/// originate from `package:flutter/`.
Future<Expression> parseExpressionFromSourceForTest(
  String source, {
  String rootPackage = _kRootPackage,
}) async {
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: rootPackage,
    includeFlutter: _importsFlutter([source]),
    includeIntl: _importsIntl([source]),
  );
  final assetKey = '$rootPackage|lib/_expr_probe.dart';
  readerWriter.testing.writeString(AssetId.parse(assetKey), source);

  Expression? result;
  await testBuilder(
    _CapturingBuilder(
      (library, assetId) async {
        final fn = library.topLevelFunctions.firstWhere((f) => f.name == 'x');
        // Use the *resolved* library so that element references (e.g.
        // MethodInvocation.methodName.element) are populated. This is
        // necessary for helper-call recognition tests where the translator
        // reads element.library.identifier to match against the registry.
        final resolvedResult =
            await library.session.getResolvedLibraryByElement(library);
        if (resolvedResult is! ResolvedLibraryResult) return;
        final node =
            resolvedResult.getFragmentDeclaration(fn.firstFragment)?.node;
        if (node is FunctionDeclaration) {
          final body = node.functionExpression.body;
          if (body is ExpressionFunctionBody) {
            result = body.expression;
          }
        }
      },
      allowedAssetIds: {AssetId.parse(assetKey)},
    ),
    {assetKey: source},
    rootPackage: rootPackage,
    readerWriter: readerWriter,
  );
  if (result == null) {
    throw StateError(
      'Failed to parse expression from source. '
      'Ensure the source defines `Object x() => <expression>;`.',
    );
  }
  return result!;
}

/// Builds a [TestReaderWriter] pre-populated with the on-disk source files
/// fixture analysis needs.
///
/// The byte map is read once and cached for the process lifetime; each call
/// returns a fresh writer pre-populated from that cache. The cache is seeded
/// from the public libraries and data files the synthetic fixtures import or
/// read, then follows Dart import/export/part directives recursively.
/// Dart-only fixtures skip Flutter sources unless [includeFlutter] is true.
Future<TestReaderWriter> readerWriterWithFilesystemSources({
  required String rootPackage,
  bool? includeFlutter,
  bool includeIntl = false,
}) async {
  final writer = TestReaderWriter(rootPackage: rootPackage);
  _writeSources(writer, await _cachedDartOnlyWorkspaceSources());
  if (rootPackage == 'apps_examples') {
    _writeSources(writer, await _cachedAppFixtureWorkspaceSources());
  }
  if (includeFlutter ?? rootPackage == 'apps_examples') {
    _writeSources(writer, await _cachedFlutterOnlyWorkspaceSources());
  }
  if (includeIntl) {
    _writeSources(writer, await _cachedIntlWorkspaceSources());
  }
  return writer;
}

void _writeSources(
  TestReaderWriter writer,
  Map<AssetId, List<int>> cached,
) {
  for (final entry in cached.entries) {
    writer.testing.writeBytes(entry.key, entry.value);
  }
}

bool _importsFlutter(Iterable<String> sources) {
  return sources.any((source) => source.contains('package:flutter/'));
}

/// True when any fixture imports `package:intl/` — the recognizer tests need
/// the real intl sources loaded so `NumberFormat` constructions resolve to the
/// `package:intl/` element (the element-gated recognition path).
bool _importsIntl(Iterable<String> sources) {
  return sources.any((source) => source.contains('package:intl/'));
}

Future<Map<AssetId, List<int>>>? _dartOnlyWorkspaceSourcesFuture;
Future<Map<AssetId, List<int>>>? _flutterOnlyWorkspaceSourcesFuture;
Future<Map<AssetId, List<int>>>? _appFixtureWorkspaceSourcesFuture;
Future<Map<AssetId, List<int>>>? _intlWorkspaceSourcesFuture;

const Map<String, List<String>> _dartOnlyWorkspaceSourceEntrypoints = {
  'rfw_catalog_schema': ['lib/rfw_catalog_schema.dart'],
};

const Map<String, List<String>> _appFixtureWorkspaceSourceEntrypoints = {
  'restage': ['lib/restage.dart'],
};

const Map<String, List<String>> _flutterWorkspaceSourceEntrypoints = {
  'flutter': ['lib/material.dart', 'lib/widgets.dart', 'lib/cupertino.dart'],
};

const Map<String, List<String>> _intlWorkspaceSourceEntrypoints = {
  'intl': ['lib/intl.dart'],
};

const Map<String, List<String>> _workspaceDataEntrypoints = {
  'restage_core': ['lib/src/widget_catalog/catalog.json'],
  'restage_material': ['lib/src/widget_catalog/catalog.json'],
  'restage_cupertino': ['lib/src/widget_catalog/catalog.json'],
};

Future<Map<AssetId, List<int>>> _cachedDartOnlyWorkspaceSources() {
  return _dartOnlyWorkspaceSourcesFuture ??= _loadWorkspaceSources(
    sourceEntrypoints: _dartOnlyWorkspaceSourceEntrypoints,
    dataEntrypoints: _workspaceDataEntrypoints,
  );
}

Future<Map<AssetId, List<int>>> _cachedFlutterOnlyWorkspaceSources() {
  return _flutterOnlyWorkspaceSourcesFuture ??= _loadWorkspaceSources(
    sourceEntrypoints: _flutterWorkspaceSourceEntrypoints,
    dataEntrypoints: const {},
  );
}

Future<Map<AssetId, List<int>>> _cachedAppFixtureWorkspaceSources() {
  return _appFixtureWorkspaceSourcesFuture ??= _loadWorkspaceSources(
    sourceEntrypoints: _appFixtureWorkspaceSourceEntrypoints,
    dataEntrypoints: const {},
  );
}

Future<Map<AssetId, List<int>>> _cachedIntlWorkspaceSources() {
  return _intlWorkspaceSourcesFuture ??= _loadWorkspaceSources(
    sourceEntrypoints: _intlWorkspaceSourceEntrypoints,
    dataEntrypoints: const {},
  );
}

Future<Map<AssetId, List<int>>> _loadWorkspaceSources({
  required Map<String, List<String>> sourceEntrypoints,
  required Map<String, List<String>> dataEntrypoints,
}) async {
  final config = await loadPackageConfigUri((await Isolate.packageConfig)!);
  final reader = PackageAssetReader(config, _kRootPackage);
  final bytes = <AssetId, List<int>>{};
  final seen = <AssetId>{};
  final queue = Queue<AssetId>();

  void enqueue(AssetId id) {
    if (seen.contains(id)) return;
    if (!id.path.startsWith('lib/')) return;
    queue.add(id);
  }

  for (final entry in sourceEntrypoints.entries) {
    for (final path in entry.value) {
      enqueue(AssetId(entry.key, path));
    }
  }
  for (final entry in dataEntrypoints.entries) {
    for (final path in entry.value) {
      final id = AssetId(entry.key, path);
      if (await reader.canRead(id)) {
        bytes[id] = await reader.readAsBytes(id);
      }
    }
  }

  while (queue.isNotEmpty) {
    final id = queue.removeFirst();
    if (!seen.add(id)) continue;
    if (!await reader.canRead(id)) continue;
    final assetBytes = await reader.readAsBytes(id);
    bytes[id] = assetBytes;
    if (!id.path.endsWith('.dart')) continue;
    _dartDirectiveDependencies(
      id,
      utf8.decode(assetBytes),
    ).forEach(enqueue);
  }
  return Map<AssetId, List<int>>.unmodifiable(bytes);
}

Iterable<AssetId> _dartDirectiveDependencies(
  AssetId sourceId,
  String source,
) sync* {
  final parsed = parseString(
    content: source,
    path: sourceId.path,
    throwIfDiagnostics: false,
  );
  for (final directive in parsed.unit.directives) {
    if (directive is! UriBasedDirective) continue;
    final uriText = directive.uri.stringValue;
    if (uriText == null) continue;
    final uri = Uri.tryParse(uriText);
    if (uri == null || uri.scheme == 'dart') continue;
    if (uri.hasScheme && uri.scheme != 'package' && uri.scheme != 'asset') {
      continue;
    }
    final id = AssetId.resolve(uri, from: sourceId);
    if (id.path.endsWith('.dart')) yield id;
  }
}

/// Builder that resolves each input Dart asset to a [LibraryElement] and
/// hands it to [onLibrary] for inspection by the visitor.
///
/// [allowedAssetIds] scopes invocations of [onLibrary] to those exact
/// synthetic inputs, so test assertions only see the in-memory fixtures and
/// never paywalls defined in real workspace packages.
class _CapturingBuilder implements Builder {
  _CapturingBuilder(this.onLibrary, {required this.allowedAssetIds});

  final Future<void> Function(LibraryElement library, AssetId assetId)
      onLibrary;

  /// Only invoke [onLibrary] for these exact asset ids.
  final Set<AssetId> allowedAssetIds;

  @override
  Map<String, List<String>> get buildExtensions => const {
        '.dart': ['.noop'],
      };

  @override
  Future<void> build(BuildStep step) async {
    if (!allowedAssetIds.contains(step.inputId)) return;
    final lib = await step.inputLibrary;
    await onLibrary(lib, step.inputId);
  }
}

/// Classifies the `@RestageWidget` class named [widgetName] declared in the
/// synthetic [sources] file at asset path [inputPath] (e.g. `lib/card.dart`),
/// running the full [WidgetClassifier] against [catalog].
///
/// The fixture's stub catalog widgets are made visible to the classifier by
/// passing a [catalog] whose entries' `flutterType` matches the
/// `<library URI>#<Class>` the classifier derives for them — see
/// `widget_classifier_test.dart` for the pattern.
Future<WidgetClassification> classifyFixture(
  Map<String, String> sources, {
  required String inputPath,
  required String widgetName,
  Catalog catalog = kEmptyCatalog,
  HelperRegistry? helpers,
}) async =>
    (await _runClassifierProbe(
      sources,
      inputPath: inputPath,
      widgetName: widgetName,
      catalog: catalog,
      helpers: helpers,
    ))
        .named;

/// Like [classifyFixture], but returns the whole-pass [ClassificationResult]
/// — the classification verdicts plus the emission blueprints the classifier
/// captured — so a test can assert what is available for inlining.
Future<ClassificationResult> classifyFixtureResult(
  Map<String, String> sources, {
  required String inputPath,
  required String widgetName,
  Catalog catalog = kEmptyCatalog,
  HelperRegistry? helpers,
}) async =>
    (await _runClassifierProbe(
      sources,
      inputPath: inputPath,
      widgetName: widgetName,
      catalog: catalog,
      helpers: helpers,
    ))
        .result;

/// Runs the [WidgetClassifier] over the `@RestageWidget` class named
/// [widgetName] declared in the synthetic [sources] file at [inputPath]
/// (e.g. `lib/card.dart`), against [catalog]. Returns both the whole-pass
/// [ClassificationResult] and that named class's own classification.
///
/// The fixture's stub catalog widgets are made visible to the classifier by
/// passing a [catalog] whose entries' `flutterType` matches the
/// `<library URI>#<Class>` the classifier derives for them — see
/// `widget_classifier_test.dart` for the pattern.
Future<({ClassificationResult result, WidgetClassification named})>
    _runClassifierProbe(
  Map<String, String> sources, {
  required String inputPath,
  required String widgetName,
  required Catalog catalog,
  required HelperRegistry? helpers,
}) async {
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: 'apps_examples',
    includeFlutter: _importsFlutter(sources.values),
    includeIntl: _importsIntl(sources.values),
  );
  final assetMap = <String, String>{
    for (final entry in sources.entries)
      'apps_examples|${entry.key}': entry.value,
  };
  for (final entry in assetMap.entries) {
    readerWriter.testing.writeString(AssetId.parse(entry.key), entry.value);
  }

  ClassificationResult? result;
  WidgetClassification? named;
  await testBuilder(
    _ClassifierProbeBuilder(
      inputAssetId: AssetId('apps_examples', inputPath),
      widgetName: widgetName,
      catalog: catalog,
      helpers: helpers,
      onResult: (probeResult, probeNamed) {
        result = probeResult;
        named = probeNamed;
      },
    ),
    assetMap,
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
  );

  final resolvedResult = result;
  final resolvedNamed = named;
  if (resolvedResult == null || resolvedNamed == null) {
    throw StateError(
      'classifyFixture: no @RestageWidget class named "$widgetName" was '
      'classified in $inputPath',
    );
  }
  return (result: resolvedResult, named: resolvedNamed);
}

/// Builder that resolves [inputAssetId], finds the class named [widgetName],
/// and runs [WidgetClassifier.classify] on it — the substrate for
/// [classifyFixture] / [classifyFixtureResult].
class _ClassifierProbeBuilder implements Builder {
  _ClassifierProbeBuilder({
    required this.inputAssetId,
    required this.widgetName,
    required this.catalog,
    required this.helpers,
    required this.onResult,
  });

  final AssetId inputAssetId;
  final String widgetName;
  final Catalog catalog;
  final HelperRegistry? helpers;
  final void Function(ClassificationResult result, WidgetClassification named)
      onResult;

  @override
  Map<String, List<String>> get buildExtensions => const {
        '.dart': ['.classifierprobe'],
      };

  @override
  Future<void> build(BuildStep step) async {
    if (step.inputId != inputAssetId) return;
    final library = await step.inputLibrary;
    final widgetClass =
        library.classes.where((c) => c.name == widgetName).firstOrNull;
    if (widgetClass == null) return;
    final classifier = WidgetClassifier(
      catalog: catalog,
      helpers: helpers,
      astNodeFor: (fragment) =>
          step.resolver.astNodeFor(fragment, resolve: true),
    );
    final named = await classifier.classify(widgetClass);
    onResult(
      ClassificationResult(
        classifications: classifier.results,
        blueprints: classifier.blueprints,
      ),
      named,
    );
  }
}
