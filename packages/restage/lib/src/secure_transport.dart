/// Thrown when a configured network origin would transmit credentials or
/// purchaser data over an insecure (cleartext) connection.
///
/// The SDK sends a public API key, an anonymous purchaser token, receipt /
/// transaction data, and the analytics stream to the configured origin. Those
/// must travel over TLS, so a non-`https` origin is rejected at configuration
/// time rather than silently leaking in cleartext. The single exception is a
/// loopback host (`localhost` / `127.0.0.1` / `::1`), which never leaves the
/// developer's machine and is allowed over `http` for local development.
class InsecureBaseUrlException implements Exception {
  /// Creates the exception for the offending [url] with an explanatory
  /// [message].
  InsecureBaseUrlException(this.url, this.message);

  /// The rejected origin.
  final String url;

  /// A human-readable explanation of why the origin was rejected.
  final String message;

  @override
  String toString() => 'InsecureBaseUrlException($url): $message';
}

/// Asserts that [url] is safe to transmit credentials and purchaser data over.
///
/// Requires an `https` scheme. Allows `http` only when the host is a loopback
/// address (`localhost`, `127.0.0.1`, `::1`) for local development. Any other
/// `http` origin, a missing scheme, or an unparseable URL throws an
/// [InsecureBaseUrlException].
///
/// [label] names the configuration field in the thrown message (e.g.
/// `'baseUrl'` or `'analytics endpoint'`).
void assertSecureUrl(String url, {required String label}) {
  final Uri uri;
  try {
    uri = Uri.parse(url);
  } on FormatException catch (error) {
    throw InsecureBaseUrlException(
      url,
      'the $label could not be parsed as a URL: ${error.message}',
    );
  }

  final scheme = uri.scheme.toLowerCase();
  if (scheme == 'https') return;

  if (scheme == 'http' && _isLoopbackHost(uri.host)) return;

  if (scheme.isEmpty) {
    throw InsecureBaseUrlException(
      url,
      'the $label must be an absolute https URL (no scheme found).',
    );
  }

  throw InsecureBaseUrlException(
    url,
    'the $label must use https (got "$scheme"). Cleartext is allowed only for '
    'loopback hosts during local development.',
  );
}

/// Whether [host] is a loopback address that never leaves the local machine.
bool _isLoopbackHost(String host) {
  // `Uri.host` lower-cases the host and strips the brackets from an IPv6
  // literal, so `http://[::1]:8080` arrives here as `::1`.
  switch (host) {
    case 'localhost':
    case '127.0.0.1':
    case '::1':
      return true;
    default:
      return false;
  }
}
