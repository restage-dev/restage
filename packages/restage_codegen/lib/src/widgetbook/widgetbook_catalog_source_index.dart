import 'dart:async';
import 'dart:convert';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:crypto/crypto.dart';
import 'package:glob/glob.dart';
import 'package:restage_codegen/src/customer_structured_admissibility.dart';
import 'package:restage_codegen/src/customer_structured_reconstruction.dart';
import 'package:restage_codegen/src/dart_import_planner.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/native_screen_source_index.dart';
import 'package:restage_codegen/src/neutral_part_directive.dart';
import 'package:restage_codegen/src/restage_source_prefilter.dart';
import 'package:restage_codegen/src/restage_widget_package_facts.dart';
import 'package:restage_codegen/src/surface_publication/output_placement.dart';
import 'package:restage_codegen/src/syntax_diagnostics.dart';
import 'package:restage_codegen/src/target_config_reader.dart';
import 'package:restage_codegen/src/widget_constructor_facts.dart';
import 'package:restage_codegen/src/widget_visitor.dart';
import 'package:restage_codegen/src/widgetbook/widgetbook_property_capability.dart';
import 'package:rfw_catalog_compiler/rfw_catalog_compiler.dart'
    show DiagnosticSeverity;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// One authored story source retained with the analyzer facts needed by the
/// native Widgetbook backend.
final class WidgetbookWidgetSource {
  /// Creates an indexed story source.
  WidgetbookWidgetSource({
    required this.entry,
    required this.element,
    required this.sourceAsset,
    required this.declarationSourcePath,
    required this.usage,
    required this.targetConfig,
    required Map<String, WidgetConstructorInput> constructorInputs,
    required List<DartBareSymbolReservation> bareNamespaceReservations,
    this.nativeScreen,
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

  /// Exact analyzer-resolved path containing the class declaration.
  ///
  /// For classes declared in a part this differs from [sourceAsset], which is
  /// the importable owning library used by generated source.
  final String declarationSourcePath;

  /// Producer-facing `usage` text, falling back to [WidgetEntry.description]
  /// exactly as the customer A2UI emitter does.
  final String usage;

  /// Widgetbook-only finite-state authoring configuration.
  final WidgetbookTargetConfigFacts targetConfig;

  /// Exact native screen source when this is an automatically generated story.
  final NativeScreenSource? nativeScreen;

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

  /// Whether this story source is an opaque native screen.
  bool get isNativeScreen => nativeScreen != null;
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
    required List<WidgetbookWidgetSource> nativeScreens,
    required List<StructuredEntry> structuredTypes,
    required Map<String, WidgetbookStructuredSource> structuredSources,
    required Map<String, String> slotTargets,
    required Set<String> nullableStructuredSlots,
    required Map<String, ReconstructionPlan> reconstructionPlans,
    required Map<String, String> unrenderableByWidget,
    required List<PropertyExclusion> exclusions,
    required Set<String> restageWidgetDeclarations,
  })  : restageWidgetDeclarations = Set.unmodifiable(restageWidgetDeclarations),
        widgets = List.unmodifiable(widgets),
        nativeScreens = List.unmodifiable(nativeScreens),
        structuredTypes = List.unmodifiable(structuredTypes),
        structuredSources = Map.unmodifiable(structuredSources),
        slotTargets = Map.unmodifiable(slotTargets),
        nullableStructuredSlots = Set.unmodifiable(nullableStructuredSlots),
        reconstructionPlans = Map.unmodifiable(reconstructionPlans),
        unrenderableByWidget = Map.unmodifiable(unrenderableByWidget),
        exclusions = List.unmodifiable(exclusions),
        widgetsByFlutterType = Map.unmodifiable({
          for (final widget in [...widgets, ...nativeScreens])
            widget.entry.flutterType: widget,
        }),
        structuredBySourceType = Map.unmodifiable({
          for (final entry in structuredTypes) entry.sourceType: entry,
        });

  /// Customer widgets in deterministic `(library namespace, name)` order.
  final List<WidgetbookWidgetSource> widgets;

  /// Native screens in deterministic exact-ID order.
  final List<WidgetbookWidgetSource> nativeScreens;

