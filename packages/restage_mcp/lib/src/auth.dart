import 'package:http/http.dart' as http;
import 'package:restage_cli/api.dart';

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

/// Resolve an authenticated [RestageApi] from the shared cached credential.
///
/// Reads the credential from [store]; when none exists, throws
/// [NotSignedInException]. Otherwise builds a [RestageApi] bound to the
/// endpoint the credential was minted against — the credential authenticates
/// only that origin, so the stored endpoint is authoritative.
///
/// [httpClient] is injectable for testing; when omitted, [RestageApi] creates
/// its own client (which the caller is responsible for closing).
///
/// Propagates [InsecureEndpointException] when the stored endpoint would
/// transport the credential over an insecure channel.
Future<RestageApi> resolveAuthenticatedApi({
  required FileCredentialStore store,
  http.Client? httpClient,
}) async {
  final credential = await store.read();
  if (credential == null) {
    throw const NotSignedInException();
  }
  return RestageApi(
    endpoint: Uri.parse(credential.endpoint),
    credential: credential,
    httpClient: httpClient,
  );
}
