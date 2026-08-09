import 'dart:async';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:glob/glob.dart';
import 'package:restage_codegen/src/customer_structured_admissibility.dart';
import 'package:restage_codegen/src/customer_structured_reconstruction.dart';
import 'package:restage_codegen/src/dart_import_planner.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/syntax_diagnostics.dart';
import 'package:restage_codegen/src/target_config_reader.dart';
import 'package:restage_codegen/src/widget_constructor_facts.dart';
import 'package:restage_codegen/src/widget_visitor.dart';
import 'package:restage_codegen/src/widgetbook/widgetbook_property_capability.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// One customer widget retained with the analyzer facts needed by the native
/// Widgetbook backend.
final class WidgetbookWidgetSource {
  /// Creates an indexed customer widget.
  WidgetbookWidgetSource({
    required this.entry,
    required this.element,
    required this.sourceAsset,
    required this.usage,
    required Map<String, WidgetConstructorInput> constructorInputs,
    required List<DartBareSymbolReservation> bareNamespaceReservations,
  })  : constructorInputs = Map.unmodifiable(constructorInputs),
        bareNamespaceReservations = List.unmodifiable(
          bareNamespaceReservations,
        );

  /// Shared catalog projection produced by [visitRestageWidgets].
  final WidgetEntry entry;

  /// Analyzer element from the widget's defining library.
  final ClassElement element;

  /// Defining source asset.
  final AssetId sourceAsset;

  /// Producer-facing `usage` text, falling back to [WidgetEntry.description]
  /// exactly as the customer A2UI emitter does.
  final String usage;

  /// Constructor-normalized inputs keyed by public property name.
  final Map<String, WidgetConstructorInput> constructorInputs;

  /// Existing bare bindings that can collide with source types reproduced by
  /// Widgetbook's generated part.
  final List<DartBareSymbolReservation> bareNamespaceReservations;

  /// Source class name.
  String get className => entry.flutterType.split('#').last;

  /// The unnamed generative constructor used by automatic native stories.
  ConstructorElement? get constructor {
    final candidate = element.unnamedConstructor;
    return candidate == null || candidate.isFactory ? null : candidate;
  }
}

/// One customer structured value retained with its analyzer declaration.
final class WidgetbookStructuredSource {
  /// Creates an indexed structured value type.
  const WidgetbookStructuredSource({
    required this.entry,
    required this.element,
    required this.sourceAsset,
  });

  /// Shared structured catalog projection.
  final StructuredEntry entry;

  /// Analyzer class that defines the customer value.
  final ClassElement element;

  /// Defining library asset.
  final AssetId sourceAsset;

  /// Constructor selected by the shared reconstruction plan.
  ConstructorElement? constructorFor(ReconstructionPlan plan) {
    final target = plan.namedConstructor;
    for (final constructor in element.constructors) {
      final name = constructor.name;
      final normalized =
          name == null || name.isEmpty || name == 'new' ? null : name;
      if (!constructor.isFactory && normalized == target) return constructor;
    }
    return null;
  }
}

/// Package-wide, admission-neutral source facts consumed only by Widgetbook.
///
/// This is an aggregation of the existing visitor/discovery facts, not a
/// new public catalog vocabulary. RFW and A2UI do not consume it.
final class WidgetbookCatalogSourceIndex {
  /// Creates an immutable package index.
  WidgetbookCatalogSourceIndex({
    required List<WidgetbookWidgetSource> widgets,
    required List<StructuredEntry> structuredTypes,
    required Map<String, WidgetbookStructuredSource> structuredSources,
    required Map<String, String> slotTargets,
    required Set<String> nullableStructuredSlots,
    required Map<String, ReconstructionPlan> reconstructionPlans,
    required Map<String, String> unrenderableByWidget,
    required List<PropertyExclusion> exclusions,
  })  : widgets = List.unmodifiable(widgets),
        structuredTypes = List.unmodifiable(structuredTypes),
        structuredSources = Map.unmodifiable(structuredSources),
        slotTargets = Map.unmodifiable(slotTargets),
        nullableStructuredSlots = Set.unmodifiable(nullableStructuredSlots),
        reconstructionPlans = Map.unmodifiable(reconstructionPlans),
        unrenderableByWidget = Map.unmodifiable(unrenderableByWidget),
        exclusions = List.unmodifiable(exclusions),
        widgetsByFlutterType = Map.unmodifiable({
          for (final widget in widgets) widget.entry.flutterType: widget,
        }),
        structuredBySourceType = Map.unmodifiable({
          for (final entry in structuredTypes) entry.sourceType: entry,
        });

