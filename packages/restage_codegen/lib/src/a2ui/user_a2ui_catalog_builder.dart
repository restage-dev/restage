import 'dart:async';
import 'dart:convert';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:build/build.dart';
import 'package:glob/glob.dart';
import 'package:restage_codegen/src/a2ui/a2ui_catalog_adapter.dart';
import 'package:restage_codegen/src/a2ui/a2ui_dart_emitter.dart';
import 'package:restage_codegen/src/a2ui/a2ui_native_screen.dart';
import 'package:restage_codegen/src/a2ui/a2ui_schema_node.dart';
import 'package:restage_codegen/src/a2ui/a2ui_schema_semantics.dart';
import 'package:restage_codegen/src/a2ui/a2ui_seam_assembly.dart';
import 'package:restage_codegen/src/emit_utils.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/native_screen_source_index.dart';
import 'package:restage_codegen/src/restage_widget_package_facts.dart';
import 'package:restage_codegen/src/syntax_diagnostics.dart';
import 'package:restage_codegen/src/target_config_reader.dart';
import 'package:restage_codegen/src/widget_constructor_facts.dart';
import 'package:restage_codegen/src/widget_visitor.dart';
import 'package:rfw_catalog_compiler/rfw_catalog_compiler.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// The generated A2UI catalog file. Declares
/// `List<CatalogItem> buildRestageCatalogItems()` — the function the consumer
/// passes to genui's `Catalog(...)`.
const _catalogAssetName = 'generated/restage_a2ui_catalog.g.dart';

/// The companion capability-stamp document — the
/// `{restageCapability, a2uiCatalog}` JSON the app-side check reads.
const _stampAssetName = 'generated/restage_a2ui_catalog.a2ui.json';

/// Placeholder pub version for a customer library's catalog envelope. The A2UI
/// stamp reads only `capabilityVersion`; the pub `version` is not part of the
/// A2UI capability axis, so a deterministic placeholder keeps the emit
/// byte-stable (matching the customer-catalog emitter's convention).
const _customerLibraryVersion = '0.0.0';

/// Aggregates the consuming package's `@RestageWidget` source into a genui
/// **A2UI** catalog (the autonomous-codegen emit target), emitting
/// `lib/generated/restage_a2ui_catalog.g.dart`
/// (`buildRestageCatalogItems()`) plus the colocated
/// `lib/generated/restage_a2ui_catalog.a2ui.json` capability stamp.
///
/// Customer widgets and native `@ScreenSource` components are read from the
/// consuming package's own source. Widgets retain the customer-catalog walk;
/// screens enter through the shared exact-identity package index and reuse the
/// same constructor-input projection and analyzer-fed A2UI seams.
///
/// The emitted catalog is **customer-authored only**: one combined genui
/// `Catalog` contains the package's customer widgets and opaque native screens.
/// Built-in catalog coverage is separate and never contributes to this output.
///
/// Each contributing customer library must declare
/// `@RestageLibrary(capabilityVersion:)`; the version is read off the barrel
/// and carried into the stamp's custom-library capability axis (the A2UI
/// emitter fails loud if a contributing custom library declares none).
///
/// Skips emit when the package contributes neither customer widgets nor native
/// screens. This builder is **opt-in** (it is not applied to dependents): the
/// emitted code imports the genui runtime, so a consumer enables it explicitly
/// only when they want an A2UI catalog.
///
/// The toolchain stays runtime-free: the emit is string emission, so this
/// builder never imports the genui runtime — only the *generated* code does,
/// and that compiles in the consumer's package (which declares the genui
/// dependency).
final class UserA2uiCatalogBuilder implements Builder {
  /// Const constructor used by the `userA2uiCatalogBuilder` factory.
  const UserA2uiCatalogBuilder(this.options);

  /// `BuilderOptions` injected by the build system; currently unused.
  final BuilderOptions options;

