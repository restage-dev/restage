import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:restage_codegen/src/annotation_lookup.dart';
import 'package:restage_codegen/src/custom_widget_blueprint.dart';
import 'package:restage_codegen/src/dot_shorthand_expansion.dart'
    show resolvedNodeInLongForm;
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/production_helpers.dart'
    show productionPaywallHelperRegistry;
import 'package:restage_codegen/src/factory_emitter.dart'
    show CustomReconstruction, customReconstructionFor;
import 'package:restage_codegen/src/restage_widget_walker.dart'
    show collectRestageWidgetsForPackage;
import 'package:restage_codegen/src/widget_classifier.dart'
    show WidgetClassifier, customWidgetKey;
import 'package:restage_codegen/src/islands/islands.dart'
    show Island, withIslands;
import 'package:restage_codegen/src/islands/opt_outs.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/neutral_part_directive.dart'
    show kNeutralGeneratedPartSuffix, neutralPartUri;
import 'package:restage_codegen/src/surface_publication/output_location.dart'
    show RestageOutputLocationPlan;
import 'package:restage_codegen/src/source_state.dart';
import 'package:restage_codegen/src/surface_publication/screen_contract_reference_emitter.dart'
    show ResolvedWidgetMountInput, emitSplitWidget;
import 'package:restage_codegen/src/widget_classification.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart' as fmt;

/// The builder scope a split widget's delivered definition reads its
/// recorded values from.
const String kSplitWidgetScope = fmt.kSplitWidgetBodyArgument;

/// A split widget's declarations, states and catalog constructors, as the
/// surface translator registers them.
typedef SplitWidgetDefinitions = ({
  Map<String, String> definitions,
  Map<String, Map<String, String>> states,
  List<fmt.RfwCatalogConstructorProvenance> origins,
  Set<String> libraries,
});

/// The registered wrapper that hosts a split widget named [catalogName].
String splitFactoryName(String catalogName) =>
    '$catalogName${fmt.kSplitWrapperSuffix}';

/// The registration constant a split widget's wrapper declares in
/// [library], added to the app's registration of [namespace].
typedef SplitRegistration = ({String namespace, String library, String name});

/// A `@RestageWidget` whose build can't be fully inlined, split like a
/// surface: [mount] is what its generated wrapper records and hosts, and
/// [definition] is the delivered declaration's root.
final class SplitWidgetInput {
  /// Creates a split widget.
  const SplitWidgetInput({
    required this.mount,
    required this.entry,
    required this.definition,
    this.inlined = (definitions: const {}, states: const {}),
    this.origins = const [],
    this.custom,
    this.foreign = false,
  });

  /// The widget's build as a mount: its class, parameters, recorded values,
  /// islands and split.
  final ResolvedWidgetMountInput mount;

  /// The widget's own catalog entry.
  final WidgetEntry entry;

  /// The RFW text of `widget <catalog name> = …`'s root.
  final String definition;

  /// Whether another package's build generated its wrapper.
  final bool foreign;

  /// How its package's factories reconstruct custom values; the wrapper
  /// decodes its arguments the same way.
  final CustomReconstruction? custom;

  /// The catalog constructors its declarations call, the wrapper included.
  final List<fmt.RfwCatalogConstructorProvenance> origins;

  /// The custom widgets its build inlines, as declarations and states.
  final ({
    Map<String, String> definitions,
    Map<String, Map<String, String>> states,
  })
  inlined;

  /// The widget's catalog name.
  String get catalogName => entry.name;

  /// The library namespace its wrapper and islands register under.
  String get namespace => entry.library.namespace;

  /// The registered wrapper the definition places.
  String get factoryName => splitFactoryName(entry.name);
}

