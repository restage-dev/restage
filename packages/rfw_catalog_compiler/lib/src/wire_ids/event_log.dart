import 'dart:convert';
import 'dart:io';

import 'package:rfw_catalog_compiler/src/wire_ids/events.dart';

/// Parses `wire_ids.events.jsonl` contents.
///
/// The reader is intentionally strict: input must be UTF-8-decoded text with
/// LF line endings only, one JSON object per non-empty line, and no blank
/// lines except the implicit final line after a trailing LF.
List<WireIdEvent> parseWireIdEventsJsonl(
  String contents, {
  String sourceDescription = 'wire_ids.events.jsonl',
}) {
  final carriageReturn = contents.indexOf('\r');
  if (carriageReturn != -1) {
    throw WireIdEventException(
      '$sourceDescription must use LF line endings; CR/CRLF is rejected',
      lineNumber: _lineForOffset(contents, carriageReturn),
    );
  }

  final lines = contents.split('\n');
  final events = <WireIdEvent>[];
  for (var index = 0; index < lines.length; index++) {
    final lineNumber = index + 1;
    final line = lines[index];
    if (line.isEmpty) {
      if (index == lines.length - 1) continue;
      throw WireIdEventException(
        '$sourceDescription contains an empty JSONL line',
        lineNumber: lineNumber,
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(line);
    } on FormatException catch (error) {
      throw WireIdEventException(
        '$sourceDescription contains invalid JSON: ${error.message}',
        lineNumber: lineNumber,
      );
    }

    if (decoded is! Map) {
      throw WireIdEventException(
        '$sourceDescription line must be a JSON object',
        lineNumber: lineNumber,
      );
    }
    events.add(
      wireIdEventFromJson(
        _castObjectMap(decoded, lineNumber),
        lineNumber: lineNumber,
      ),
    );
  }
  return events;
}

/// Encodes events as canonical JSONL with LF line endings.
String encodeWireIdEventsJsonl(Iterable<WireIdEvent> events) {
  final buffer = StringBuffer();
  for (final event in events) {
    buffer
      ..write(encodeWireIdEventJson(event))
      ..write('\n');
  }
  return buffer.toString();
}

/// Reads a wire-ID event log from disk using strict UTF-8.
List<WireIdEvent> readWireIdEventLogSync(File file) {
  final contents = _readUtf8(file);
  return parseWireIdEventsJsonl(
    contents,
    sourceDescription: file.path,
  );
}

/// Writes a complete canonical wire-ID event log to disk.
void writeWireIdEventLogSync(
  File file,
  Iterable<WireIdEvent> events,
) {
  file.writeAsBytesSync(
    utf8.encode(encodeWireIdEventsJsonl(events)),
    flush: true,
  );
}

/// Appends canonical event lines to an existing log.
///
/// Existing contents are validated first so appends do not normalize a corrupt
/// source-of-truth file silently.
void appendWireIdEventsSync(
  File file,
  Iterable<WireIdEvent> events,
) {
  String? contents;
  try {
    contents = _readUtf8(file);
  } on PathNotFoundException {
    contents = null;
  }
  if (contents != null) {
    parseWireIdEventsJsonl(contents, sourceDescription: file.path);
    if (contents.isNotEmpty && !contents.endsWith('\n')) {
      throw WireIdEventException(
        '${file.path} must end with LF before appending',
      );
    }
  }
  file.writeAsBytesSync(
    utf8.encode(encodeWireIdEventsJsonl(events)),
    mode: FileMode.append,
    flush: true,
  );
}

String _readUtf8(File file) {
  try {
    return utf8.decode(file.readAsBytesSync(), allowMalformed: false);
  } on FormatException catch (error) {
    throw WireIdEventException(
      '${file.path} is not valid UTF-8: ${error.message}',
    );
  }
}

Map<String, Object?> _castObjectMap(
  Map<Object?, Object?> json,
  int lineNumber,
) {
  final result = <String, Object?>{};
  for (final entry in json.entries) {
    final key = entry.key;
    if (key is! String) {
      throw WireIdEventException(
        'JSON object keys must be strings',
        lineNumber: lineNumber,
      );
    }
    result[key] = entry.value;
  }
  return result;
}

int _lineForOffset(String source, int offset) {
  var line = 1;
  for (var i = 0; i < offset; i++) {
    if (source.codeUnitAt(i) == 0x0A) line++;
  }
  return line;
}
