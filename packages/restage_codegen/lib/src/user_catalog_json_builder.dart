import 'dart:async';

import 'package:build/build.dart';
import 'package:restage_codegen/src/restage_widget_walker.dart';
import 'package:restage_codegen/src/user_catalog_allocation.dart';
import 'package:rfw_catalog_compiler/rfw_catalog_compiler.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Aggregates `@RestageWidget`-annotated classes from every `lib/**.dart` file
/// in the consuming package and emits `lib/src/widget_catalog/catalog.json` —
/// the build-time catalog the paywall/onboarding transpile reads to resolve a
/// registered custom widget as a catalog reference instead of attempting to
/// inline it.
///
/// Derives from the SAME allocation the runtime catalog (`user_catalog.g.dart`)
/// uses, so the build-time (referenced) and runtime (resolves the reference)
/// wire IDs agree by construction. Reads the append-only wire-ID event log to
/// seed the allocation but never appends to it — the runtime-catalog builder
/// owns the append, and a fresh id computes identically here by deterministic
/// replay from the same seed.
///
/// Skips emit when no `@RestageWidget`-annotated classes are present. The
/// curated registry-driven catalog packages disable this builder (they emit
/// their own `catalog.json`).
final class UserCatalogJsonBuilder implements Builder {
  /// Const constructor used by the `userCatalogJsonBuilder` factory.
  const UserCatalogJsonBuilder(this.options);

  /// `BuilderOptions` injected by build_runner; currently unused.
  final BuilderOptions options;

  @override
  Map<String, List<String>> get buildExtensions => const {
        r'$lib$': ['src/widget_catalog/catalog.json'],
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

    // Emit only — never append to the event log. The runtime-catalog builder
    // owns the append; running after it means the log is already complete here,
    // and the ids are deterministic regardless of order.
    await buildStep.writeAsString(
      AssetId(
        buildStep.inputId.package,
        'lib/src/widget_catalog/catalog.json',
      ),
      encodeCatalog(allocation.catalog),
    );
  }
}
