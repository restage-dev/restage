import 'document_path_codec.dart';
import 'wire_json.dart';

/// Validates one snapshot target before it reaches either protocol boundary.
///
/// Snapshot paths retain the frozen v1 wire representation: canonical compact
/// document-path JSON. Every authored string segment is also checked against
/// the same normalized credential vocabulary as render data and environment
/// maps.
void validateSnapshotPath(
  String path, {
  required String argumentName,
}) {
  if (path.isEmpty || path.length > 1024) {
    throw ArgumentError.value(
      path,
      argumentName,
      'must be bounded and non-empty',
    );
  }
  for (final segment in DocumentPathCodec.decode(path)) {
    if (segment is String) {
      rejectCredentialFieldName(segment, argumentName: argumentName);
    }
  }
}
