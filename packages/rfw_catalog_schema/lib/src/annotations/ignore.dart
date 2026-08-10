import 'package:meta/meta.dart';
import 'package:meta/meta_meta.dart';
import 'package:rfw_catalog_schema/src/annotations/emit_target.dart';

/// Excludes one constructor input from generated catalog representations.
///
/// Use it for an input the catalog COULD carry but that the application owns
/// — a retry count, a debug label — so it stays a constructor argument the app
/// passes and never becomes part of the remote surface.
///
/// ```dart
/// const FeatureList({
///   super.key,
///   required this.items,
///   @ignore this.maxRetries = 3,
/// });
/// ```
///
/// An input the catalog cannot carry at all needs no annotation: it is
/// excluded automatically and reported. This is only for inputs that would
/// otherwise be included.
///
/// With no argument, the input is excluded from every emit target. Pass a
/// compile-time constant list or set to select individual targets:
///
/// ```dart
/// const FeatureList({
///   @Ignore({EmitTarget.a2ui, EmitTarget.widgetbook})
///   this.debugLabel = '',
/// });
/// ```
///
/// Excluding an input is legal only where leaving the argument out is
/// semantically exact — the generated construction omits it and ordinary Dart
/// applies the same result. It is therefore an error on a required input,
/// which cannot be omitted, and it excludes exactly one input without
/// silencing any other diagnostic.
/// Valid on a constructor parameter or its backing field; the analyzer
/// rejects it elsewhere.
@immutable
@Target({TargetKind.field, TargetKind.parameter})
final class Ignore {
  /// Creates the annotation.
  ///
  /// Omitted or `null` [targets] retains the legacy all-target behavior. A
  /// non-null iterable selects exactly those targets. Code generation accepts
  /// const lists and sets and rejects an explicitly empty selection.
  const Ignore([this.targets]);

  /// Emit targets from which the input is excluded, or `null` for every target.
  final Iterable<EmitTarget>? targets;
}

/// The canonical instance of [Ignore]; see that class for the rules.
const Ignore ignore = Ignore();
