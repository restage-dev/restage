import 'package:meta/meta.dart';
import 'package:meta/meta_meta.dart';

/// Excludes one constructor input from the generated catalog.
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
  const Ignore();
}

/// The canonical instance of [Ignore]; see that class for the rules.
const Ignore ignore = Ignore();
