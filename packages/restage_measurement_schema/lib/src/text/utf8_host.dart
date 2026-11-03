import 'dart:convert';
import 'dart:typed_data';

/// [text] as UTF-8.
Uint8List encodeUtf8(String text) => utf8.encode(text);
