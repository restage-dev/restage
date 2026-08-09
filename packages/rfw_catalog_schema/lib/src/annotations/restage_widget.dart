import 'package:meta/meta.dart';
import 'package:meta/meta_meta.dart';

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
/// import 'package:rfw_catalog_schema/a2ui.dart' as a2ui;
/// import 'package:rfw_catalog_schema/rfw.dart' as rfw;
///
/// @a2ui.Config.usage('Use for the primary form action.')
/// @RestageWidget(
///   name: 'SubmitButton',
///   library: WidgetLibrary.custom('acme.widgets'),
///   category: WidgetCategory.action,
/// )
/// class SubmitButton extends StatelessWidget {
///   const SubmitButton({
///     super.key,
///     required this.label,
///     required this.onPressed,
///   });
///
///   /// Visible button label.
///   final String label;
///
///   /// Runs the form action.
///   final VoidCallback onPressed;
///
///   @override
///   Widget build(BuildContext context) => GestureDetector(
///         onTap: onPressed,
///         child: Text(label),
///       );
/// }
/// ```
@immutable
@Target({TargetKind.classType})
final class RestageWidget {
  /// Const annotation constructor. [name], [library], and [category] are
  /// required. When [description] is empty, code generation reads the
  /// annotated class's Dart documentation.
  const RestageWidget({
    required this.name,
    required this.library,
    required this.category,
    this.description = '',
    this.childrenSlot = ChildrenSlot.none,
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

  /// Description override for the widget.
  ///
  /// When empty, code generation reads the annotated class's Dart
  /// documentation.
  final String description;

  /// Whether the widget accepts no, a single, or a list of children.
  final ChildrenSlot childrenSlot;

  /// Catalog schema version that introduced this widget. Defaults to 1.
  final int minSchemaVersion;
}
