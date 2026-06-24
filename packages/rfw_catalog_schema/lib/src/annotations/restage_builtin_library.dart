import 'package:meta/meta.dart';

import 'package:rfw_catalog_schema/src/widget_library.dart';

/// Marks a top-level `const List<BuiltinWidgetCuration>` as the curation
/// declaration for a built-in widget library.
///
/// Read at build time by the curation builder, which discovers each
/// annotated list, reflects on every entry's type argument to derive
/// most of the resulting widget entry, merges in the curation overrides,
/// and emits `lib/registry.dart` plus `lib/src/widget_catalog/catalog.json`.
/// Has no runtime effect — annotations are erased outside the builder.
///
/// Customer-registered libraries use `@RestageWidget` on each widget
/// class instead; this annotation targets only the three sibling built-in
/// libraries (`restage_core`, `restage_material`, `restage_cupertino`)
/// and customer-authored design-system curation files that follow the
/// same pattern.
///
/// ```dart
/// @RestageBuiltinLibrary(
///   library: WidgetLibrary.core,
///   version: '0.1.0',
/// )
/// const List<BuiltinWidgetCuration> kCoreCuration = [
///   BuiltinWidgetCuration<Center>(category: WidgetCategory.layout),
///   BuiltinWidgetCuration<Column>(category: WidgetCategory.layout),
///   // ...
/// ];
/// ```
@immutable
final class RestageBuiltinLibrary {
  /// Const constructor.
  const RestageBuiltinLibrary({
    required this.library,
    required this.version,
    this.minSchemaVersion = 1,
  });

  /// Sibling library namespace this curation populates.
  final WidgetLibrary library;

  /// Semver of the package authoring this curation. Surfaced in the
  /// generated `LibraryInfo.version` field.
  final String version;

  /// Catalog schema version this curation requires. Defaults to 1.
  /// Mirrors the `minSchemaVersion` field on `RestageWidget` and
  /// `RestageProperty` for parity across annotations.
  final int minSchemaVersion;
}