/// The delivered definition of a split [entry] whose build translated to
/// [root]: the wrapper, with each property forwarded and [root] as its
/// builder body. Reads of [params] become `args`, other render-context reads
/// become the wrapper's recorded values.
///
/// Throws [FormatException] when the result still reads the render context.
String splitDefinition(String root, WidgetEntry entry, Set<String> params) {
  final program = BuilderProgram(
    values: const ValueProgram(
      nodes: [ValueNode('literal', ValueType.boolean, value: true)],
      root: 0,
    ),
    result: const BuilderResult.body(0),
    bodyCount: 1,
  );
  final forwarded = [
    for (final property in _designProperties(entry))
      '${property.name}: args.${property.name}',
    // Where the surface places it, so its wrapper keeps one identity.
    for (final name in kAppWidgetPlacementArguments) '$name: args.$name',
  ];
  final body = _scoped(root, params);
  final definition =
      '${splitFactoryName(entry.name)}(${[
        ...forwarded,
        '$kSplitWidgetScope: $kBuilderContinuationWidgetName(version: 1, '
            'program: ${jsonEncode(program.encode())}, captures: {}, '
            'bodies: [($kSplitWidgetScope) => $body])',
      ].join(', ')})';
  final parsed = fmt.parseLibraryFile('widget _ = $definition;');
  if (_readsContext(parsed.widgets.single.root)) {
    throw FormatException(
      'The definition of ${entry.name} still reads the render context.',
    );
  }
  return definition;
}

