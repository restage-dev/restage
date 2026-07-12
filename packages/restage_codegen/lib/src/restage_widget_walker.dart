import 'dart:async';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:glob/glob.dart';
import 'package:restage_codegen/src/customer_structured_admissibility.dart';
import 'package:restage_codegen/src/customer_structured_reconstruction.dart';
import 'package:restage_codegen/src/factory_emitter.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/syntax_diagnostics.dart';
import 'package:restage_codegen/src/widget_visitor.dart';
import 'package:rfw_catalog_compiler/rfw_catalog_compiler.dart'
    show DiagnosticSeverity, walkRestageLibrary;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// The admitted result of a per-package `@RestageWidget` walk: the
/// RFW-renderable widgets plus the customer structured graph threaded to both
/// `$lib$` builders.
///
/// `structuredTypes` is filtered to the transitive closure reachable from the
/// admitted widgets, and `slotTargets` maps each structured slot to its target
/// `sourceType` (the identity the sentinel `structuredRef` does not carry); the
/// catalog builder allocates + resolves both from this one seed, and the
/// factory builder reconstructs from the same.
typedef RestageWidgetCollection = ({
  List<WidgetEntry> widgets,
  List<StructuredEntry> structuredTypes,
  Map<String, String> slotTargets,
  Set<String> nullableStructuredSlots,
  Map<String, ReconstructionPlan> reconstructionPlans,
  Map<String, int> stampedCapabilityVersions,
});

