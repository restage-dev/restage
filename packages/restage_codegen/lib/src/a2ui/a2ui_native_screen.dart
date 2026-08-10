import 'package:meta/meta.dart';
import 'package:restage_codegen/src/native_screen_source_index.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Target-local A2UI plan for one opaque native screen component.
///
/// [entry] carries the existing A2UI classifier vocabulary. [source] retains
/// the exact analyzer identity and canonical imports needed by native sibling
/// emission. This plan is never a second serialized source artifact.
@immutable
final class A2uiNativeScreen {
  /// Creates one native screen component plan.
  const A2uiNativeScreen({required this.source, required this.entry});

  /// Shared package-index source facts.
  final NativeScreenSource source;

  /// Constructor-derived component plan.
  final WidgetEntry entry;
}
