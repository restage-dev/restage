import 'package:meta/meta.dart';
import 'package:meta/meta_meta.dart';

import 'package:rfw_catalog_schema/src/annotations/restage_library.dart';
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
///
/// `lib/restage_imports.dart`:
/// ```dart
/// import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
///
/// export 'widgets/submit_button.dart';
///
/// final class AcmeWidgets extends WidgetLibrary {
///   const AcmeWidgets();
///
///   @override
///   final String namespace = 'acme.widgets';
/// }
///
/// const WidgetLibrary acmeWidgets = AcmeWidgets();
///
/// @RestageLibrary(library: acmeWidgets, capabilityVersion: 1)
/// const restageCatalog = 0;
/// ```
///
/// `lib/widgets/submit_button.dart`:
/// ```dart
/// import 'package:flutter/material.dart';
/// import 'package:rfw_catalog_schema/a2ui.dart' as a2ui;
/// import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
///
/// @a2ui.Config.usage('Use for the primary form action.')
/// @RestageWidget()
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
  /// Const annotation constructor.
  ///
  /// When [name] is omitted, code generation uses the annotated Dart class
  /// name. When [library] is omitted, ownership is inferred from the exact
  /// [RestageLibrary] barrel that exports the class. An omitted [category]
  /// leaves the widget at the library root. When [description] is empty, code
  /// generation reads the annotated class's Dart documentation.
  const RestageWidget({
    this.name,
    this.library,
    this.category,
    this.description = '',
    this.minSchemaVersion = 1,
  });

  /// Optional catalog-key override.
  ///
  /// Omission uses the exact Dart class name. An explicitly supplied value
  /// must contain non-whitespace characters.
  final String? name;

  /// Optional sibling-library override.
  ///
  /// Omission resolves ownership from exact [RestageLibrary] export
  /// membership.
  final WidgetLibrary? library;

  /// Optional sub-grouping within the library.
  ///
  /// Omission keeps the widget ungrouped at the library root.
  final WidgetCategory? category;

  /// Description override for the widget.
  ///
  /// When empty, code generation reads the annotated class's Dart
  /// documentation.
  final String description;

  /// Catalog schema version that introduced this widget. Defaults to 1.
  final int minSchemaVersion;
}
