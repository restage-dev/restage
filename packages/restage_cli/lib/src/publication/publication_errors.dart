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

/// A declared generated artifact cannot be assembled into its payload.
class PublicationAssemblyException extends PublicationException {
  /// Construct an artifact assembly failure.
  const PublicationAssemblyException(super.message);
}
