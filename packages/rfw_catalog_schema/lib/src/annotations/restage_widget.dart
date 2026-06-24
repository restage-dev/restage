import 'package:meta/meta.dart';

import 'package:rfw_catalog_schema/src/widget_library.dart';
import 'package:rfw_catalog_schema/src/widget_metadata.dart';

/// Marks a widget class as a customer-registered widget for inclusion
/// in the catalog.
///
/// Read at build time by the code-generation builder to extract widget
/// metadata into the merged catalog. Has no runtime effect — annotations
/// are erased outside the builder. Curated built-in libraries author
/// their entries directly in `lib/registry.dart` and do not use this
/// annotation.
///
/// Example:
/// ```dart
/// @RestageWidget(
///   name: 'ElevatedButton',
///   library: WidgetLibrary.material,
///   category: WidgetCategory.action,
///   description: 'A standard call-to-action button.',
///   fires: [WidgetEventName.onPressed],
///   childrenSlot: ChildrenSlot.single,
/// )
/// class ElevatedButton extends StatelessWidget { /* ... */ }
/// ```
@immutable
final class RestageWidget {
  /// Const annotation constructor. All non-list fields default to
  /// schema-safe values; `name`, `library`, `category`, and
  /// `description` are required.
  const RestageWidget({
    required this.name,
    required this.library,
    required this.category,
    required this.description,
    this.fires = const [],
    this.childrenSlot = ChildrenSlot.none,
    @Deprecated(
      "Annotate the widget class with @Deprecated('...') instead; the catalog "
      'captures it as structured deprecation.',
    )
    this.deprecatedSince,
    this.minSchemaVersion = 1,
  });

  /// Catalog key. Must match the class name (e.g. `'ElevatedButton'`,
  /// `'CupertinoButton'`) so codegen can disambiguate via import path.
  final String name;

  /// Which sibling curated library this widget belongs to. Required so
  /// authors declare design language explicitly.
  final WidgetLibrary library;

  /// Sub-grouping within the library. Drives editor palette placement.
  final WidgetCategory category;

  /// Single-source-of-truth doc string. Editor uses for tooltips,
  /// codegen for diagnostic messages, doc-comment generation pulls
  /// from here.
  final String description;

  /// Event names this widget can fire (e.g.
  /// `[WidgetEventName.onPressed]`).
  final List<WidgetEventName> fires;

  /// Whether the widget accepts no, a single, or a list of children.
  final ChildrenSlot childrenSlot;

  /// Catalog version where this widget became deprecated. `null` if
  /// active.
  ///
  /// Deprecated: annotate the widget class with Dart's `@Deprecated('...')`
  /// instead — the catalog captures that as the structured, on-the-wire
  /// deprecation status. This plain-string marker is not serialized.
  @Deprecated(
    "Annotate the widget class with @Deprecated('...') instead; the catalog "
    'captures it as structured deprecation.',
  )
  final String? deprecatedSince;

  /// Catalog schema version that introduced this widget. Defaults to 1.
  final int minSchemaVersion;
}