/// The split of each `@RestageWidget` [classification] found that doesn't
/// fully inline and has a [catalog] entry, translated as its own root by
/// [translator]. A widget kept as the app builds it, or whose build doesn't
/// translate, stays its registered factory.
Future<List<SplitWidgetInput>> splitWidgetsOf({
  required ClassificationResult classification,
  required Catalog catalog,
  required LibraryElement surfaceLibrary,
  required Future<AstNode?> Function(Fragment fragment) astNodeFor,
  required ExpressionTranslator translator,
  required Set<String> noticeKeys,
  Set<String>? placed,
  Future<CustomReconstruction?> Function()? custom,
}) async {
  // Each note logs once per build, whichever surfaces place the widget.
  var placedHere = true;
  void note(Issue issue) {
    if (placedHere && noticeKeys.add(issue.buildNoticeKey)) {
      log.warning(issue.message);
    }
  }

  final splits = <SplitWidgetInput>[];
  for (final MapEntry(key: key, value: widget)
      in classification.classes.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key))) {
    if (classification.classifications[key] is ComposableWidget ||
        firstAnnotation(widget, 'RestageWidget') == null ||
        optOutOfClass(widget, surfaceLibrary.firstFragment) != null) {
      continue;
    }
    final flutterType = '${widget.library.identifier}#${widget.name}';
    final entry = catalog.widgets
        .where(
          (entry) =>
              entry.flutterType == flutterType &&
              WidgetLibrary.builtInByNamespace(entry.library.namespace) == null,
        )
        .firstOrNull;
    if (entry == null) continue;
    placedHere =
        placed == null ||
        placed.contains('${entry.library.namespace}:${entry.name}');
    final assetId = AssetId.resolve(widget.library.uri);
    // Another package's widget splits through the wrapper that package's
    // own build generated.
    final foreign = assetId.package != surfaceLibrary.uri.pathSegments.first;
    Issue foreignNote() => Issue(
      code: IssueCode.customWidgetNotSplit,
      message:
          "Designs can't change what's inside `${widget.name}` "
          '(${_classLocation(widget, assetId)} in package '
          '${assetId.package}) because the code Restage generates for it '
          'in ${assetId.package} is missing or out of date. Try running '
          '`dart run build_runner build` in ${assetId.package}.',
      location: _classLocation(widget, assetId),
    );
    if (foreign && !declaresGeneratedPart(widget.library)) {
      note(foreignNote());
      continue;
    }
    if (!declaresGeneratedPart(widget.library)) {
      final location = _classLocation(widget, assetId);
      note(
        Issue(
          code: IssueCode.customWidgetNotSplit,
          message:
              "Designs can't change what's inside `${widget.name}` "
              '($location) because ${assetId.path} has no '
              "`part '${neutralPartUri(RestageOutputLocationPlan.defaults, assetId.path)}';` "
              'line. Try adding that line to ${assetId.path}.',
          location: location,
        ),
      );
      continue;
    }
    final scratch = <Issue>[];
    final blueprint = await extractSourceBuildBlueprint(
      sourceClass: widget,
      library: widget.library,
      astNodeFor: astNodeFor,
      issues: scratch,
      location: '${assetId.path}#${widget.name}',
      catalog: catalog,
      liftState: true,
    );
    if (blueprint == null) continue;
    final build = blueprint.liftable ?? blueprint;
    final translation = translator.translate(
      build.rootExpression,
      entryId: entry.name,
      sourcePath: assetId.path,
      lineInfo: widget.library.firstFragment.lineInfo,
      rootState: build.state,
      rootParams: build.rootParams,
      rootEventHandlers: build.eventHandlers,
      buildContextParameter: build.buildContextParameter,
      rootInlined: build.inlined,
      hoistInMount: true,
      liftedState: build.liftedState,
      contentFree: build.contentFree,
      rootBuildArguments: build.buildArguments,
    );
    if (translation.issues.any((issue) => !issue.code.isBuildNotice) ||
        translation.dsl.isEmpty) {
      continue;
    }
    final reconstruction = custom == null ? null : await custom();
    final split = SplitWidgetInput(
      custom: reconstruction,
      foreign: foreign,
      mount: ResolvedWidgetMountInput(
        assetId: assetId,
        screen: widget,
        rootParams: build.rootParams,
        constructorParams: build.constructorParams,
        mountConstructorProblem: build.mountConstructorProblem,
        hoisted: translation.hoisted,
        islands: translation.islands,
        split: translation.split,
        buildArguments: build.buildArguments,
      ),
      entry: entry,
      definition: splitDefinition(translation.dsl, entry, {
        for (final param in build.rootParams) param.name,
      }),
      inlined: (
        definitions: translation.widgetDefinitions,
        states: translation.widgetDefinitionStates,
      ),
      origins: [
        ...translation.rfwCatalogConstructorOrigins,
        fmt.RfwCatalogConstructorProvenance(
          constructorName: splitFactoryName(entry.name),
          catalogLibraryNamespace: entry.library.namespace,
          catalogWidgetWireId: _splitWireId(entry),
        ),
        for (final continuation in catalog.widgets)
          if (continuation.name == kBuilderContinuationWidgetName)
            fmt.RfwCatalogConstructorProvenance(
              constructorName: continuation.name,
              catalogLibraryNamespace: continuation.library.namespace,
              catalogWidgetWireId: continuation.wireId,
            ),
      ],
    );
    // A wrapper that can't be generated leaves the widget whole.
    String? omission;
    String? registration;
    try {
      final emitted = emitSplitWidget(split);
      omission = emitted.omissionMessage;
      registration = emitted.registration;
    } on StateError catch (error) {
      omission =
          "`${split.factoryName}` wasn't generated because Restage "
          'failed (${error.message}). Please report this as a Restage bug.';
    }
    if (omission != null) {
      note(
        Issue(
          code: IssueCode.customWidgetNotSplit,
          message: omission,
          location: _classLocation(widget, assetId),
        ),
      );
      continue;
    }
    // Another package's wrapper must render this very definition.
    if (foreign &&
        (registration == null ||
            _committedHash(widget.library, registration) !=
                splitDefinitionHash(split))) {
      note(foreignNote());
      continue;
    }
    splits.add(split);
  }
  return splits;
}

String _classLocation(ClassElement cls, AssetId assetId) {
  final fragment = cls.firstFragment;
  final location = fragment.libraryFragment.lineInfo.getLocation(
    fragment.nameOffset ?? fragment.offset,
  );
  return '${assetId.path}:${location.lineNumber}:${location.columnNumber}';
}