  /// Customer widgets in deterministic `(library namespace, name)` order.
  final List<WidgetbookWidgetSource> widgets;

  /// Customer structured types reachable from any indexed widget.
  final List<StructuredEntry> structuredTypes;

  /// Analyzer declarations keyed by structured `sourceType`.
  final Map<String, WidgetbookStructuredSource> structuredSources;

  /// Structured owner/slot key to target `sourceType`.
  final Map<String, String> slotTargets;

  /// Nullable widget-level structured slots.
  final Set<String> nullableStructuredSlots;

  /// Analyzer-derived customer constructor plans.
  final Map<String, ReconstructionPlan> reconstructionPlans;

  /// Widget identity to a reason automatic story generation is unsound.
  final Map<String, String> unrenderableByWidget;

  /// Constructor inputs omitted because Widgetbook cannot decode their type.
  final List<PropertyExclusion> exclusions;

  /// Widget identity lookup.
  final Map<String, WidgetbookWidgetSource> widgetsByFlutterType;

  /// Structured source identity lookup.
  final Map<String, StructuredEntry> structuredBySourceType;
}

/// Per-build cache for the package-wide Widgetbook index.
///
/// Every caller still registers every authored Dart asset as a dependency.
/// Sharing the resolved index must not make the second story output stale when
/// a component in another file changes.
final class WidgetbookCatalogIndexCache {
  final Map<String, Future<WidgetbookCatalogSourceIndex>> _byPackage = {};

  /// Returns the current package index, resolving it once in this build pass.
  Future<WidgetbookCatalogSourceIndex> getOrLoad(BuildStep buildStep) async {
    final assets = await buildStep
        .findAssets(Glob('lib/**.dart'))
        .where(_isAuthoredDartAsset)
        .toList();
    assets.sort((left, right) => left.path.compareTo(right.path));
    for (final asset in assets) {
      await buildStep.canRead(asset);
    }

    return _byPackage[buildStep.inputId.package] ??=
        loadWidgetbookCatalogSourceIndex(
      buildStep,
      assets: assets,
    );
  }
}