  @override
  Map<String, List<String>> get buildExtensions => const {
        r'$lib$': [_catalogAssetName, _stampAssetName],
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    final walk = await _walkCustomerWidgets(buildStep);
    final nativeScreens = await _projectNativeScreens(buildStep);
    if (walk.widgets.isEmpty &&
        nativeScreens.components.isEmpty &&
        !walk.hasWidgetDeclarations) {
      return;
    }

    final catalog = _customerOnlyCatalog(walk);
    final allComponents = <A2uiWidgetElement>[
      ...walk.widgets,
      ...nativeScreens.widgetElements,
    ];
    final usageByComponent = <String, String>{
      ...walk.usageByWidget,
      ...nativeScreens.usageByComponent,
    };
    final seams = assembleA2uiSeams(
      allComponents,
      writeBackValuesByWidget: <String, Map<String, String>>{
        ...walk.writeBackValuesByWidget,
        ...nativeScreens.writeBackValuesByComponent,
      },
    );

    // A structured property the A2UI emitter cannot represent (a data class
    // with an unrepresentable field) surfaces as a seam issue — fail it loud,
    // never let the widget silently drop from the catalog. Mirrors the
    // walk-issue surfacing in [_walkCustomerWidgets].
    if (seams.issues.isNotEmpty) {
      for (final issue in seams.issues) {
        log.severe(issue.toString());
      }
      throw StateError(
        '${seams.issues.length} customer component A2UI seam issue(s) '
        'detected; '
        'see log above.',
      );
    }

    // The classifier's coverage record is the remaining gate: a component or
    // required field the classifier scopes out would otherwise vanish from
    // both outputs (or emit uncompilable code) under a green build. Enforce it
    // as loud as the walk / seam gates above.
    final plan = classifyA2uiCatalogDart(
      catalog,
      nativeScreens: nativeScreens.components,
      richShapes: seams.richShapes,
      eventSeam: seams.eventSeam,
      pairingSeam: seams.pairingSeam,
    );
    _enforceLoudCoverage(
      plan,
      allComponents,
      nativeScreenNames: {
        for (final component in nativeScreens.components) component.entry.name,
      },
    );

    // Build the complete stamped registration contract once. Its content
    // address and finalized producer guidance are then shared by both emitted
    // artifacts, so runtime and standalone identity cannot diverge.
    final registration = emitA2uiCatalog(
      catalog,
      nativeScreens: nativeScreens.components,
      richShapes: seams.richShapes,
      eventSeam: seams.eventSeam,
      pairingSeam: seams.pairingSeam,
      usageByWidget: usageByComponent,
    );
    final emittedDart = emitA2uiCatalogDart(
      catalog,
      registration: registration,
      nativeScreens: nativeScreens.components,
      richShapes: seams.richShapes,
      eventSeam: seams.eventSeam,
      pairingSeam: seams.pairingSeam,
      usageByWidget: usageByComponent,
    );
    final emitted = StringBuffer(emittedDart);
    writePropertyExclusionReport(
      emitted,
      <PropertyExclusion>[...walk.exclusions, ...nativeScreens.exclusions],
    );
    final dart = formatGeneratedDart(emitted.toString());
    await buildStep.writeAsString(
      AssetId(buildStep.inputId.package, 'lib/$_catalogAssetName'),
      dart,
    );

    final stamp = registration.toJson();
    await buildStep.writeAsString(
      AssetId(buildStep.inputId.package, 'lib/$_stampAssetName'),
      const JsonEncoder.withIndent('  ').convert(stamp),
    );
  }

  Future<_NativeScreenWalk> _projectNativeScreens(BuildStep buildStep) async {
    final index = await loadNativeScreenSourceIndex(
      buildStep,
      consumer: NativeScreenSourceConsumer.a2ui,
      validateA2uiNamespace: true,
    );
    final components = <A2uiNativeScreen>[];
    final widgetElements = <A2uiWidgetElement>[];
    final usageByComponent = <String, String>{};
    final writeBackValuesByComponent = <String, Map<String, String>>{};
    final exclusions = <PropertyExclusion>[];
    final issues = <Issue>[];
    const planningLibrary = WidgetLibrary.custom(
      'restage.native_screen_source',
    );

    for (final source in index.screens) {
      final projection = projectConstructorComponent(
        element: source.element,
        assetId: source.sourceAsset,
        constructorFacts: source.constructorFacts,
        componentName: source.id,
        flutterType: source.classIdentity,
        description: source.description ?? '',
        sinceVersion: source.version,
        planningLibrary: planningLibrary,
        target: WidgetVisitorTarget.a2ui,
      );
      issues.addAll(projection.issues);
      exclusions.addAll(projection.exclusions);
      final component = A2uiNativeScreen(
        source: source,
        entry: projection.entry,
      );
      components.add(component);
      widgetElements.add((entry: projection.entry, element: source.element));
      final usage = source.a2uiTargetConfig.usage;
      if (usage != null && usage.isNotEmpty) {
        usageByComponent[source.id] = usage;
      }
      writeBackValuesByComponent[source.id] =
          source.a2uiTargetConfig.writeBackValues;
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
        '${failures.length} native screen A2UI projection issue(s) detected; '
        'see log above.',
      );
    }

