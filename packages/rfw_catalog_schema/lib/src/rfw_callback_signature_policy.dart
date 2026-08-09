import 'package:rfw_catalog_schema/src/dart_identifier.dart';

/// Parses the RFW-supported `T` from a serialized `ValueChanged<T>`.
///
/// Returns `null` when [source] is not an exact supported public spelling.
/// Scalar payloads use the RFW target's built-in `dart:core` vocabulary.
/// List payloads are non-null lists of the customer scalar vocabulary, with
/// nullable elements allowed.
String? parseRfwCallbackValueType(String source) {
  const prefix = 'ValueChanged<';
  if (!source.startsWith(prefix) || !source.endsWith('>')) return null;
  var payload = source.substring(prefix.length, source.length - 1);
  var isList = false;
  if (payload.startsWith('List<') && payload.endsWith('>')) {
    isList = true;
    payload = payload.substring('List<'.length, payload.length - 1);
  }
  var nullable = false;
  if (payload.endsWith('?')) {
    nullable = true;
    payload = payload.substring(0, payload.length - 1);
  }
  if (!isPublicDartTypeIdentity('dart:core', payload)) return null;
  final supported = isList
      ? _customerScalarPayloads.contains(payload)
      : _builtInScalarPayloads.contains(payload);
  if (!supported) return null;
  final scalar = '$payload${nullable ? '?' : ''}';
  return isList ? 'List<$scalar>' : scalar;
}

const Set<String> _customerScalarPayloads = {
  'bool',
  'int',
  'double',
  'num',
  'String',
};

const Set<String> _builtInScalarPayloads = {
  ..._customerScalarPayloads,
  'DateTime',
  'Duration',
};