  /// Every source that owns one ordinary generated Widgetbook story.
  Iterable<WidgetbookWidgetSource> get storySources sync* {
    yield* widgets;
    yield* nativeScreens;
  }

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

  /// Genuine customer-widget analyzer identities, including target-disabled
  /// classes. Each is `<library uri>#<class name>`, so story placement can be
  /// resolved from the declaring library rather than from the class name
  /// alone.
  final Set<String> restageWidgetDeclarations;

  /// Genuine customer-widget class names, including target-disabled classes.
  Set<String> get restageWidgetClassNames => {
        for (final identity in restageWidgetDeclarations)
          identity.substring(identity.lastIndexOf('#') + 1),
      };

  /// Story-source identity lookup.
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
  final Map<
      String,
      ({
        String fingerprint,
        String placement,
        Future<WidgetbookCatalogSourceIndex> index,
      })> _byPackage = {};

  /// Returns the current package index, resolving it once in this build pass.
  ///
  /// The index carries placement-derived diagnostics, so it is only reusable
  /// across builders that resolved the same placement. Every
  /// placement-affected builder key in a package is required to resolve an
  /// identical plan, so sharing is the normal case — but a disagreement is
  /// reported rather than silently served from whichever builder happened to
  /// populate the cache first.
  Future<WidgetbookCatalogSourceIndex> getOrLoad(
    BuildStep buildStep,
    RestageOutputPlacementPlan plan,
  ) async {
    final assets = await buildStep
        .findAssets(Glob('lib/**.dart'))
        .where(_isAuthoredDartAsset)
        .toList();
    assets.sort((left, right) => left.path.compareTo(right.path));
    final fingerprintParts = <String>[];
    for (final asset in assets) {
      final contents = await buildStep.readAsBytes(asset);
      fingerprintParts.add(
        '${asset.package}|${asset.path}|${sha256.convert(contents)}',
      );
    }
    final fingerprint = sha256
        .convert(
          utf8.encode(fingerprintParts.join('\n')),
        )
        .toString();
    final packageName = buildStep.inputId.package;
    final placement = restagePlacementSignature(plan);
    final cached = _byPackage[packageName];
    if (cached != null && cached.placement != placement) {
      throw StateError(
        'Placement options divergence between Restage builder targets for '
        'package $packageName: the source index was resolved under '
        '[${cached.placement}] and is now requested under [$placement]. '
        'Every placement-affected Restage builder key must carry identical '
        'placement options. In build.yaml, set the same options on each '
        'restage_codegen builder key under targets; a YAML anchor lets you '
        'write the values once. Do not set them under global_options: root '
        'global_options overrides the options every package in the build '
        'sets for itself.',
      );
    }
    if (cached != null && cached.fingerprint == fingerprint) {
      return cached.index;
    }
    final index = loadWidgetbookCatalogSourceIndex(buildStep, plan: plan);
    _byPackage[packageName] =
        (fingerprint: fingerprint, placement: placement, index: index);
    return index;
  }
}

