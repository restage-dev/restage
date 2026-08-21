import 'dart:async';

import 'package:build/build.dart';
import 'package:restage_codegen/src/customer_map_plan.dart';
import 'package:restage_codegen/src/customer_record_plan.dart';
import 'package:restage_codegen/src/customer_structured_reconstruction.dart';
import 'package:restage_codegen/src/restage_widget_walker.dart';
import 'package:restage_codegen/src/user_factory_emitter.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Aggregates `@RestageWidget`-annotated classes from the consuming
/// package — scanning every `lib/**.dart` and walking the files that spell a
/// Restage annotation (or an alias of one) — and emits a single
/// `lib/user_factories.g.dart` containing per-widget `LocalWidgetBuilder`
/// closures plus a one-call `registerRestageCustomerWidgets()` helper.
///
/// The customer's `main()` calls the generated helper once at startup;
/// every widget annotated in the package becomes available to RFW blobs
/// without any hand-written factory plumbing.
///
/// Skips emit when no `@RestageWidget`-annotated classes are present. If the
/// shared walker admits a widget that factory emission then rejects, the build
/// fails as an internal coherence error before any partial output is written.
/// When declarations remain but every widget is disabled for RFW, emits a
/// valid no-op registration source so a previous aggregate cannot stay stale.
final class UserFactoryBuilder implements Builder {
  /// Const constructor used by the `userFactoryBuilder` factory.
  const UserFactoryBuilder(this.options);

  /// `BuilderOptions` injected by build_runner; currently unused.
  final BuilderOptions options;

  @override
  Map<String, List<String>> get buildExtensions => const {
        r'$lib$': ['user_factories.g.dart'],
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    final collection = await collectRestageWidgetsForPackage(buildStep);
    if (collection == null) return;

    // The admitted customer structured graph is threaded to the inline
    // reconstructor: a widget carrying a renderable customer structured
    // property is emitted to the catalog AND reconstructed here (admit + decode
    // together). An admitted widget the reconstructor can't handle is a
    // predicate gap (excluded upstream), never a factory skip.
    final source = emitAdmittedUserFactoriesDart(
      collection.widgets,
      structuredTypes: collection.structuredTypes,
      slotTargets: collection.slotTargets,
      nullableStructuredSlots: collection.nullableStructuredSlots,
      reconstructionPlans: collection.reconstructionPlans,
      mapPlans: collection.mapPlans,
      recordPlans: collection.recordPlans,
      stampedCapabilityVersions: collection.stampedCapabilityVersions,
    );

    await buildStep.writeAsString(
      AssetId(buildStep.inputId.package, 'lib/user_factories.g.dart'),
      source,
    );
  }
}

/// Emits factories for widgets already admitted by the production walker.
///
/// This is the only production emission seam. It always converts a lower-level
/// emitter skip into a hard coherence failure before the builder writes output.
/// [emitUserFactoriesDart] remains permissive only for lower-level tests and
/// tooling that inspect historical or manually assembled catalog shapes.
String emitAdmittedUserFactoriesDart(
  List<WidgetEntry> widgets, {
  List<StructuredEntry> structuredTypes = const [],
  Map<String, String> slotTargets = const {},
  Set<String> nullableStructuredSlots = const {},
  Map<String, ReconstructionPlan> reconstructionPlans = const {},
  Map<String, MapPlan> mapPlans = const {},
  Map<String, RecordPlan> recordPlans = const {},
  Map<String, int> stampedCapabilityVersions = const {},
}) {
  final source = emitUserFactoriesDart(
    widgets,
    structuredTypes: structuredTypes,
    slotTargets: slotTargets,
    nullableStructuredSlots: nullableStructuredSlots,
    reconstructionPlans: reconstructionPlans,
    mapPlans: mapPlans,
    recordPlans: recordPlans,
    stampedCapabilityVersions: stampedCapabilityVersions,
    onSkip: _throwAdmittedFactoryCoherenceFailure,
  );
  return source ?? emitEmptyUserFactoriesDart();
}

Never _throwAdmittedFactoryCoherenceFailure(WidgetEntry skipped) {
  throw StateError(
    'Internal Restage catalog/factory coherence failure: admitted '
    'catalog widget "${skipped.name}" (${skipped.flutterType}) was rejected '
    'by customer factory emission. Catalog names default to the Dart class '
    'and use an explicit override only when supplied. The shared admission '
    'predicate and factory emitter are out of sync; report this as a '
    'restage_codegen bug. No generated output was written.',
  );
}
