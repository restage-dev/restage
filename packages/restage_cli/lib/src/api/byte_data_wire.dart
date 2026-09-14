import 'dart:convert';
import 'dart:typed_data';

// The service renders and accepts byte columns as `decode('<base64>', 'base64')`.
const _prefix = "decode('";
const _suffix = "', 'base64')";

/// Renders [bytes] in the wire form the service reads.
String encodeByteDataWire(List<int> bytes) =>
    '$_prefix${base64Encode(bytes)}$_suffix';

/// Reads the wire form back, accepting only canonical base64 that decodes to
/// at least one byte, and to at most [maximumBytes] where the caller sets a
/// bound. [malformed] builds the exception the caller reports, and receives a
/// phrase naming what was wrong.
Uint8List decodeByteDataWire(
  Object? raw, {
  required Exception Function(String detail) malformed,
  int? maximumBytes,
}) {
  if (raw is! String || !raw.startsWith(_prefix) || !raw.endsWith(_suffix)) {
    throw malformed('is not in the wire form');
  }
  final encoded = raw.substring(_prefix.length, raw.length - _suffix.length);
  if (encoded.isEmpty ||
      (maximumBytes != null &&
          encoded.length > ((maximumBytes + 2) ~/ 3) * 4)) {
    throw malformed('is outside its bounded shape');
  }
  final Uint8List bytes;
  try {
    bytes = Uint8List.fromList(base64Decode(encoded));
  } on FormatException {
    throw malformed('is not valid base64');
  }
  if (bytes.isEmpty || (maximumBytes != null && bytes.length > maximumBytes)) {
    throw malformed('is outside its bounded shape');
  }
  if (base64Encode(bytes) != encoded) {
    throw malformed('is not canonical');
  }
  return bytes;
}
