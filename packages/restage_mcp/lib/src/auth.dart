/// Thrown when no cached credential is available, so the server cannot act on
/// the caller's behalf.
///
/// The message points the user at the in-server `restage_login` tool (no CLI
/// required), or the `restage login` CLI command — either writes the shared
/// credential this server reads.
class NotSignedInException implements Exception {
  /// Construct the exception.
  const NotSignedInException();

  @override
  String toString() =>
      'Not signed in. Call the restage_login tool to sign in (or run '
      '`restage login` from the CLI), then try again.';
}
