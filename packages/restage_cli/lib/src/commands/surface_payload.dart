import 'package:restage_cli/src/publication/publication_errors.dart';
import 'package:restage_shared/restage_shared.dart';

/// Backwards-compatible name for a generated publication assembly failure.
class SurfacePayloadException extends PublicationAssemblyException {
  /// Construct a user-facing payload failure.
  const SurfacePayloadException(super.message);
}

/// Unions the verified sidecar requirements for a flow.
///
/// Each namespace appears once and carries the greatest minimum version
/// required by any screen in the closure. The result is sorted for canonical
/// payload construction.
List<LibraryRequirement> unionRequiredLibraries(
  Iterable<List<LibraryRequirement>> perScreen,
) {
  final maxByNamespace = <String, int>{};
  for (final requirements in perScreen) {
    for (final requirement in requirements) {
      final existing = maxByNamespace[requirement.namespace];
      if (existing == null || requirement.minVersion > existing) {
        maxByNamespace[requirement.namespace] = requirement.minVersion;
      }
    }
  }
  return [
    for (final namespace in maxByNamespace.keys.toList()..sort())
      LibraryRequirement(
        namespace: namespace,
        minVersion: maxByNamespace[namespace]!,
      ),
  ];
}