/// Aggregates existing package visitor results into the Widgetbook source
/// index without applying RFW factory admission.
Future<WidgetbookCatalogSourceIndex> loadWidgetbookCatalogSourceIndex(
  BuildStep buildStep, {
  Iterable<AssetId>? assets,
}) async {
  final sourceAssets = (assets == null
      ? await buildStep
          .findAssets(Glob('lib/**.dart'))
          .where(_isAuthoredDartAsset)
          .toList()
      : assets.toList())
    ..sort((left, right) => left.path.compareTo(right.path));
  final widgetbookLibrary = await _resolveOptionalLibrary(
    buildStep.resolver,
    AssetId('widgetbook', 'lib/widgetbook.dart'),
  );

  final widgets = <WidgetbookWidgetSource>[];
  final structuredBySourceType = <String, StructuredEntry>{};
  final slotTargets = <String, String>{};
  final nullableStructuredSlots = <String>{};
  final localUnrenderable = <String, String>{};
  final widgetUnrenderable = <String, String>{};
  final reconstructionPlans = <String, ReconstructionPlan>{};
  final issues = <Issue>[];
  final exclusions = <PropertyExclusion>[];

  for (final assetId in sourceAssets) {
    final LibraryElement library;
    try {
      library = await buildStep.resolver.libraryFor(
        assetId,
        allowSyntaxErrors: true,
      );
    } on NonLibraryAssetException {
      continue;
    }

    final result = visitRestageWidgets(
      library,
      assetId,
      target: WidgetVisitorTarget.widgetbook,
    );
    issues.addAll(result.issues);
    exclusions.addAll(result.exclusions);
    _mergeStringMap(
      slotTargets,
      result.slotTargets,
      label: 'structured slot target',
      issues: issues,
      location: assetId.path,
    );
    nullableStructuredSlots.addAll(result.nullableStructuredSlots);
    _mergeStringMap(
      localUnrenderable,
      result.localUnrenderable,
      label: 'structured unrenderability',
      issues: issues,
      location: assetId.path,
    );
    _mergeStringMap(
      widgetUnrenderable,
      result.widgetUnrenderable,
      label: 'widget unrenderability',
      issues: issues,
      location: assetId.path,
    );
    for (final plan in result.reconstructionPlans.entries) {
      reconstructionPlans.putIfAbsent(plan.key, () => plan.value);
    }
    for (final structured in result.structuredTypes) {
      structuredBySourceType.putIfAbsent(
        structured.sourceType,
        () => structured,
      );
    }

    for (final entry in result.widgets) {
      final className = entry.flutterType.split('#').last;
      final matches =
          library.classes.where((element) => element.name == className);
      if (matches.length != 1) {
        issues.add(
          Issue(
            code: IssueCode.analyzerResolutionFailed,
            message: 'could not resolve exactly one class "$className" for '
                '@RestageWidget "${entry.name}".',
            location: '${assetId.path}#$className',
          ),
        );
        continue;
      }
      final element = matches.single;
      if (WidgetLibrary.builtInByNamespace(entry.library.namespace) != null) {
        issues.add(
          Issue(
            code: IssueCode.invalidWidgetClass,
            message: '@RestageWidget "${entry.name}" declares reserved '
                'built-in namespace "${entry.library.namespace}".',
            location: '${assetId.path}#$className',
          ),
        );
        continue;
      }

      final constructorFacts = readWidgetConstructorFacts(element, assetId);
      final targetConfig = readA2uiTargetConfig(
        element,
        assetId,
        constructorInputs: constructorFacts.inputs,
        consumer: A2uiTargetConfigConsumer.widgetbookMetadata,
      );
      issues.addAll(targetConfig.issues);
      final usageValue = targetConfig.usage;
      final inputsByName = {
        for (final input in constructorFacts.inputs) input.name: input,
      };
      widgets.add(
        WidgetbookWidgetSource(
          entry: entry,
          element: element,
          sourceAsset: assetId,
          usage: usageValue == null || usageValue.isEmpty
              ? entry.description
              : usageValue,
          constructorInputs: inputsByName,
          bareNamespaceReservations: _bareNamespaceReservations(
            sourceLibrary: library,
            widgetbookLibrary: widgetbookLibrary,
            sourceClassName: className,
            propertyTypes: [
              for (final property in entry.properties)
                if (property.type != PropertyType.event)
                  if (inputsByName[property.name] case final input?) input.type,
            ],
          ),
        ),
      );

      final metadataCollisions = entry.properties
          .where(
            (property) =>
                property.name == 'description' || property.name == 'usage',
          )
          .map((property) => property.name)
          .toList(growable: false);
      if (metadataCollisions.isNotEmpty) {
        widgetUnrenderable[entry.flutterType] =
            'catalog property name(s) ${metadataCollisions.join(', ')} collide '
            'with the generated Widgetbook metadata sidebar fields';
      }

      if (element.typeParameters.isNotEmpty) {
        widgetUnrenderable[entry.flutterType] =
            'generic @RestageWidget classes are not supported by automatic '
            'Widgetbook stories; use a concrete wrapper widget';
      }
      final constructor = element.unnamedConstructor;
      if (constructor == null || constructor.isFactory) {
        widgetUnrenderable[entry.flutterType] =
            'automatic Widgetbook stories require an unnamed generative '
            'constructor';
      } else {
        final catalogNames = {
          for (final property in entry.properties) property.name,
        };
        final missingRequired = constructor.formalParameters.where(
          (parameter) =>
              parameter.isRequired && !catalogNames.contains(parameter.name),
        );
        if (missingRequired.isNotEmpty) {
          widgetUnrenderable[entry.flutterType] =
              'required constructor parameter(s) not represented in the '
              'catalog: ${missingRequired.map(
                    (parameter) => parameter.name ?? '<positional>',
                  ).join(', ')}';
        }
      }
    }

    final resolved = await library.session.getResolvedLibraryByElement(library);
    if (resolved is ResolvedLibraryResult && resolved.units.isNotEmpty) {
      issues.addAll(syntacticErrorIssues(resolved, sourcePath: assetId.path));
    }
  }

  final byCatalogName = <String, List<WidgetbookWidgetSource>>{};
  final byFlutterType = <String, List<WidgetbookWidgetSource>>{};
  for (final widget in widgets) {
    byCatalogName.putIfAbsent(widget.entry.name, () => []).add(widget);
    byFlutterType.putIfAbsent(widget.entry.flutterType, () => []).add(widget);
  }
  for (final duplicate
      in byCatalogName.entries.where((entry) => entry.value.length > 1)) {
    issues.add(
      Issue(
        code: IssueCode.duplicateWidgetName,
        message: 'Widgetbook canonical component name "${duplicate.key}" is '
            'ambiguous across ${duplicate.value.map(
                  (widget) => widget.entry.flutterType,
                ).join(', ')}.',
        location: 'lib/',
      ),
    );
  }
  for (final duplicate
      in byFlutterType.entries.where((entry) => entry.value.length > 1)) {
    issues.add(
      Issue(
        code: IssueCode.duplicateWidgetName,
        message: 'duplicate @RestageWidget source identity '
            '"${duplicate.key}".',
        location: 'lib/',
      ),
    );
  }

  final structuredTypes = structuredBySourceType.values.toList()
    ..sort((left, right) => left.sourceType.compareTo(right.sourceType));
  final structuredSources = <String, WidgetbookStructuredSource>{};
  for (final structured in structuredTypes) {
    final source = await _resolveStructuredSource(
      buildStep,
      structured,
      from: sourceAssets.firstOrNull ?? buildStep.inputId,
    );
    if (source == null) {
      localUnrenderable[structured.sourceType] =
          'the analyzer could not resolve its defining customer class';
    } else {
      structuredSources[structured.sourceType] = source;
    }
  }
  final structuredEntries = {
    for (final entry in structuredTypes) entry.sourceType: entry,
  };
  for (final widget in widgets) {
    final obstruction = _widgetbookCapabilityObstruction(
      widget.entry,
      structuredEntries: structuredEntries,
      slotTargets: slotTargets,
    );
    if (obstruction != null) {
      widgetUnrenderable[widget.entry.flutterType] = obstruction;
    }
  }
  final admission = computeAdmission(
    widgets: [for (final widget in widgets) widget.entry],
    structuredTypes: structuredTypes,
    slotTargets: slotTargets,
    localUnrenderable: localUnrenderable,
    widgetUnrenderable: widgetUnrenderable,
  );
  for (final excluded in admission.excluded) {
    widgetUnrenderable.putIfAbsent(
      excluded.widget.flutterType,
      () => excluded.reason,
    );
  }

  for (final issue in issues.where((issue) => issue.code.isInformational)) {
    log.warning(issue.toString());
  }
  final failures = issues
      .where((issue) => !issue.code.isInformational)
      .toList(growable: false);
  if (failures.isNotEmpty) {
    for (final issue in failures) {
      log.severe(issue.toString());
    }
    throw StateError(
      '${failures.length} Widgetbook catalog source issue(s); see log above.',
    );
  }

  widgets.sort((left, right) {
    final byLibrary = left.entry.library.namespace.compareTo(
      right.entry.library.namespace,
    );
    return byLibrary != 0
        ? byLibrary
        : left.entry.name.compareTo(right.entry.name);
  });
  return WidgetbookCatalogSourceIndex(
    widgets: widgets,
    structuredTypes: structuredTypes,
    structuredSources: structuredSources,
    slotTargets: slotTargets,
    nullableStructuredSlots: nullableStructuredSlots,
    reconstructionPlans: reconstructionPlans,
    unrenderableByWidget: widgetUnrenderable,
    exclusions: exclusions,
  );
}