/// The name of the constant beside the wrapper registered as [registration]
/// that holds the hash of the definition it renders.
String splitDefinitionHashName(String registration) =>
    registration.replaceFirst(r'restageSplit$', r'restageSplitDefinition$');

/// The hash of [split]'s delivered definition, as its wrapper's package
/// records it.
String splitDefinitionHash(SplitWidgetInput split) => crypto.sha256
    .convert(
      utf8.encode(
        jsonEncode([
          split.definition,
          [
            for (final name in split.inlined.definitions.keys.toList()..sort())
              [name, split.inlined.definitions[name]],
          ],
          [for (final island in split.mount.islands) island.id],
        ]),
      ),
    )
    .toString()
    .substring(0, 16);

String? _committedHash(LibraryElement library, String registration) {
  final name = splitDefinitionHashName(registration);
  return library.topLevelVariables
      .where((variable) => variable.name == name)
      .firstOrNull
      ?.computeConstantValue()
      ?.toStringValue();
}

/// Whether [library] declares its generated part, where a split widget's
/// wrapper goes.
bool declaresGeneratedPart(LibraryElement library) =>
    library.firstFragment.partIncludes.any(
      (part) => switch (part.uri) {
        DirectiveUriWithRelativeUriString(:final relativeUriString) =>
          relativeUriString.endsWith(kNeutralGeneratedPartSuffix),
        _ => false,
      },
    );

/// The split of each of this package's own catalogued custom widgets that
/// declares its generated part, used by a surface or not: a design-system
/// package ships its wrappers this way. Only widgets in [placed], as
/// `namespace:name`, get a note when they can't split.
Future<List<SplitWidgetInput>> ownSplitWidgets(
  BuildStep buildStep, {
  required Catalog catalog,
  required Set<String> noticeKeys,
  required Set<String> placed,
}) async {
  final collection = await collectRestageWidgetsForPackage(buildStep);
  if (collection == null) return const [];
  Future<AstNode?> astNodeFor(Fragment fragment) =>
      resolvedNodeInLongForm(buildStep.resolver, fragment);
  final classifier = WidgetClassifier(catalog: catalog, astNodeFor: astNodeFor);
  final classes = <String, ClassElement>{};
  for (final entry in collection.widgets) {
    final hash = entry.flutterType.indexOf('#');
    if (hash < 0) continue;
    final asset = AssetId.resolve(
      Uri.parse(entry.flutterType.substring(0, hash)),
    );
    if (asset.package != buildStep.inputId.package) continue;
    final library = await buildStep.resolver.libraryFor(asset);
    final name = entry.flutterType.substring(hash + 1);
    final widget = library.classes.where((cls) => cls.name == name).firstOrNull;
    if (widget == null) continue;
    await classifier.classify(widget);
    classes[customWidgetKey(widget)] = widget;
  }
  if (classes.isEmpty) return const [];
  final classification = ClassificationResult(
    classifications: classifier.results,
    blueprints: classifier.blueprints,
    classes: classes,
  );
  return splitWidgetsOf(
    classification: classification,
    catalog: catalog,
    surfaceLibrary: classes.values.first.library,
    astNodeFor: astNodeFor,
    noticeKeys: noticeKeys,
    placed: placed,
    translator: ExpressionTranslator(
      catalog: catalog,
      helpers: productionPaywallHelperRegistry(),
      customWidgetClassifications: classification.classifications,
      customWidgetBlueprints: classification.blueprints,
    ),
    custom: () async => customReconstructionFor(
      structuredTypes: collection.structuredTypes,
      reconstructionPlans: collection.reconstructionPlans,
      mapPlans: collection.mapPlans,
      recordPlans: collection.recordPlans,
      slotTargets: collection.slotTargets,
      nullableStructuredSlots: collection.nullableStructuredSlots,
    ),
  );
}