/// Walks every `lib/**.dart` asset in [buildStep]'s package for
/// `@RestageWidget`-annotated classes, aggregates the resulting
/// `WidgetEntry`s, detects cross-file `(library, name)` duplicates, and
/// returns the deduplicated list in `(library namespace, name)` order
/// for byte-deterministic emit.
///
/// Returns `null` when no `@RestageWidget`-annotated classes are present
/// so the caller can short-circuit emission.
///
/// Throws [StateError] after `log.severe`-ing each [Issue] when any
/// issues surface during the walk (annotation field gaps, unsupported
/// property types, duplicate widget names across files). The thrown
/// error surfaces as a failed build via `testBuilder`'s `result.errors`.
///
/// Both the customer-catalog and customer-factory builders consume this
/// helper so the per-package walk runs once worth of structural work per
/// builder rather than two near-identical implementations drifting in
/// step with each other.
Future<RestageWidgetCollection?> collectRestageWidgetsForPackage(
  BuildStep buildStep,
) async {
  final widgets = <WidgetEntry>[];
  final issues = <Issue>[];
  // The customer structured graph, aggregated across the package's assets (each
  // asset's discovery is per-file; the closure spans files).
  final structuredTypes = <StructuredEntry>[];
  final slotTargets = <String, String>{};
  final nullableStructuredSlots = <String>{};
  final localUnrenderable = <String, String>{};
  final widgetUnrenderable = <String, String>{};
  final reconstructionPlans = <String, ReconstructionPlan>{};
  // Declared `@RestageLibrary(capabilityVersion:)` per customer library (from
  // the barrel walk), used to stamp a structured-admitting library's floor. A
  // conflicting redeclaration across files fails loud (not last-wins).
  final declaredCapabilityVersions = <String, int?>{};

  await for (final assetId in buildStep.findAssets(Glob('lib/**.dart'))) {
    // Do not pre-filter with `resolver.isLibrary` — its implementation
    // calls `libraryFor` internally, so a guard would double the resolver
    // cost on every Dart asset. Catch `NonLibraryAssetException` instead.
    final LibraryElement library;
    try {
      library = await buildStep.resolver.libraryFor(
        assetId,
        allowSyntaxErrors: true,
      );
    } on NonLibraryAssetException {
      continue;
    }
    final result = visitRestageWidgets(library, assetId);
    widgets.addAll(result.widgets);
    issues.addAll(result.issues);
    structuredTypes.addAll(result.structuredTypes);
    slotTargets.addAll(result.slotTargets);
    nullableStructuredSlots.addAll(result.nullableStructuredSlots);
    localUnrenderable.addAll(result.localUnrenderable);
    widgetUnrenderable.addAll(result.widgetUnrenderable);
    reconstructionPlans.addAll(result.reconstructionPlans);

    // The asset resolved with `allowSyntaxErrors: true`, so a malformed token
    // whose parser error-recovery yields a structurally-valid declaration
    // could otherwise be walked into a clean catalog with the bad token
    // silently dropped. Surface genuine syntactic errors so a malformed
    // customer-widget source fails the build rather than emitting a degraded
    // entry.
    final resolved = await library.session.getResolvedLibraryByElement(library);
    if (resolved is ResolvedLibraryResult && resolved.units.isNotEmpty) {
      issues.addAll(syntacticErrorIssues(resolved, sourcePath: assetId.path));
    }

    // The customer library's declared `@RestageLibrary(capabilityVersion:)`,
    // if any (mirrors the A2UI builder's barrel read + conflict-detection).
    final walk = walkRestageLibrary(barrel: library, barrelAssetId: assetId);
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
    final declaration = walk.declaration;
    if (declaration != null) {
      final namespace = declaration.library.namespace;
      final existing = declaredCapabilityVersions[namespace];
      if (declaredCapabilityVersions.containsKey(namespace) &&
          existing != declaration.capabilityVersion) {
        issues.add(
          Issue(
            code: IssueCode.duplicateId,
            message: 'conflicting @RestageLibrary capabilityVersion for '
                '"$namespace": $existing vs ${declaration.capabilityVersion}.',
            location: assetId.path,
          ),
        );
      }
      declaredCapabilityVersions[namespace] = declaration.capabilityVersion;
    }
  }

  // Flutter-enum importability (async — needs `widgets.dart` resolved): a
  // customer structured field whose FLUTTER enum type is NOT in
  // `package:flutter/widgets.dart`'s export namespace can't be named BARE in
  // the generated factory (the only flutter surface it imports; a flutter enum
  // is not alias-imported), so its owning structured type is excluded-loud.
  // FAIL-CLOSED: if `widgets.dart` can't be resolved (should never happen —
  // customer widgets import flutter), exclude EVERY flutter enum field rather
  // than admit-then-fail-to-compile. The EXPORT NAMESPACE — not the enum's
  // src-path — is ground truth (`Axis` is `src/painting/` yet exported;
  // `TextInputAction` is `src/services/` yet not).
  await _excludeUnexportedFlutterEnums(
    structuredTypes: structuredTypes,
    resolver: buildStep.resolver,
    localUnrenderable: localUnrenderable,
  );

  // The ONE admission point (the single-admission invariant): a customer
  // structured widget renders on the RFW path only if its ENTIRE transitive
  // structured closure is renderable. `computeAdmission` excludes-loud (build
  // continues) exactly the unrenderable ones — each with a NAMED reason (an
  // unsupported inner field, a non-canonical/unfaithful reconstruction ctor, an
  // unnameable referenced type) — and they still render in the A2UI catalog.
  // Both `$lib$` builders consume this same admitted result, so they can't
  // diverge on what is in the catalog. This is a NON-FATAL exclusion (logged),
  // distinct from the unsupported-type / duplicate-name issues below which fail
  // the build.
  // The inline-reconstruction context for the whole-widget emittability check
  // (aliases are irrelevant to emittability, so an empty map suffices). A
  // widget's structured prop counts as emittable only if its type is a
  // discovered structured type with a reconstruction plan.
  final emittabilityContext = (
    structuredBySourceType: {
      for (final structured in structuredTypes)
        structured.sourceType: structured,
    },
    plansBySourceType: reconstructionPlans,
    slotTargets: slotTargets,
    nullableStructuredSlots: nullableStructuredSlots,
    aliases: const <String, String>{},
  );
  final admission = computeAdmission(
    widgets: widgets,
    structuredTypes: structuredTypes,
    slotTargets: slotTargets,
    localUnrenderable: localUnrenderable,
    widgetUnrenderable: widgetUnrenderable,
    // Close the admit-then-skip gap: a structured-prop widget whose OTHER
    // props aren't all factory-emittable is excluded here, not
    // admitted-then-skipped (catalog + factory share this one admitted set).
    isWholeWidgetEmittable: (widget) =>
        isFactoryEmittable(widget, customer: emittabilityContext),
  );
  for (final excluded in admission.excluded) {
    log.info(
      'Customer widget ${excluded.widget.library.namespace}#'
      '${excluded.widget.name} is excluded from the RFW catalog/factory: '
      '${excluded.reason}. It still renders in the A2UI catalog.',
    );
  }
  final admittedWidgets = admission.admitted;

  // Thread only the structured types reachable from an ADMITTED widget (deduped
  // by sourceType — a shared type is discovered once per referencing file).
  final seenStructured = <String>{};
  final admittedStructuredTypes = <StructuredEntry>[
    for (final structured in structuredTypes)
      if (admission.admittedSourceTypes.contains(structured.sourceType) &&
          seenStructured.add(structured.sourceType))
        structured,
  ];

  // The visitor catches duplicate (library, name) pairs within a single
  // file. Cross-file collisions only surface here, after aggregation.
  final byKey = <String, List<WidgetEntry>>{};
  for (final w in admittedWidgets) {
    byKey.putIfAbsent('${w.library.namespace}#${w.name}', () => []).add(w);
  }
  for (final entry in byKey.entries.where((e) => e.value.length > 1)) {
    final declarations = entry.value.map((w) => w.flutterType).join(', ');
    issues.add(
      Issue(
        code: IssueCode.duplicateWidgetName,
        message: 'Multiple @RestageWidget classes across this package '
            'share name in ${entry.key}: $declarations.',
        location: 'lib/',
      ),
    );
  }

  // Customer-library capabilityVersion stamp (the capability-floor fold-in): a
  // library with an admitted widget that RENDERS a CUSTOMER structured property
  // is using a NEW render capability, so its declared capabilityVersion raises
  // the delivery floor (an under-capable client fails closed at the SDK
  // pre-render check). Such a library MUST declare one (fail loud). A scalar /
  // built-in-structured-only library is NEVER forced and stays byte-stable.
  final structuredSourceTypes = {
    for (final structured in structuredTypes) structured.sourceType,
  };
  final structuredAdmittingLibraries = <String>{};
  for (final widget in admittedWidgets) {
    for (final prop in widget.properties) {
      if (!isCustomerStructuredPropertySlot(prop)) continue;
      final target =
          slotTargets[structuredSlotKey(widget.flutterType, prop.name)];
      if (target != null && structuredSourceTypes.contains(target)) {
        structuredAdmittingLibraries.add(widget.library.namespace);
      }
    }
  }
  final stampedCapabilityVersions = <String, int>{};
  for (final namespace in structuredAdmittingLibraries) {
    final declared = declaredCapabilityVersions[namespace];
    if (declared == null) {
      issues.add(
        Issue(
          code: IssueCode.customLibraryMissingCapabilityVersion,
          message: 'Customer library "$namespace" renders a customer '
              'structured property (a new render capability) but declares no '
              'capability version. Add `capabilityVersion:` to its '
              '@RestageLibrary so the delivery-time floor rejects an '
              'under-capable client (a monotonic integer, not your pub '
              'package version).',
          location: namespace,
        ),
      );
    } else {
      stampedCapabilityVersions[namespace] = declared;
    }
  }
  // A library that explicitly DECLARES a capabilityVersion has it stamped even
  // when it is not structured-admitting: a scalar custom widget referenced in a
  // surface still needs a delivery floor derivable from the catalog. Declaring
  // stays optional — an undeclared library is simply not stamped and stays
  // byte-stable (a reference to it is diagnosed at capability derivation).
  for (final entry in declaredCapabilityVersions.entries) {
    final declared = entry.value;
    if (declared != null) {
      stampedCapabilityVersions.putIfAbsent(entry.key, () => declared);
    }
  }

  if (issues.isNotEmpty) {
    for (final issue in issues) {
      log.severe(issue.toString());
    }
    throw StateError(
      '${issues.length} customer widget issue(s) detected; see log above.',
    );
  }

  if (admittedWidgets.isEmpty) return null;

  final ordered = admittedWidgets.toList()
    ..sort((a, b) {
      final byLib = a.library.namespace.compareTo(b.library.namespace);
      if (byLib != 0) return byLib;
      return a.name.compareTo(b.name);
    });
  return (
    widgets: ordered,
    structuredTypes: admittedStructuredTypes,
    slotTargets: slotTargets,
    nullableStructuredSlots: nullableStructuredSlots,
    reconstructionPlans: {
      for (final plan in reconstructionPlans.entries)
        if (admission.admittedSourceTypes.contains(plan.key))
          plan.key: plan.value,
    },
    stampedCapabilityVersions: stampedCapabilityVersions,
  );
}