List<DartBareSymbolReservation> _bareNamespaceReservations({
  required LibraryElement sourceLibrary,
  required LibraryElement? widgetbookLibrary,
  required String sourceClassName,
  required Iterable<DartType> propertyTypes,
}) {
  final symbols = <String>{sourceClassName};
  for (final type in propertyTypes) {
    _collectInterfaceTypeSymbols(type, symbols);
  }
  final coreLibrary = sourceLibrary.typeProvider.objectElement.library;
  final reservations = <String, DartBareSymbolReservation>{};

  void reserve(Element? element, String symbol, String source) {
    final libraryUri = element?.library?.identifier;
    if (libraryUri == null) return;
    reservations.putIfAbsent(
      '$libraryUri#$symbol',
      () => DartBareSymbolReservation(
        libraryUri: libraryUri,
        symbol: symbol,
        source: source,
      ),
    );
  }

  for (final symbol in symbols.toList()..sort()) {
    reserve(
      coreLibrary.publicNamespace.get2(symbol),
      symbol,
      'implicit dart:core namespace',
    );
    final widgetbookElement = widgetbookLibrary?.exportNamespace.get2(symbol);
    if (widgetbookElement != null) {
      reserve(
        widgetbookElement,
        symbol,
        'package:widgetbook/widgetbook.dart export',
      );
    }
  }
  final result = reservations.values.toList()
    ..sort((left, right) {
      final bySymbol = left.symbol.compareTo(right.symbol);
      if (bySymbol != 0) return bySymbol;
      final byUri = (left.libraryUri ?? '').compareTo(right.libraryUri ?? '');
      return byUri != 0 ? byUri : left.source.compareTo(right.source);
    });
  return result;
}

void _collectInterfaceTypeSymbols(DartType type, Set<String> symbols) {
  if (type is! InterfaceType) return;
  final symbol = type.element.name;
  if (symbol != null && symbol.isNotEmpty) symbols.add(symbol);
  for (final argument in type.typeArguments) {
    _collectInterfaceTypeSymbols(argument, symbols);
  }
}