    return (
      components: components,
      widgetElements: widgetElements,
      usageByComponent: usageByComponent,
      writeBackValuesByComponent: writeBackValuesByComponent,
      exclusions: exclusions,
    );
  }

  /// Walks every `lib/**.dart` asset for the consumer's `@RestageWidget`
  /// classes — projecting each to a [WidgetEntry] via the public
  /// [visitRestageWidgets] vocabulary while capturing its resolved
  /// [ClassElement] (the seam-assembly's analyzer input) in the same pass — and
  /// reads each contributing library's `@RestageLibrary(capabilityVersion:)`.
  /// Surfaces any walk issue (an unsupported property type, a duplicate name)
  /// loud as a failed build, mirroring the customer-catalog walk.
  Future<_CustomerWalk> _walkCustomerWidgets(BuildStep buildStep) async {
    final widgets = <A2uiWidgetElement>[];
    final capabilityVersions = <WidgetLibrary, int?>{};
    final usageByWidget = <String, String>{};
    final writeBackValuesByWidget = <String, Map<String, String>>{};
    final exclusions = <PropertyExclusion>[];
    final issues = <Issue>[];

    final sources = <ResolvedPackageLibrary>[];
    await for (final assetId in buildStep.findAssets(Glob('lib/**.dart'))) {
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
    sources.sort(
      (left, right) => left.assetId.path.compareTo(right.assetId.path),
    );
    final packageFacts = indexRestageWidgetPackage(sources);

    for (final source in sources) {
      final assetId = source.assetId;
      final library = source.library;

      final result = visitRestageWidgetsInPackage(
        library,
        assetId,
        target: WidgetVisitorTarget.a2ui,
        packageFacts: packageFacts,
      );
      issues.addAll(result.issues);
      exclusions.addAll(result.exclusions);
      for (final entry in result.widgets) {
        // A customer `@RestageWidget` must not claim a built-in namespace — it
        // would bypass the custom-library capability axis (built-in namespaces
        // are reserved for the built-in content floor). Reject it loud.
        if (WidgetLibrary.builtInByNamespace(entry.library.namespace) != null) {
          issues.add(
            Issue(
              code: IssueCode.invalidWidgetClass,
              message: "@RestageWidget '${entry.name}' declares the built-in "
                  'namespace "${entry.library.namespace}", which is reserved.',
              location: '${assetId.path}#${entry.name}',
            ),
          );
          continue;
        }
        final className = entry.flutterType.split('#').last;
        final element =
            library.classes.where((c) => c.name == className).firstOrNull;
        if (element == null) {
          // The projection came from this library's classes, so a missing class
          // is an internal inconsistency — fail loud, never silently drop.
          issues.add(
            Issue(
              code: IssueCode.analyzerResolutionFailed,
              message: "could not resolve the class '$className' for "
                  "@RestageWidget '${entry.name}'.",
              location: '${assetId.path}#${entry.name}',
            ),
          );
          continue;
        }
        widgets.add((entry: entry, element: element));

        final constructorFacts = projectWidgetConstructorFacts(
          element,
          assetId,
          readWidgetConstructorFacts(element, assetId),
          target: EmitTarget.a2ui,
        );
        final targetConfig = readA2uiTargetConfig(
          element,
          assetId,
          constructorInputs: constructorFacts.inputs,
        );
        issues.addAll(targetConfig.issues);
        final usage = targetConfig.usage;
        if (usage != null && usage.isNotEmpty) {
          // Keying by the bare `entry.name` (not `(namespace, name)`) is safe
          // here: `emitA2uiCatalog`'s flat-namespace de-dup fails the build
          // loud on any cross-library duplicate name, so a name collision
          // that would mis-key a usage fragment can never reach a shipped
          // artifact — it is caught upstream before this map is consumed.
          usageByWidget[entry.name] = usage;
        }
        writeBackValuesByWidget[entry.name] = targetConfig.writeBackValues;
      }

      // Surface genuine syntactic errors: the asset resolved with
      // `allowSyntaxErrors: true`, so a malformed token whose parser recovery
      // yields a structurally-valid declaration would otherwise be walked into
      // a clean catalog with the bad token silently dropped.
      final resolved = await library.session.getResolvedLibraryByElement(
        library,
      );
      if (resolved is ResolvedLibraryResult && resolved.units.isNotEmpty) {
        issues.addAll(syntacticErrorIssues(resolved, sourcePath: assetId.path));
      }

      // Read the `@RestageLibrary` capability version, surfacing the walk's own
      // diagnostics (malformed / reserved namespace) and failing on a
      // conflicting redeclaration rather than nondeterministic last-wins.
      final walk = packageFacts.walksByAsset[assetId]!;
      for (final diagnostic in walk.diagnostics) {
        // Only ERROR-severity diagnostics fail the build; a walk WARNING (e.g.
        // `restageLibraryForeignWidget` — a re-exported `@RestageWidget` this
        // per-file catalog walk never picks up anyway) is surfaced non-fatally,
        // so a legitimate multi-package barrel is not over-rejected.
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
      final declaration = walk.declaration;
      if (declaration != null) {
        if (capabilityVersions.containsKey(declaration.library) &&
            capabilityVersions[declaration.library] !=
                declaration.capabilityVersion) {
          issues.add(
            Issue(
              code: IssueCode.duplicateId,
              message: 'conflicting @RestageLibrary capabilityVersion for '
                  '"${declaration.library.namespace}": '
                  '${capabilityVersions[declaration.library]} vs '
                  '${declaration.capabilityVersion}.',
              location: assetId.path,
            ),
          );
        }
        capabilityVersions[declaration.library] = declaration.capabilityVersion;
      }
    }

    // Cross-file `(library, name)` duplicate detection — `visitRestageWidgets`
    // only catches within-file duplicates.
    final byKey = <String, List<A2uiWidgetElement>>{};
    for (final w in widgets) {
      byKey
          .putIfAbsent('${w.entry.library.namespace}#${w.entry.name}', () => [])
          .add(w);
    }
    for (final dup in byKey.entries.where((e) => e.value.length > 1)) {
      issues.add(
        Issue(
          code: IssueCode.duplicateWidgetName,
          message: 'Multiple @RestageWidget classes share name in ${dup.key}: '
              '${dup.value.map((w) => w.entry.flutterType).join(', ')}.',
          location: 'lib/',
        ),
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
        '${failures.length} customer widget issue(s) detected; see log above.',
      );
    }

    // Deterministic emit order — by (library namespace, name) — so the
    // generated catalog is byte-stable regardless of asset discovery order.
    widgets.sort((a, b) {
      final byLib =
          a.entry.library.namespace.compareTo(b.entry.library.namespace);
      return byLib != 0 ? byLib : a.entry.name.compareTo(b.entry.name);
    });

    return (
      widgets: widgets,
      hasWidgetDeclarations: packageFacts.hasWidgetDeclarations,
      capabilityVersions: capabilityVersions,
      usageByWidget: usageByWidget,
      writeBackValuesByWidget: writeBackValuesByWidget,
      exclusions: exclusions,
    );
  }

  /// Builds the customer-only A2UI catalog: `libraries` and `widgets` come from
  /// the source walk alone (the single authoritative customer source), with
  /// each customer library carrying its declared `capabilityVersion`. Built-in
  /// catalog state never contributes — structured types, unions, tokens, and
  /// compat rules are empty, so a customer `@RestageWidget` either lowers into
  /// this catalog or the build fails loud; nothing about the built-ins can
  /// define, weaken, enlarge, or block that output.
  ///
  /// Metadata is deterministic (schema-version constant, epoch `generatedAt`,
  /// no `flutterVersion`) so the emit is byte-stable — the A2UI emitters read
  /// none of it, and the capability floor derives to the baseline with no
  /// built-in widgets present.
  /// Enforces the fail-loud contract over the classifier's coverage record —
  /// the classify-level analogue of the walk / seam gates above. In this
  /// customer-only catalog every component is an authored `@RestageWidget` or
  /// `@ScreenSource` (there are no built-ins to legitimately scope out), so:
  ///
  ///  * a DROPPED component is a silent loss of a declared source — fatal;
  ///  * an OMITTED field whose default-constructor parameter is REQUIRED would
  ///    generate a constructor call missing that argument — uncompilable
  ///    generated code — fatal. The constructor formal (not the catalog's
  ///    annotation-fed `required` flag) is the source of truth here: a
  ///    parameter the constructor requires may still carry
  ///    `@RestageProperty(required: false)` on the catalog;
  ///  * an OMITTED OPTIONAL field narrows the source's advertised contract but
  ///    still compiles and renders (the constructor default applies) — a
  ///    warning naming the widget, field, and reason;
  ///  * an emitted SINGLE-CHILD slot lowers through a nullable child lookup
  ///    (an A2UI child is a component-id reference that need not resolve), so
  ///    a NON-NULLABLE child parameter the catalog does not mark required and
  ///    has no reconstructed constructor default would receive a nullable
  ///    expression — uncompilable generated code — fatal, with the actionable
  ///    fix (declare `Widget?`, mark the property required, or use a public
  ///    reconstructable const default).
  void _enforceLoudCoverage(
    A2uiDartCatalogPlan plan,
    List<A2uiWidgetElement> widgets, {
    required Set<String> nativeScreenNames,
  }) {
    final elementByComponent = <String, ClassElement>{
      for (final source in widgets) source.entry.name: source.element,
    };
    String sourceAnnotation(String componentName) =>
        nativeScreenNames.contains(componentName)
            ? '@ScreenSource'
            : '@RestageWidget';
    final fatal = <String>[];

    for (final drop in plan.coverage.droppedWidgets) {
      final field = drop.fieldName;
      final annotation = sourceAnnotation(drop.widgetName);
      fatal.add(
        "The $annotation '${drop.widgetName}'"
        "${field == null ? '' : " (property '$field')"} cannot be lowered "
        'into the A2UI catalog and would be silently dropped: '
        '${_coverageReasonHint(drop.reason, field)}',
      );
    }

    for (final omission in plan.coverage.omittedFields) {
      final hint = _coverageReasonHint(omission.reason, omission.fieldName);
      final annotation = sourceAnnotation(omission.widgetName);
      final formal = _constructorFormal(
        elementByComponent[omission.widgetName],
        omission.fieldName,
      );
      if (formal?.isRequired ?? false) {
        fatal.add(
          "The property '${omission.fieldName}' on $annotation "
          "'${omission.widgetName}' cannot be lowered into the A2UI catalog, "
          'and its constructor parameter is required — the generated code '
          'would call the constructor without a required argument and fail '
          'to compile: $hint',
        );
      } else {
        log.warning(
          "The optional property '${omission.fieldName}' on $annotation "
          "'${omission.widgetName}' is omitted from the A2UI catalog (the "
          'constructor default applies): $hint',
        );
      }
    }

    // An emitted single-child slot: the generated child expression is nullable
    // unless the catalog marks the property required (which emits a null
    // assertion), so a non-nullable, not-catalog-required child parameter
    // cannot compile.
    for (final widget in plan.widgets) {
      for (final field in widget.fields) {
        if (field.emission case A2uiChildField(slot: A2uiChildNode())) {
          if (field.property.required) continue;
          final constructorDefault = field.property.constructorDefault;
          if (constructorDefault != null &&
              constructorDefault is! DartConstNull) {
            continue;
          }
          final formal = _constructorFormal(
            elementByComponent[widget.entry.name],
            field.property.name,
          );
          if (formal != null &&
              formal.type.nullabilitySuffix != NullabilitySuffix.question) {
            fatal.add(
              "The child slot '${field.property.name}' on "
              '${sourceAnnotation(widget.entry.name)} '
              "'${widget.entry.name}' is a non-nullable Widget the catalog "
              'does not mark required. An A2UI child is a component-id '
              'reference that need not resolve, so the generated code would '
              'pass a nullable child to a non-nullable parameter and fail to '
              "compile. Declare the parameter 'Widget?', mark the property "
              '@RestageProperty(required: true) to require a child, or use a '
              'public reconstructable const default.',
            );
          }
        }
      }
    }

    if (fatal.isEmpty) return;
    fatal.forEach(log.severe);
    throw StateError(
      '${fatal.length} customer component A2UI coverage issue(s) detected; '
      'see log above.',
    );
  }

  /// The default generative constructor's formal parameter binding [fieldName]
  /// on [element], or `null` when the class, constructor, or parameter is
  /// absent. For both supported source kinds the projected catalog property
  /// name equals the constructor parameter name.
  FormalParameterElement? _constructorFormal(
    ClassElement? element,
    String fieldName,
  ) =>
      element?.constructors
          .where(
            (c) => !c.isFactory && const {null, '', 'new'}.contains(c.name),
          )
          .firstOrNull
          ?.formalParameters
          .where((p) => p.name == fieldName)
          .firstOrNull;

  Catalog _customerOnlyCatalog(_CustomerWalk walk) {
    final customerLibraries = <WidgetLibrary>{
      for (final w in walk.widgets) w.entry.library,
    };
    return Catalog(
      schemaVersion: kSupportedSchemaVersion,
      generatedAt: '1970-01-01T00:00:00Z',
      libraries: {
        for (final library in customerLibraries)
          library: LibraryInfo(
            version: _customerLibraryVersion,
            capabilityVersion: walk.capabilityVersions[library],
          ),
      },
      widgets: [for (final w in walk.widgets) w.entry],
    );
  }
}

/// The customer-widget walk result: the `(WidgetEntry, ClassElement)` pairs the
/// seam-assembly + emitter consume, each contributing library's declared
/// `@RestageLibrary(capabilityVersion:)` (`null` when undeclared — the emitter
/// fails loud if such a library contributes components), and each widget's
/// `@a2ui.Config.usage` note (only widgets with a non-empty usage are
/// present — the emit falls back to the widget's description for the rest).
typedef _CustomerWalk = ({
  List<A2uiWidgetElement> widgets,
  bool hasWidgetDeclarations,
  Map<WidgetLibrary, int?> capabilityVersions,
  Map<String, String> usageByWidget,
  Map<String, Map<String, String>> writeBackValuesByWidget,
  List<PropertyExclusion> exclusions,
});

typedef _NativeScreenWalk = ({
  List<A2uiNativeScreen> components,
  List<A2uiWidgetElement> widgetElements,
  Map<String, String> usageByComponent,
  Map<String, Map<String, String>> writeBackValuesByComponent,
  List<PropertyExclusion> exclusions,
});

/// A customer-actionable explanation for a classifier coverage [reason]: what
/// the A2UI catalog cannot express about the widget/property, and what to
/// change. [fieldName] disambiguates unsupported-type and envelope-key
/// reasons.
String _coverageReasonHint(A2uiDartCoverageReason reason, String? fieldName) {
  switch (reason) {
    case A2uiDartCoverageReason.unsupportedInteractiveCallback:
      return 'the callback signature has no declarative lowering (supported: '
          'a zero-argument void callback, or a one-argument void callback '
          'over a scalar or a list of scalars).';
    case A2uiDartCoverageReason.ambiguousWritePairing:
      return 'the write-back callback cannot be paired unambiguously with a '
          'value property (more than one write-back callback, or more than '
          'one matching-type value property); name the value property '
          'explicitly with @a2ui.Config.writeBackValue on the callback or '
          '@a2ui.Config.writeBackValues on the widget.';
    case A2uiDartCoverageReason.uncontrolledInteractiveWidget:
      return 'the interactive callback has no matching-type value property '
          'to control; add a value property of the callback value type so '
          'the component is data-model-controlled.';
    case A2uiDartCoverageReason.writeBackValueNotBound:
      return 'the value property paired with the write-back callback is not '
          'a bindable data field.';
    case A2uiDartCoverageReason.invalidExplicitWritePairing:
      return 'the @a2ui.Config write-back pairing does not name a '
          'matching-type bindable value property on the widget.';
    case A2uiDartCoverageReason.requiredUnsupportedPropertyType:
    case A2uiDartCoverageReason.optionalUnsupportedPropertyType:
      if (fieldName != null &&
          isReservedA2uiComponentEnvelopeField(fieldName)) {
        return 'the property name is reserved by the flattened GenUI '
            "component envelope ('id', 'component'); rename the property. "
            'Nested rich-data members may keep either name.';
      }
      return 'the property type is not supported by the A2UI catalog.';
    case A2uiDartCoverageReason.unsupportedChildrenSlot:
      return 'the child slot is not the canonical shape (a single-child '
          "widget must declare a 'child' Widget property; a multi-child "
          "widget a 'children' List<Widget> property).";
    case A2uiDartCoverageReason.missingEnumType:
      return 'the enum property does not carry a resolvable enum type.';
    case A2uiDartCoverageReason.eventProperty:
      return 'the callback property has no declarative A2UI lowering.';
    case A2uiDartCoverageReason.themeDefault:
      return 'the property default is theme-sourced, which the A2UI catalog '
          'does not carry.';
    case A2uiDartCoverageReason.nativeDecomposeUnsupported:
      return 'the property is consumed by a decomposition recipe the A2UI '
          'catalog does not reconstruct.';
    case A2uiDartCoverageReason.syntheticUnsupported:
      return 'the property uses a synthetic construction strategy with no '
          'A2UI projection.';
    case A2uiDartCoverageReason.unconstructableBuiltIn:
      return 'the widget constructor requires an argument the catalog cannot '
          'supply.';
  }
}