/// Marks (in [localUnrenderable]) any structured type in [structuredTypes] with
/// a FLUTTER enum field the generated factory cannot name — a flutter/dart enum
/// whose symbol is NOT in `package:flutter/widgets.dart`'s export namespace
/// (the only flutter surface the generated factory imports; a flutter enum is
/// named bare). Customer enums (import-aliased) are not checked. FAIL-CLOSED:
/// if `widgets.dart` can't be resolved, every flutter enum field is treated as
/// non-importable (excluded), never admit-then-fail-to-compile.
Future<void> _excludeUnexportedFlutterEnums({
  required List<StructuredEntry> structuredTypes,
  required Resolver resolver,
  required Map<String, String> localUnrenderable,
}) async {
  // Nothing to check unless some structured field references a flutter enum.
  final hasFlutterEnum = structuredTypes
      .any((s) => s.fields.any((f) => _flutterEnumRef(f) != null));
  if (!hasFlutterEnum) return;

  final widgetsLib = await _resolveWidgetsLibrary(resolver);
  for (final structured in structuredTypes) {
    for (final field in structured.fields) {
      final ref = _flutterEnumRef(field);
      if (ref == null) continue; // not a flutter/dart enum
      // Importable iff `widgets.dart` EXPORTS this exact enum (its exported
      // symbol resolves to the SAME defining library, rejecting a same-name
      // collision). A null `widgetsLib` (fail-closed) or a missing/mismatched
      // symbol excludes.
      final exportedFrom =
          widgetsLib?.exportNamespace.get2(ref.symbolName)?.library?.identifier;
      if (exportedFrom != ref.libraryUri) {
        localUnrenderable.putIfAbsent(
          structured.sourceType,
          () => 'the field "${field.name}" has a Flutter enum '
              '"${ref.symbolName}" (${ref.libraryUri}) not exported by '
              'package:flutter/widgets.dart, so the generated factory cannot '
              'name it',
        );
      }
    }
  }
}

