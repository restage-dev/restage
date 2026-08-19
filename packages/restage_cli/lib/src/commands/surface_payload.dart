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

/// Returns an informational capability note for a generated publication.
String? publishCapabilityWarning(CapabilityManifest manifest) {
  final needsAboveBaseline = manifest.builtInFloor > kBaselineCatalogVersion;
  if (!needsAboveBaseline && manifest.requiredLibraries.isEmpty) return null;

  final requirements = <String>[
    if (needsAboveBaseline)
      'built-in catalog content version ${manifest.builtInFloor}',
    for (final requirement in manifest.requiredLibraries)
      'custom library "${requirement.namespace}" >= v${requirement.minVersion}',
  ];
  return 'Note: this publication requires ${requirements.join(' and ')}. '
      'Clients without those capabilities will use their configured fallback.';
}
