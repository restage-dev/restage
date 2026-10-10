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
      'the built-in widget catalog at content version '
          '${manifest.builtInFloor} or later',
    for (final requirement in manifest.requiredLibraries)
      'the app widget library "${requirement.namespace}" at version '
          '${requirement.minVersion} or later',
  ];
  return 'Note for devices: this publication renders only in app builds '
      'that register ${requirements.join(' and ')}. Installs of older app '
      'builds show their configured fallback. This is about device delivery; '
      'dashboard previews depend on a build push instead.';
}
