import 'package:meta/meta.dart';
import 'package:meta/meta_meta.dart';

/// How generated Widgetbook stories vary finite widget state.
enum StoryExpansion {
  /// Emit the default story plus one story for each non-default axis value.
  independent,

  /// Emit every combination of the configured finite axis values.
  cartesian,
}

/// Widgetbook-specific configuration for generated customer-widget stories.
///
/// Import this annotation from `package:restage/widgetbook.dart` (or the
/// corresponding `rfw_catalog_schema` / `restage_shared` entrypoint) with a
/// target prefix:
///
/// ```dart
/// import 'package:flutter/widgets.dart';
/// import 'package:restage/restage.dart';
/// import 'package:restage/widgetbook.dart' as wb;
///
/// /// Displays whether a status is enabled.
/// @RestageWidget()
/// @wb.Config(
///   expansion: wb.StoryExpansion.cartesian,
///   maxStories: 12,
/// )
/// class StatusCard extends StatelessWidget {
///   const StatusCard({super.key, required this.enabled});
///
///   /// Whether the status is enabled.
///   @wb.Config.values([true, false])
///   final bool enabled;
///
///   @override
///   Widget build(BuildContext context) => Text(enabled ? 'On' : 'Off');
/// }
/// ```
///
/// [expansion] and [maxStories] configure a widget class. Independent expansion
/// is the default. The generator allows 32 stories per widget by default;
/// [maxStories] may deliberately lower or raise that limit, but must be greater
/// than zero and no greater than the absolute ceiling of 256.
///
/// [storyValues] and [allValues] configure an individual `bool` or enum
/// constructor property. The Restage generator validates those placements and
/// the selected values.
@immutable
@Target({TargetKind.classType, TargetKind.field})
final class Config {
  /// Creates a Widgetbook configuration overlay.
  const Config({
    this.enabled,
    this.expansion,
    this.maxStories,
    this.storyValues,
    this.allValues = false,
  });

  /// Controls whether the annotated customer widget gets Widgetbook stories.
  // ignore: avoid_positional_boolean_parameters
  const Config.enabled(bool enabled) : this(enabled: enabled);

  /// Configures how finite property axes are expanded into stories.
  const Config.expansion(StoryExpansion expansion) : this(expansion: expansion);

  /// Configures the maximum generated story count for one widget.
  ///
  /// The package default is 32. An override must be greater than zero and no
  /// greater than the absolute ceiling of 256.
  const Config.maxStories(int maxStories) : this(maxStories: maxStories);

  /// Selects finite story values for the annotated property.
  ///
  /// An empty list selects no values beyond the constructor default. If every
  /// configured axis is empty, both expansion policies emit only the default
  /// story.
  const Config.values(List<Object?> storyValues)
      : this(storyValues: storyValues);

  /// Selects every finite value of the annotated `bool` or enum property.
  const Config.allValues() : this(allValues: true);

  /// Whether this customer widget participates in Widgetbook story emit.
  ///
  /// `null` keeps the default enabled behavior. This key is valid only on an
  /// `@RestageWidget` class.
  final bool? enabled;

  /// Story expansion policy, or `null` to use independent expansion.
  final StoryExpansion? expansion;

  /// Per-widget story-count limit override (package default 32, ceiling 256).
  final int? maxStories;

  /// Authored finite values for one property, in story order.
  final List<Object?>? storyValues;

  /// Whether every finite value of one property is selected.
  final bool allValues;
}
