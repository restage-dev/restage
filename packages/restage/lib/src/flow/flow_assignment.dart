import 'package:meta/meta.dart';

/// The complete server-selected arm an artifact was resolved under.
///
/// This is carried with the artifact, never the fetch attempt, so attribution
/// binds to what actually rendered. An unassigned artifact uses a null
/// [FlowAssignment] rather than an instance with missing fields.
@immutable
class FlowAssignment {
  const FlowAssignment({
    required this.experimentId,
    required this.variantId,
    required this.experimentEpoch,
  });

  final String experimentId;
  final String variantId;
  final int experimentEpoch;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FlowAssignment &&
          experimentId == other.experimentId &&
          variantId == other.variantId &&
          experimentEpoch == other.experimentEpoch;

  @override
  int get hashCode => Object.hash(experimentId, variantId, experimentEpoch);
}
