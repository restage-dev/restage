import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:restage_cli/src/api/restage_api.dart';

/// Typed wrapper over the widget catalog RPC endpoint.
///
/// The upload path is intentionally hand-written over [RestageApi] so the
/// command-line tool can stay independent from any generated client package.
@experimental
class CatalogApi {
  /// Build a catalog API client backed by [_api].
  CatalogApi(this._api);

  final RestageApi _api;

  /// Push [catalogJson] for (project, app), returning the stored version.
  ///
  /// [catalogJson] is sent as a plain JSON string. It is not wrapped in the
  /// ByteData `decode(...)` transport used by binary surface payloads.
  Future<int> push({
    required String project,
    required String app,
    required String catalogJson,
    int? organizationId,
  }) async {
    final raw = await _api.call('catalog', 'push', <String, dynamic>{
      'projectSlug': project,
      'appSlug': app,
      'catalogJson': catalogJson,
      'organizationId': ?organizationId,
    });
    return raw as int;
  }
}

/// Typed catalog validation errors returned by the service.
@experimental
@immutable
sealed class CatalogException implements Exception {
  const CatalogException();
}

/// The catalog JSON was malformed or failed schema validation.
@experimental
class CatalogInvalid extends CatalogException {
  /// Construct with the validation [message].
  const CatalogInvalid({required this.message});

  /// Validation message returned by the service.
  final String message;

  @override
  String toString() => 'CatalogInvalid(message: $message)';
}

/// The catalog JSON exceeded the upload byte limit.
@experimental
class CatalogTooLarge extends CatalogException {
  /// Construct with byte-limit details.
  const CatalogTooLarge({required this.maxBytes, required this.actualBytes});

  /// Maximum accepted UTF-8 byte length.
  final int maxBytes;

  /// Actual UTF-8 byte length.
  final int actualBytes;

  @override
  String toString() =>
      'CatalogTooLarge(maxBytes: $maxBytes, actualBytes: $actualBytes)';
}

/// Attempt to decode [body] as one of the typed catalog exceptions.
///
/// Returns null when [body] is not a typed-exception payload. Callers should
/// then fall through to generic [RestageApiException] handling.
@experimental
CatalogException? decodeCatalogTypedException(String body) {
  if (body.isEmpty) return null;
  final dynamic doc;
  try {
    doc = jsonDecode(body);
  } on FormatException {
    return null;
  }
  if (doc is! Map<String, dynamic>) return null;
  final className = doc['className'];
  final data = doc['data'];
  if (className is! String || data is! Map<String, dynamic>) return null;
  switch (className) {
    case 'CatalogInvalidException':
      final message = data['message'];
      if (message is! String) return null;
      return CatalogInvalid(message: message);
    case 'CatalogTooLargeException':
      final maxBytes = data['maxBytes'];
      final actualBytes = data['actualBytes'];
      if (maxBytes is! int || actualBytes is! int) return null;
      return CatalogTooLarge(maxBytes: maxBytes, actualBytes: actualBytes);
    default:
      return null;
  }
}

/// Return a customer-facing message for a typed catalog exception.
@experimental
String renderCatalogException(CatalogException e) => switch (e) {
  CatalogInvalid(:final message) =>
    'The widget catalog could not be uploaded: $message',
  CatalogTooLarge(:final maxBytes, :final actualBytes) =>
    'The widget catalog is too large to upload ($actualBytes bytes; '
        'maximum $maxBytes bytes).',
};
