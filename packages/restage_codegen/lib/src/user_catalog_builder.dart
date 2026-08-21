import 'dart:async';

import 'package:build/build.dart';
import 'package:restage_codegen/src/restage_widget_walker.dart';
import 'package:restage_codegen/src/user_catalog_allocation.dart';
import 'package:restage_codegen/src/user_catalog_emitter.dart';
import 'package:rfw_catalog_compiler/rfw_catalog_compiler.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Aggregates `@RestageWidget`-annotated classes from the consuming
/// package — scanning every `lib/**.dart` and walking the files that spell a
/// Restage annotation (or an alias of one) — and emits a single
/// `lib/user_catalog.g.dart` declaring `final Catalog kUserCatalog`.
///
/// Customers register the resulting catalog at startup with
/// `Restage.registerWidgetLibrary(...)` (see `restage`).
///
/// Skips emit when no `@RestageWidget` declaration is present. When
/// declarations remain but none participate in RFW, writes an empty catalog
/// so a previously generated aggregate cannot stay stale.
final class UserCatalogBuilder implements Builder {
  /// Const constructor used by the `userCatalogBuilder` factory.
  const UserCatalogBuilder(this.options);

  /// `BuilderOptions` injected by build_runner; currently unused.
  final BuilderOptions options;

  @override
  Map<String, List<String>> get buildExtensions => const {
        r'$lib$': ['user_catalog.g.dart'],
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    final collection = await collectRestageWidgetsForPackage(buildStep);
    if (collection == null) return;

    final logContents =
        await readRootEventLog(buildStep, buildStep.inputId.package);
    final existingEvents = logContents == null
        ? <WireIdEvent>[]
        : parseWireIdEventsJsonl(
            logContents.contents,
            sourceDescription: logContents.sourceDescription,
          );
    final allocation = allocateUserCatalogFromWidgets(
      package: buildStep.inputId.package,
      widgets: collection.widgets,
      structuredTypes: collection.structuredTypes,
      slotTargets: collection.slotTargets,
      stampedCapabilityVersions: collection.stampedCapabilityVersions,
      exclusions: collection.exclusions,
      existingEvents: existingEvents,
    );
    requireNativeCatalog(allocation.catalog);

    await buildStep.writeAsString(
      AssetId(buildStep.inputId.package, 'lib/user_catalog.g.dart'),
      emitUserCatalogDart(allocation.catalog),
    );

    if (allocation.newEvents.isNotEmpty) {
      await appendEventsToRootEventLog(
        package: buildStep.inputId.package,
        events: allocation.newEvents,
        createIfMissing: true,
      );
    }
  }
}
