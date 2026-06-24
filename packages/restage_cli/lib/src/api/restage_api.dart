import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:restage_cli/src/credentials/credential.dart';

/// Non-200 response from a backend RPC. The caller decides whether the
/// status code maps to a user-error (1) or system-error (2) exit code.
@experimental
class RestageApiException implements Exception {
  /// Construct with the response's status code and body.
  const RestageApiException(this.statusCode, this.body);

  /// HTTP status code returned by the backend.
  final int statusCode;

  /// Raw response body. Often a typed `SerializableException` payload
  /// the caller can decode to surface a more specific error.
  final String body;

  @override
  String toString() => 'RestageApiException(status=$statusCode, body=$body)';
}

/// Thrown when a caller asks for an endpoint that would transport
/// bearer credentials over an insecure channel. The CLI refuses on
/// principle — only `https://` and `http://` against loopback hosts
/// are permitted.
@experimental
class InsecureEndpointException implements Exception {
  /// Construct with the offending [endpoint].
  const InsecureEndpointException(this.endpoint);

  /// The endpoint URL the caller asked to use.
  final Uri endpoint;

  @override
  String toString() =>
      'Refusing to send credentials over an insecure endpoint: '
      '$endpoint. Use https:// (or an http:// loopback URL for local '
      'development).';
}

/// Returns true when [endpoint] is safe to send credentials to.
///
/// `https://` is always accepted; `http://` is accepted only when the
/// host is a loopback IP address or a known loopback hostname.
/// Other schemes are rejected.
@experimental
bool isAcceptableTransport(Uri endpoint) {
  if (endpoint.scheme == 'https') return true;
  if (endpoint.scheme == 'http') {
    final host = endpoint.host.toLowerCase();
    final address = InternetAddress.tryParse(host);
    if (address != null) {
      return address.isLoopback || _isIpv4MappedLoopback(address);
    }
    return _loopbackHostnames.contains(host);
  }
  return false;
}

const _loopbackHostnames = {'localhost', 'localhost.'};

bool _isIpv4MappedLoopback(InternetAddress address) {
  final bytes = address.rawAddress;
  if (bytes.length != 16) return false;
  for (var i = 0; i < 10; i++) {
    if (bytes[i] != 0) return false;
  }
  return bytes[10] == 0xff && bytes[11] == 0xff && bytes[12] == 127;
}

/// Thin HTTP client over the backend's RPC protocol.
///
/// The backend exposes one POST endpoint per RPC class (e.g.
/// `https://api/auth`); each call carries a JSON body containing the
/// requested `method` plus the method's arguments. The auth header is
/// built from a [Credential] (when present) and switches on the
/// credential's `kind` so the on-disk format can grow new credential
/// shapes without breaking pre-existing files.
@experimental
class RestageApi {
  /// Construct an API client.
  ///
  /// [endpoint] is the backend origin (e.g.
  /// `https://api.restage.dev/`); per-call paths append the RPC class
  /// name (`auth`, `paywall`, …). [credential] is optional and only
  /// required for endpoints that read `session.authenticated`.
  RestageApi({
    required Uri endpoint,
    http.Client? httpClient,
    Credential? credential,
  }) : _endpoint = _validatedEndpoint(endpoint),
       _httpClient = httpClient ?? http.Client(),
       _credential = credential;

  static Uri _validatedEndpoint(Uri endpoint) {
    if (!isAcceptableTransport(endpoint)) {
      throw InsecureEndpointException(endpoint);
    }
    return _withTrailingSlash(endpoint);
  }

  /// Ensure [endpoint] ends in a `/` so that resolving a relative RPC path
  /// (`auth`, `paywall`, …) appends to the full base path instead of
  /// replacing its last segment.
  ///
  /// `Uri.resolve` treats the base's final segment as a file to be replaced:
  /// `https://host/api`.resolve(`auth`) yields `https://host/auth`, silently
  /// dropping the `/api` prefix. Normalising the base to `https://host/api/`
  /// makes it resolve to `https://host/api/auth`. An endpoint that already
  /// ends in `/` (or has an empty path) is returned unchanged.
  static Uri _withTrailingSlash(Uri endpoint) {
    final path = endpoint.path;
    if (path.isEmpty || path.endsWith('/')) return endpoint;
    return endpoint.replace(path: '$path/');
  }

  final Uri _endpoint;
  final http.Client _httpClient;
  final Credential? _credential;

  /// Invoke [methodName] on [endpointName].
  ///
  /// Returns the decoded JSON body for 200 responses (a `Map`, `List`,
  /// primitive, or `null`). Throws [RestageApiException] on non-200
  /// responses; throws [StateError] when [_credential] uses a kind the
  /// auth-header builder does not recognise.
  Future<dynamic> call(
    String endpointName,
    String methodName,
    Map<String, dynamic> args,
  ) async {
    final body = jsonEncode(<String, dynamic>{...args, 'method': methodName});
    final headers = <String, String>{
      'content-type': 'application/json; charset=utf-8',
    };
    final credential = _credential;
    if (credential != null) {
      headers['authorization'] = _buildAuthHeader(credential);
    }
    final response = await _httpClient.post(
      _endpoint.resolve(endpointName),
      headers: headers,
      body: body,
    );
    if (response.statusCode != 200) {
      throw RestageApiException(response.statusCode, response.body);
    }
    if (response.body.isEmpty) return null;
    return jsonDecode(response.body);
  }

  /// Release the underlying HTTP client's resources.
  void close() => _httpClient.close();
}

/// Build the `Authorization` header value for [credential].
///
/// Switches on the credential's `kind` so the on-disk format remains
/// forward-compatible — adding a new kind is a single new case here
/// plus a new value in [CredentialKind].
String _buildAuthHeader(Credential credential) {
  switch (credential.kind) {
    case CredentialKind.authKey:
      // The auth-server's session header scheme: `Basic <base64(token)>`
      // where token is the `<keyId>:<key>` pair returned by sign-in.
      //
      // The capital `B` is load-bearing. The current server parses the
      // `Authorization` header by prefix-matching case-sensitively
      // against `Basic ` (RFC 7235 makes the scheme name
      // case-insensitive on the wire, but the parser does not honour
      // that). Lowercase here falls through every matcher and surfaces
      // as a 400 with `Invalid 'authorization' header: Invalid header
      // format`. Do NOT "fix" this back to lowercase until the server
      // gains case-insensitive scheme parsing.
      return 'Basic ${base64Encode(utf8.encode(credential.authToken))}';
    default:
      throw StateError(
        'Unknown credential kind: ${credential.kind}. The credentials '
        'file may have been written by a newer release of the tool.',
      );
  }
}
