import 'package:meta/meta.dart';

/// One immutable release stamp for a future all-root Measurement cutover.
///
/// The value is deliberately only a selector input. It neither registers a
/// root nor grants a write authority by itself.
@internal
final class MeasurementCutoverGeneration {
  /// Creates one non-negative cutover generation within one release.
  MeasurementCutoverGeneration({
    required this.releaseId,
    required this.cutoverGeneration,
  }) {
    if (releaseId.isEmpty) {
      throw ArgumentError.value(releaseId, 'releaseId', 'Must not be empty');
    }
    if (cutoverGeneration < 0) {
      throw ArgumentError.value(
        cutoverGeneration,
        'cutoverGeneration',
        'Must not be negative',
      );
    }
  }

  /// Immutable release identifier supplied by a future cutover owner.
  final String releaseId;

  /// Monotonic generation within [releaseId].
  final int cutoverGeneration;
}

/// The one whole-root result a cutover selector can choose.
@internal
enum MeasurementCutoverRoot {
  /// The pre-cutover root alone is selected.
  oldOnly,

  /// The replacement root alone is selected.
  newOnly,
}

/// An atomic whole-root selector for a future Measurement cutover.
///
/// A selector has exactly one branch and one immutable generation. It has no
/// independent root flags, fallback branch, or dual-selection state. The
/// caller supplies branch construction so this value remains dormant until a
/// later composition owner explicitly installs it.
@internal
sealed class MeasurementCutoverSelector {
  const MeasurementCutoverSelector._(this.generation);

  /// Selects only the pre-cutover root for [generation].
  factory MeasurementCutoverSelector.oldOnly({
    required MeasurementCutoverGeneration generation,
  }) = _OldOnlyMeasurementCutoverSelector;

  /// Selects only the replacement root for [generation].
  factory MeasurementCutoverSelector.newOnly({
    required MeasurementCutoverGeneration generation,
  }) = _NewOnlyMeasurementCutoverSelector;

  /// Immutable release/cutover stamp shared by the selected root.
  final MeasurementCutoverGeneration generation;

  /// The one root selected by this value.
  MeasurementCutoverRoot get selectedRoot;

  /// Runs exactly one whole-root branch.
  T select<T>({required T Function() oldRoot, required T Function() newRoot});
}

final class _OldOnlyMeasurementCutoverSelector
    extends MeasurementCutoverSelector {
  const _OldOnlyMeasurementCutoverSelector({
    required MeasurementCutoverGeneration generation,
  }) : super._(generation);

  @override
  MeasurementCutoverRoot get selectedRoot => MeasurementCutoverRoot.oldOnly;

  @override
  T select<T>({required T Function() oldRoot, required T Function() newRoot}) =>
      oldRoot();
}

final class _NewOnlyMeasurementCutoverSelector
    extends MeasurementCutoverSelector {
  const _NewOnlyMeasurementCutoverSelector({
    required MeasurementCutoverGeneration generation,
  }) : super._(generation);

  @override
  MeasurementCutoverRoot get selectedRoot => MeasurementCutoverRoot.newOnly;

  @override
  T select<T>({required T Function() oldRoot, required T Function() newRoot}) =>
      newRoot();
}