// The package's custom value reconstruction, once per build step.
final _packageReconstruction = Expando<Future<CustomReconstruction?>>();

/// The package's custom value reconstruction, computed once per build step.
Future<CustomReconstruction?> packageReconstruction(BuildStep buildStep) =>
    _packageReconstruction[buildStep] ??= () async {
      final collection = await collectRestageWidgetsForPackage(buildStep);
      return collection == null
          ? null
          : customReconstructionFor(
              structuredTypes: collection.structuredTypes,
              reconstructionPlans: collection.reconstructionPlans,
              mapPlans: collection.mapPlans,
              recordPlans: collection.recordPlans,
              slotTargets: collection.slotTargets,
              nullableStructuredSlots: collection.nullableStructuredSlots,
            );
    }();

/// The surface translator's split definitions for [splits], by class key.
Map<String, SplitWidgetDefinitions> splitWidgetDefinitionsOf(
  Iterable<SplitWidgetInput> splits,
) => {
  for (final split in splits)
    customWidgetKey(split.mount.screen): (
      definitions: {
        ...split.inlined.definitions,
        split.catalogName: split.definition,
      },
      states: split.inlined.states,
      origins: split.origins,
      libraries: {
        for (final origin in split.origins)
          if (WidgetLibrary.builtInByNamespace(
                origin.catalogLibraryNamespace,
              ) ==
              null)
            origin.catalogLibraryNamespace,
      },
    ),
};

/// [catalog] with [islands], and each of [splits] with its wrapper and its
/// islands.
Catalog withSplits(
  Catalog catalog,
  Iterable<Island> islands,
  Iterable<SplitWidgetInput> splits,
) => withSplitWidgets(
  withIslands(catalog, [
    ...islands,
    for (final split in splits) ...split.mount.islands,
  ]),
  splits,
);

/// [catalog] with a wrapper entry for each of [splits].
Catalog withSplitWidgets(Catalog catalog, Iterable<SplitWidgetInput> splits) {
  if (splits.isEmpty) return catalog;
  return Catalog(
    schemaVersion: catalog.schemaVersion,
    generatedAt: catalog.generatedAt,
    libraries: catalog.libraries,
    widgets: [
      ...catalog.widgets,
      for (final split in splits)
        WidgetEntry(
          wireId: _splitWireId(split.entry),
          name: split.factoryName,
          library: split.entry.library,
          category: null,
          description: split.entry.description,
          flutterType: '${split.entry.flutterType}${fmt.kSplitWrapperSuffix}',
          childrenSlot: ChildrenSlot.none,
          properties: [
            ..._designProperties(split.entry),
            for (final name in kAppWidgetPlacementArguments)
              PropertyEntry(
                wireId: _wire(
                  'p',
                  '${split.entry.flutterType}${fmt.kSplitWrapperSuffix}/$name',
                ),
                name: name,
                type: name == kPlacementNameArgument
                    ? PropertyType.string
                    : PropertyType.integerList,
                description: name,
              ),
            // The body reads the values the wrapper records, typed here.
            PropertyEntry(
              wireId: _wire(
                'p',
                '${split.entry.flutterType}${fmt.kSplitWrapperSuffix}/$kSplitWidgetScope',
              ),
              name: kSplitWidgetScope,
              type: PropertyType.widgetBuilder,
              description: kSplitWidgetScope,
              required: true,
              builderContract: WidgetBuilderContract(
                parameters: const [
                  WidgetBuilderParameter.buildContext,
                  WidgetBuilderParameter.data,
                ],
                nativeValues: {
                  for (final value in split.mount.hoisted)
                    if (value.nativeContract case final contract?)
                      value.key: WidgetBuilderNativeValue(
                        contract.type,
                        nullable: contract.nullable,
                      ),
                },
              ),
            ),
          ],
          sinceVersion: split.entry.sinceVersion,
        ),
    ],
    structuredTypes: catalog.structuredTypes,
    unions: catalog.unions,
    designTokens: catalog.designTokens,
    exclusions: catalog.exclusions,
    flutterVersion: catalog.flutterVersion,
    compatRules: catalog.compatRules,
  );
}