/// Aggregates existing package visitor results into the Widgetbook source
/// index without applying RFW factory admission.
Future<WidgetbookCatalogSourceIndex> loadWidgetbookCatalogSourceIndex(
  BuildStep buildStep, {
  RestageOutputPlacementPlan? plan,
}) async {
  // Only the assets that can carry a customer widget are worth resolving.
  // Scanning still covers the whole package, so a token in a file this index
  // will not resolve still pulls in the owner it will — if it is a `part`.
  // A token in a non-part file this index skips pulls in nothing.
  final sourceAssets = await selectRestageWidgetCandidates(
    buildStep,
    resolvable: _isAuthoredDartAsset,
  );
  final widgetbookLibrary = await _resolveOptionalLibrary(
    buildStep.resolver,
    AssetId('widgetbook', 'lib/widgetbook.dart'),
  );

  final widgets = <WidgetbookWidgetSource>[];
  final nativeScreens = <WidgetbookWidgetSource>[];
  final structuredBySourceType = <String, StructuredEntry>{};
  final slotTargets = <String, String>{};
  final nullableStructuredSlots = <String>{};
  final localUnrenderable = <String, String>{};
  final widgetUnrenderable = <String, String>{};
  final reconstructionPlans = <String, ReconstructionPlan>{};
  final issues = <Issue>[];
  final exclusions = <PropertyExclusion>[];

  final sources = <ResolvedPackageLibrary>[];
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
    sources.add((assetId: assetId, library: library));
  }
  final packageFacts = indexRestageWidgetPackage(sources);

  for (final source in sources) {
    final assetId = source.assetId;
    final library = source.library;
    final walk = packageFacts.walksByAsset[assetId]!;
    for (final diagnostic in walk.diagnostics) {
      if (diagnostic.severity == DiagnosticSeverity.error) {
        issues.add(
          Issue(
            code: IssueCode.missingAnnotationField,
            message: diagnostic.message,
            location: diagnostic.location,
          ),
        );
      } else {
        log.warning(diagnostic.message);
      }
    }

    final result = visitRestageWidgetsInPackage(
      library,
      assetId,
      target: WidgetVisitorTarget.widgetbook,
      packageFacts: packageFacts,
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

      final constructorFacts = projectWidgetConstructorFacts(
        element,
        assetId,
        readWidgetConstructorFacts(element, assetId),
        target: EmitTarget.widgetbook,
      );
      final a2uiTargetConfig = readA2uiTargetConfig(
        element,
        assetId,
        constructorInputs: constructorFacts.inputs,
        consumer: A2uiTargetConfigConsumer.widgetbookMetadata,
      );
      final widgetbookTargetConfig = readWidgetbookTargetConfig(
        element,
        assetId,
        constructorInputs: constructorFacts.inputs,
      );
      issues
        ..addAll(a2uiTargetConfig.issues)
        ..addAll(widgetbookTargetConfig.issues);
      final usageValue = a2uiTargetConfig.usage;
      final inputsByName = {
        for (final input in constructorFacts.inputs) input.name: input,
      };
      widgets.add(
        WidgetbookWidgetSource(
          entry: entry,
          element: element,
          sourceAsset: assetId,
          declarationSourcePath: _elementSourcePath(element, assetId),
          usage: usageValue == null || usageValue.isEmpty
              ? entry.description
              : usageValue,
          targetConfig: widgetbookTargetConfig,
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
      _recordAutomaticSourceObstructions(
        source: widgets.last,
        sourceLabel: '@RestageWidget',
        unrenderable: widgetUnrenderable,
      );
    }

    final resolved = await library.session.getResolvedLibraryByElement(library);
    if (resolved is ResolvedLibraryResult && resolved.units.isNotEmpty) {
      issues.addAll(syntacticErrorIssues(resolved, sourcePath: assetId.path));
    }
  }

  final nativeIndex = await loadNativeScreenSourceIndex(
    buildStep,
    plan: plan,
    consumer: NativeScreenSourceConsumer.widgetbook,
  );
  const screenPlanningLibrary = WidgetLibrary.custom(
    'restage.native_screen_source',
  );
  for (final screen in nativeIndex.screens) {
    final projection = projectConstructorComponent(
      element: screen.element,
      assetId: screen.sourceAsset,
      constructorFacts: screen.constructorFacts,
      componentName: screen.id,
      flutterType: screen.classIdentity,
      description: screen.description ?? '',
      sinceVersion: screen.version,
      planningLibrary: screenPlanningLibrary,
      target: WidgetVisitorTarget.widgetbook,
    );
    issues.addAll(projection.issues);
    exclusions.addAll(projection.exclusions);
    _mergeStringMap(
      slotTargets,
      projection.slotTargets,
      label: 'structured slot target',
      issues: issues,
      location: screen.declarationSourcePath,
    );
    nullableStructuredSlots.addAll(projection.nullableStructuredSlots);
    _mergeStringMap(
      localUnrenderable,
      projection.localUnrenderable,
      label: 'structured unrenderability',
      issues: issues,
      location: screen.declarationSourcePath,
    );
    _mergeStringMap(
      widgetUnrenderable,
      projection.componentUnrenderable,
      label: 'screen unrenderability',
      issues: issues,
      location: screen.declarationSourcePath,
    );
    for (final plan in projection.reconstructionPlans.entries) {
      reconstructionPlans.putIfAbsent(plan.key, () => plan.value);
    }
    for (final structured in projection.structuredTypes) {
      structuredBySourceType.putIfAbsent(
        structured.sourceType,
        () => structured,
      );
    }

    final entry = projection.entry;
    final inputsByName = {
      for (final input in screen.constructorFacts.inputs) input.name: input,
    };
    final usageValue = screen.a2uiTargetConfig.usage;
    nativeScreens.add(
      WidgetbookWidgetSource(
        entry: entry,
        element: screen.element,
        sourceAsset: screen.sourceAsset,
        declarationSourcePath: screen.declarationSourcePath,
        usage: usageValue == null || usageValue.isEmpty
            ? entry.description
            : usageValue,
        targetConfig: screen.widgetbookTargetConfig,
        nativeScreen: screen,
        constructorInputs: inputsByName,
        bareNamespaceReservations: _bareNamespaceReservations(
          sourceLibrary: screen.element.library,
          widgetbookLibrary: widgetbookLibrary,
          sourceClassName: screen.element.name ?? '<unnamed>',
          propertyTypes: [
            for (final property in entry.properties)
              if (property.type != PropertyType.event)
                if (inputsByName[property.name] case final input?) input.type,
          ],
        ),
      ),
    );

    _recordAutomaticSourceObstructions(
      source: nativeScreens.last,
      sourceLabel: screen.sourceAnnotation,
      unrenderable: widgetUnrenderable,
    );
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
  final storySources = <WidgetbookWidgetSource>[
    ...widgets,
    ...nativeScreens,
  ];
  for (final widget in storySources) {
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
    widgets: [for (final widget in storySources) widget.entry],
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
  nativeScreens.sort((left, right) {
    final byId = left.entry.name.compareTo(right.entry.name);
    return byId != 0
        ? byId
        : left.entry.flutterType.compareTo(right.entry.flutterType);
  });
  return WidgetbookCatalogSourceIndex(
    widgets: widgets,
    nativeScreens: nativeScreens,
    structuredTypes: structuredTypes,
    structuredSources: structuredSources,
    slotTargets: slotTargets,
    nullableStructuredSlots: nullableStructuredSlots,
    reconstructionPlans: reconstructionPlans,
    unrenderableByWidget: widgetUnrenderable,
    exclusions: exclusions,
    restageWidgetDeclarations: packageFacts.widgetDeclarations,
  );
}

void _recordAutomaticSourceObstructions({
  required WidgetbookWidgetSource source,
  required String sourceLabel,
  required Map<String, String> unrenderable,
}) {
  final entry = source.entry;
  if (source.element.typeParameters.isNotEmpty) {
    unrenderable[entry.flutterType] =
        'generic $sourceLabel classes are not supported by automatic '
        'Widgetbook stories; use a concrete wrapper widget';
  }
  final constructor = source.element.unnamedConstructor;
  if (constructor == null || constructor.isFactory) {
    unrenderable[entry.flutterType] =
        'automatic Widgetbook stories require an unnamed generative '
        'constructor';
    return;
  }
  final catalogNames = {
    for (final property in entry.properties) property.name,
  };
  final missingRequired = constructor.formalParameters.where(
    (parameter) =>
        parameter.isRequired && !catalogNames.contains(parameter.name),
  );
  if (missingRequired.isNotEmpty) {
    unrenderable[entry.flutterType] =
        'required constructor parameter(s) not represented in the catalog: '
        '${missingRequired.map(
              (parameter) => parameter.name ?? '<positional>',
            ).join(', ')}';
  }
}

String _elementSourcePath(Element element, AssetId contextAsset) {
  final fragment = element.firstFragment.libraryFragment;
  if (fragment == null) {
    throw StateError(
      'Could not resolve a defining library fragment for '
      '${element.displayName}.',
    );
  }
  final source = fragment.source;
  final uri = source.uri;
  if (uri.scheme == 'package' || uri.scheme == 'asset') {
    final asset = AssetId.resolve(uri);
    return asset.package == contextAsset.package ? asset.path : uri.toString();
  }
  if (uri.scheme == 'file') return source.fullName;
  if (uri.hasScheme) return uri.toString();
  throw StateError(
    'Could not resolve an exact defining source for '
    '${element.displayName}.',
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
