import 'dart:async';

import 'package:build/build.dart';
import 'package:restage_codegen/src/restage_widget_walker.dart';
import 'package:restage_codegen/src/user_catalog_allocation.dart';
import 'package:restage_codegen/src/user_catalog_emitter.dart';
import 'package:rfw_catalog_compiler/rfw_catalog_compiler.dart';

/// Aggregates `@RestageWidget`-annotated classes from every `lib/**.dart`
/// file in the consuming package and emits a single
/// `lib/user_catalog.g.dart` declaring `final Catalog kUserCatalog`.
///
/// Customers register the resulting catalog at startup with
/// `Restage.registerWidgetLibrary(...)` (see `restage`).
///
/// Skips emit when no `@RestageWidget`-annotated classes are present —
/// packages without customer widgets don't acquire a generated catalog
/// file. After removing the last `@RestageWidget` class, run
/// `dart run build_runner clean` to delete a previously emitted
/// `user_catalog.g.dart` (build_runner does not auto-clean source
/// outputs whose declaring builder later opts out).
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
    final widgets = await collectRestageWidgetsForPackage(buildStep);
    if (widgets == null) return;

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
      widgets: widgets,
      existingEvents: existingEvents,
    );

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