/// The `enumRef` of [field] WHEN it is a FLUTTER/dart enum field
/// (`package:flutter/…` or `dart:…`), else `null` (a scalar, a nested
/// structured value, or a CUSTOMER enum — customer enums are import-aliased and
/// always nameable, so they are not checked against widgets.dart's exports).
DartTypeRef? _flutterEnumRef(StructuredField field) {
  if (field.valueShape case final EnumShape shape) {
    final uri = shape.enumRef.libraryUri;
    if (uri.startsWith('package:flutter/') || uri.startsWith('dart:')) {
      return shape.enumRef;
    }
  }
  return null;
}

/// The resolved `package:flutter/widgets.dart` library element, or `null` when
/// it cannot be resolved (the caller then fail-closes — excludes every flutter
/// enum field). Resolved through the build [resolver] (not a raw session,
/// whose `getLibraryByUri` is unreliable for a non-input library under a
/// `$lib$` builder). Queried per-symbol via its `exportNamespace` (a recording
/// namespace populated on lookup, so `definedNames2` is not enumerable).
Future<LibraryElement?> _resolveWidgetsLibrary(Resolver resolver) async {
  final widgetsAsset = AssetId('flutter', 'lib/widgets.dart');
  try {
    if (!await resolver.isLibrary(widgetsAsset)) return null;
    return await resolver.libraryFor(widgetsAsset, allowSyntaxErrors: true);
  } on Object {
    return null;
  }
}
