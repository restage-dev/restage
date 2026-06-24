import 'package:meta/meta.dart';

import 'package:rfw_catalog_schema/src/widget_library.dart';

/// Declares that a Dart package contributes catalog entries to a named
/// [library].
///
/// Authored as a top-level annotation on any sentinel const in the
/// customer package's barrel — e.g.
/// `lib/restage_imports.dart`. The compiler walks the annotated
/// package looking for `@RestageWidget`-annotated classes,
/// `@RestageStructuredType` declarations, `@RestageUnionVariant`
/// registrations, and `@RestageFactoryVariant` registrations, and
/// emits a catalog entry per discovered element.
///
/// ```dart
/// @RestageLibrary(
///   library: WidgetLibrary.custom('acme.design_system'),
///   package: 'acme_design_system',
/// )
/// const _restageImportSentinel = 0;
/// ```
///
/// The optional [package] field names the source package URI the
/// compiler walks for catalog entries — useful when the annotation
/// lives in a barrel that re-exports another package's symbols.
///
/// Declare [capabilityVersion] once your widgets are delivered to surfaces:
///
/// ```dart
/// @RestageLibrary(
///   library: WidgetLibrary.custom('acme.design_system'),
///   package: 'acme_design_system',
///   capabilityVersion: 1,
/// )
/// const _restageImportSentinel = 0;
/// ```
@immutable
final class RestageLibrary {
  /// Const constructor.
  const RestageLibrary({
    required this.library,
    this.package,
    this.capabilityVersion,
  }) : assert(
          capabilityVersion == null || capabilityVersion >= 1,
          'capabilityVersion must be a positive monotonic version (>= 1) when '
          'set',
        );

  /// Library namespace this package contributes to.
  final WidgetLibrary library;

  /// Source package URI the compiler walks for catalog entries.
  /// `null` walks the current package.
  final String? package;

  /// The library's **capability version** — a monotonic integer you increment
  /// whenever you add a widget or make a render-affecting change. It lets the
  /// delivery layer compute, per surface, the minimum version of your library a
  /// client must have installed to render that surface faithfully.
  ///
  /// This is **NOT your pub package's semantic version** — it is a separate,
  /// monotonic integer that only ever goes up (start at `1`). Treat a catalog
  /// version as a cumulative render-support set: every widget present at
  /// version N stays renderable at every version ≥ N; an incompatible change to
  /// a widget allocates a new identity rather than reusing the old one.
  ///
  /// Optional so a library can exist before it is delivered. It becomes
  /// required the moment a surface references one of the library's widgets: the
  /// build fails if a *referenced* library has not declared a
  /// [capabilityVersion]. An unreferenced library that omits it is left alone.
  final int? capabilityVersion;
}