/// The function that places the split widget [name] the app builds.
String splitAppName(String name) =>
    'restageSplitApp\$${name.replaceAll(RegExp(r'[^A-Za-z0-9_$]'), '_')}';

/// The argument naming where the surface places an app widget.
const String kPlacementNameArgument = 'restageIsland';

/// The argument holding an app widget placement's position in each loop
/// around it, outermost first.
const String kPlacementItemsArgument = 'restageItems';

/// The arguments a design places any app widget with.
const Set<String> kAppWidgetPlacementArguments = {
  kPlacementNameArgument,
  kPlacementItemsArgument,
};

WireId _splitWireId(WidgetEntry entry) =>
    _wire('w', '${entry.flutterType}${fmt.kSplitWrapperSuffix}');

WireId _wire(String kind, String seed) {
  final digest = crypto.sha256.convert(utf8.encode(seed)).toString();
  return WireId(
    '$kind${'${int.parse(digest.substring(0, 7), radix: 16) + 1}'.padLeft(4, '0')}',
  );
}

// The properties a wrapper forwards. An occurrence label stays on the
// widget's own placement, which keeps its measurement identity.
Iterable<PropertyEntry> _designProperties(WidgetEntry entry) =>
    entry.properties.where((p) => p.name != kAnalyticsIdPropertyName);

// [root] with each `data.context.<key>` read outside string literals scoped
// to the wrapper: `args.<key>` for [params], recorded values otherwise.
String _scoped(String root, Set<String> params) {
  const prefix = 'data.context.';
  final out = StringBuffer();
  var index = 0;
  while (index < root.length) {
    final char = root[index];
    if (char == '"' || char == "'") {
      final end = _stringEnd(root, index);
      out.write(root.substring(index, end));
      index = end;
    } else if (root.startsWith(prefix, index)) {
      index += prefix.length;
      final start = index;
      final key = root[index] == '"' || root[index] == "'"
          ? root.substring(start, index = _stringEnd(root, index))
          : _identifier(root, start, (end) => index = end);
      final name = key.startsWith('"') || key.startsWith("'")
          ? jsonDecode(key.replaceAll("'", '"')) as String
          : key;
      out.write(
        params.contains(name) ? 'args.$key' : '$kSplitWidgetScope.values.$key',
      );
    } else {
      out.write(char);
      index += 1;
    }
  }
  return out.toString();
}

String _identifier(String text, int start, void Function(int end) done) {
  var end = start;
  while (end < text.length && RegExp(r'[A-Za-z0-9_$]').hasMatch(text[end])) {
    end += 1;
  }
  done(end);
  return text.substring(start, end);
}

int _stringEnd(String text, int start) {
  final quote = text[start];
  var index = start + 1;
  while (index < text.length && text[index] != quote) {
    index += text[index] == r'\' ? 2 : 1;
  }
  return index + 1;
}

bool _readsContext(Object? value) => switch (value) {
  fmt.DataReference(:final parts) =>
    parts.isNotEmpty && parts.first == 'context',
  fmt.ConstructorCall(:final arguments) => _readsContext(arguments),
  final Map<String, Object?> map => map.values.any(_readsContext),
  final List<Object?> list => list.any(_readsContext),
  fmt.Loop(:final input, :final output) =>
    _readsContext(input) || _readsContext(output),
  fmt.Switch(:final input, :final outputs) =>
    _readsContext(input) ||
        outputs.entries.any(
          (e) => _readsContext(e.key) || _readsContext(e.value),
        ),
  fmt.WidgetBuilderDeclaration(:final widget) => _readsContext(widget),
  fmt.EventHandler(:final eventArguments) => _readsContext(eventArguments),
  fmt.SetStateHandler(:final value) => _readsContext(value),
  _ => false,
};
