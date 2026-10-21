import 'package:meta/meta.dart';
import 'package:restage_shared/restage_shared.dart' show Surface;

/// The experiment assignment that selected a successfully rendered surface.
///
/// These identifiers are inert. They describe the served choice and carry no
/// assignment authority or application identity.
@immutable
final class SurfaceAssignment {
  /// Creates an immutable served-assignment value.
  const SurfaceAssignment({
    required this.experimentId,
    required this.experimentRevisionId,
    required this.experimentEpochId,
    required this.variantId,
  });

  /// Stable experiment identifier.
  final String experimentId;

  /// Revision of the experiment definition that made the assignment.
  final String experimentRevisionId;

  /// Experiment allocation epoch that made the assignment.
  final String experimentEpochId;

  /// Stable identifier of the served experiment variant.
  final String variantId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SurfaceAssignment &&
          other.experimentId == experimentId &&
          other.experimentRevisionId == experimentRevisionId &&
          other.experimentEpochId == experimentEpochId &&
          other.variantId == variantId;

  @override
  int get hashCode => Object.hash(
        experimentId,
        experimentRevisionId,
        experimentEpochId,
        variantId,
      );
}

/// Immutable render identity captured when an event is emitted.
@immutable
final class SurfaceEventAttribution {
  /// Creates a surface-event attribution snapshot.
  const SurfaceEventAttribution({
    required this.surfaceId,
    required this.surfaceType,
    this.surfaceVersion,
    this.assignment,
  });

  /// Stable identifier of the surface host.
  final String surfaceId;

  /// Product surface category.
  final Surface surfaceType;

  /// Exact rendered-content version, when a presentation has committed.
  final String? surfaceVersion;

  /// Served experiment assignment, when the committed render was assigned.
  final SurfaceAssignment? assignment;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SurfaceEventAttribution &&
          other.surfaceId == surfaceId &&
          other.surfaceType == surfaceType &&
          other.surfaceVersion == surfaceVersion &&
          other.assignment == assignment;

  @override
  int get hashCode =>
      Object.hash(surfaceId, surfaceType, surfaceVersion, assignment);
}