Future<LibraryElement?> _resolveOptionalLibrary(
  Resolver resolver,
  AssetId asset,
) async {
  try {
    return await resolver.libraryFor(asset, allowSyntaxErrors: true);
  } on Object {
    return null;
  }
}

Future<WidgetbookStructuredSource?> _resolveStructuredSource(
  BuildStep buildStep,
  StructuredEntry entry, {
  required AssetId from,
}) async {
  final separator = entry.sourceType.lastIndexOf('#');
  if (separator <= 0 || separator == entry.sourceType.length - 1) return null;
  final uri = Uri.tryParse(entry.sourceType.substring(0, separator));
  if (uri == null || uri.scheme != 'package') return null;
  final asset = AssetId.resolve(uri, from: from);
  if (!await buildStep.canRead(asset)) return null;

  final LibraryElement library;
  try {
    library = await buildStep.resolver.libraryFor(
      asset,
      allowSyntaxErrors: true,
    );
  } on NonLibraryAssetException {
    return null;
  }
  final symbol = entry.sourceType.substring(separator + 1);
  final matches = library.classes.where((element) => element.name == symbol);
  if (matches.length != 1) return null;
  return WidgetbookStructuredSource(
    entry: entry,
    element: matches.single,
    sourceAsset: asset,
  );
}

bool _isAuthoredDartAsset(AssetId asset) =>
    asset.path.endsWith('.dart') &&
    !asset.path.endsWith('.g.dart') &&
    !asset.path.endsWith('.stories.dart');

void _mergeStringMap(
  Map<String, String> destination,
  Map<String, String> incoming, {
  required String label,
  required List<Issue> issues,
  required String location,
}) {
  for (final entry in incoming.entries) {
    final prior = destination[entry.key];
    if (prior != null && prior != entry.value) {
      issues.add(
        Issue(
          code: IssueCode.duplicateId,
          message: 'conflicting $label for "${entry.key}": '
              '"$prior" vs "${entry.value}".',
          location: location,
        ),
      );
      continue;
    }
    destination[entry.key] = entry.value;
  }
}

String? _widgetbookCapabilityObstruction(
  WidgetEntry widget, {
  required Map<String, StructuredEntry> structuredEntries,
  required Map<String, String> slotTargets,
}) {
  for (final property in widget.properties) {
    final path = '${widget.name}.${property.name}';
    final target =
        slotTargets[structuredSlotKey(widget.flutterType, property.name)];
    if (target != null) {
      final obstruction = _structuredCapabilityObstruction(
        target,
        path: path,
        structuredEntries: structuredEntries,
        slotTargets: slotTargets,
        visiting: <String>{},
      );
      if (obstruction != null) return obstruction;
      continue;
    }
    if (isCustomerStructuredPropertySlot(property)) {
      return '$path is missing its customer structured target identity';
    }
    if (widgetbookPropertyCapability(
          property.type,
          context: WidgetbookPropertyContext.widgetProperty,
        ) ==
        WidgetbookPropertyCapability.rejected) {
      return '$path uses unsupported Widgetbook property type '
          '${property.type.name}';
    }
  }
  return null;
}

String? _structuredCapabilityObstruction(
  String sourceType, {
  required String path,
  required Map<String, StructuredEntry> structuredEntries,
  required Map<String, String> slotTargets,
  required Set<String> visiting,
}) {
  if (!visiting.add(sourceType)) {
    return '$path reaches a cyclic structured type';
  }
  try {
    final entry = structuredEntries[sourceType];
    if (entry == null) {
      return '$path targets missing structured type $sourceType';
    }
    for (final field in entry.fields) {
      final fieldPath = '$path.${field.name}';
      final target = slotTargets[structuredSlotKey(sourceType, field.name)];
      if (target != null) {
        final obstruction = _structuredCapabilityObstruction(
          target,
          path: fieldPath,
          structuredEntries: structuredEntries,
          slotTargets: slotTargets,
          visiting: visiting,
        );
        if (obstruction != null) return obstruction;
        continue;
      }
      if (isCustomerStructuredFieldSlot(field)) {
        return '$fieldPath is missing its customer structured target identity';
      }
      if (widgetbookPropertyCapability(
            field.type,
            context: WidgetbookPropertyContext.structuredField,
          ) ==
          WidgetbookPropertyCapability.rejected) {
        return '$fieldPath uses unsupported Widgetbook structured field type '
            '${field.type.name}';
      }
    }
    return null;
  } finally {
    visiting.remove(sourceType);
  }
}
