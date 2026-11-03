import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

@JS('TextEncoder')
extension type _TextEncoder._(JSObject _) implements JSObject {
  external factory _TextEncoder();
  external JSUint8Array encode(JSString text);
}

final _TextEncoder? _encoder =
    globalContext.has('TextEncoder') ? _TextEncoder() : null;

/// [text] as UTF-8, encoded by the host where it has a `TextEncoder`. On Wasm
/// the list stays backed by the host's array: copying it costs more than
/// encoding in Dart.
Uint8List encodeUtf8(String text) {
  final encoder = _encoder;
  return encoder == null ? utf8.encode(text) : encoder.encode(text.toJS).toDart;
}
