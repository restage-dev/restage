/// Base class for failures while loading or assembling generated publication
/// metadata.
class PublicationException implements Exception {
  /// Construct a publication failure with a user-facing message.
  const PublicationException(this.message);

  /// User-facing diagnostic and remediation.
  final String message;

  @override
  String toString() => message;
}

/// A generated publication manifest is missing, invalid, or not fresh.
class PublicationManifestException extends PublicationException {
  /// Construct a manifest loading failure.
  const PublicationManifestException(super.message);
}

/// No generated publication output exists for the package at all.
///
/// Distinguished from other manifest failures so a read-only surface can
/// report "nothing generated yet" without treating it as stale or ambiguous
/// output.
class PublicationGenerationRequiredException
    extends PublicationManifestException {
  /// Construct a missing-generation failure.
  const PublicationGenerationRequiredException(super.message);
}

/// A declared generated artifact cannot be assembled into its payload.
class PublicationAssemblyException extends PublicationException {
  /// Construct an artifact assembly failure.
  const PublicationAssemblyException(super.message);
}

/// A generated bundle cannot be read or does not match its locator metadata.
class PublicationBundleException extends PublicationException {
  /// Construct a bundle-reader failure.
  const PublicationBundleException(super.message);
}
