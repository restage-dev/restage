import 'dart:async';

import 'package:build/build.dart';
import 'package:restage_codegen/src/restage_widget_walker.dart';
import 'package:restage_codegen/src/user_factory_emitter.dart';

/// Aggregates `@RestageWidget`-annotated classes from every `lib/**.dart`
/// file in the consuming package and emits a single
/// `lib/user_factories.g.dart` containing per-widget `LocalWidgetBuilder`
/// closures plus a one-call `registerRestageCustomerWidgets()` helper.
///
/// The customer's `main()` calls the generated helper once at startup;
/// every widget annotated in the package becomes available to RFW blobs
/// without any hand-written factory plumbing.
///
/// Skips emit when no `@RestageWidget`-annotated classes are present or
/// every entry is structurally non-emittable. After removing the last
/// such class, run `dart run build_runner clean` to delete a previously
/// emitted `user_factories.g.dart` (build_runner does not auto-clean
/// source outputs whose declaring builder later opts out).
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
    final widgets = await collectRestageWidgetsForPackage(buildStep);
    if (widgets == null) return;

    final source = emitUserFactoriesDart(
      widgets,
      onSkip: (skipped) => log.warning(
        '@RestageWidget(name: ${skipped.name}) on ${skipped.flutterType} '
        'declares a shape the factory emitter cannot currently generate '
        'mechanically (e.g. childrenSlot without a canonical child '
        'property, unsupported synthetic strategy, malformed decomposition '
        'recipe). Skipping; the widget will appear in user_catalog.g.dart '
        'but not in user_factories.g.dart, so rfw blobs referencing it '
        'will render a "widget not found" error at runtime. Register a '
        'hand-written RestageWidgetFactory for it, or adjust the '
        'annotation so the emitter can produce it.',
      ),
    );
    if (source == null) return;

    await buildStep.writeAsString(
      AssetId(buildStep.inputId.package, 'lib/user_factories.g.dart'),
      source,
    );
  }
}
