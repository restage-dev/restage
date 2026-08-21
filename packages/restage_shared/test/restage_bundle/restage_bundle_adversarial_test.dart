// Adversarial and property-style coverage for the deterministic Restage
// bundle codec: the single ZIP-compatible seam used for build output, CLI
// publication reads, and SDK bundle consumption.
//
// The decoder is a narrow, byte-exact parser for one canonical container
// profile, not a general-purpose ZIP reader, so most attacks below are
// exercised by taking one valid encoder output and mutating specific fields
// or bytes in place (a "byte-edited fixture") rather than by committing
// binary test data.
import 'dart:convert';
import 'dart:typed_data';

import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Low-level ZIP field helpers.
//
// These constants and offsets describe the public ZIP file format (not an
// implementation secret) and mirror the fixed layout the codec itself emits:
// a 30-byte local file header, a 46-byte central directory record, and a
// 22-byte end-of-central-directory record, each followed by a variable-length
// file name and, for local headers, the entry content.
// ---------------------------------------------------------------------------

const int _centralHeaderSignature = 0x02014B50;
const int _eocdSignature = 0x06054B50;

int _u16(Uint8List bytes, int offset) =>
    bytes[offset] | (bytes[offset + 1] << 8);

int _u32(Uint8List bytes, int offset) =>
    bytes[offset] |
    (bytes[offset + 1] << 8) |
    (bytes[offset + 2] << 16) |
    (bytes[offset + 3] << 24);

void _setU16(Uint8List bytes, int offset, int value) {
  bytes[offset] = value & 0xFF;
  bytes[offset + 1] = (value >> 8) & 0xFF;
}

void _setU32(Uint8List bytes, int offset, int value) {
  bytes[offset] = value & 0xFF;
  bytes[offset + 1] = (value >> 8) & 0xFF;
  bytes[offset + 2] = (value >> 16) & 0xFF;
  bytes[offset + 3] = (value >> 24) & 0xFF;
}

int _crc32(List<int> bytes) {
  var value = 0xFFFFFFFF;
  for (final byte in bytes) {
    value ^= byte;
    for (var bit = 0; bit < 8; bit += 1) {
      value = (value & 1) == 0 ? value >>> 1 : (value >>> 1) ^ 0xEDB88320;
    }
  }
  return (value ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

int _eocdOffset(Uint8List bytes) {
  // The codec never emits an archive comment, so the EOCD record is always
  // the final 22 bytes.
  final offset = bytes.length - 22;
  expect(
    _u32(bytes, offset),
    _eocdSignature,
    reason: 'fixture must start from a valid bundle',
  );
  return offset;
}

class _CentralRecord {
  _CentralRecord(this.offset, this.nameLength);

  final int offset;
  final int nameLength;

  int get length => 46 + nameLength;
  int get nameOffset => offset + 46;
  int get localHeaderOffsetField => offset + 42;
}

List<_CentralRecord> _centralRecords(Uint8List bytes) {
  final eocd = _eocdOffset(bytes);
  final centralLength = _u32(bytes, eocd + 12);
  final centralOffset = _u32(bytes, eocd + 16);
  final records = <_CentralRecord>[];
  var cursor = centralOffset;
  final end = centralOffset + centralLength;
  while (cursor < end) {
    expect(_u32(bytes, cursor), _centralHeaderSignature);
    final nameLength = _u16(bytes, cursor + 28);
    records.add(_CentralRecord(cursor, nameLength));
    cursor += 46 + nameLength;
  }
  return records;
}

/// Overwrites the name bytes of central-directory record [index] in place.
/// [replacement] must be exactly as long as the existing name, so no other
/// offset in the archive needs to move.
void _renameCentralEntry(Uint8List bytes, int index, List<int> replacement) {
  final record = _centralRecords(bytes)[index];
  expect(replacement.length, record.nameLength);
  bytes.setRange(
    record.nameOffset,
    record.nameOffset + record.nameLength,
    replacement,
  );
}

/// Overwrites the name bytes of both the central record and its matching
/// local header. Needed only when the mutated central name is itself still
/// well-formed (so the decoder's central-directory pass doesn't reject it
/// before ever comparing against the local header).
void _renameEntryEverywhere(Uint8List bytes, int index, List<int> replacement) {
  final record = _centralRecords(bytes)[index];
  expect(replacement.length, record.nameLength);
  bytes.setRange(
    record.nameOffset,
    record.nameOffset + record.nameLength,
    replacement,
  );
  final localOffset = _u32(bytes, record.localHeaderOffsetField);
  final localNameStart = localOffset + 30;
  bytes.setRange(
      localNameStart, localNameStart + record.nameLength, replacement);
}

Uint8List _validBundleBytes({
  String packageName = 'example_package',
  String authoredLibraryPath = 'lib/features/welcome.dart',
  List<RestageBundleEntry> entries = const <RestageBundleEntry>[],
}) {
  final bundle = RestageBundle(
    packageName: packageName,
    authoredLibraryPath: authoredLibraryPath,
    entries: entries,
  );
  return RestageBundleCodec.encode(bundle);
}

RestageBundleEntry _entry(String path, List<int> bytes) => RestageBundleEntry(
      logicalPath: path,
      role: RestageBundleEntryRole.screenBlob,
      bytes: bytes,
    );

Matcher get _rejected => throwsA(isA<FormatException>());

/// Applies [mutate] to the decoded canonical JSON text of the metadata entry
/// and patches its CRC-32 so the change isn't masked by an earlier integrity
/// check. Requires the mutation to preserve the JSON's byte length — every
/// test fixture below only ever swaps characters for same-width ones, so no
/// other offset in the archive ever needs to move. Assumes the metadata
/// entry is the first (and, in single-payload fixtures, only) archive entry,
/// which holds for every fixture here because `META-INF/...` sorts before
/// every lowercase payload path used in this file.
Uint8List _withMutatedMetadataJson(
  Uint8List bundleBytes,
  String Function(String canonicalJson) mutate,
) {
  final bytes = Uint8List.fromList(bundleBytes);
  final nameLength = _u16(bytes, 26);
  final contentLength = _u32(bytes, 22);
  final contentStart = 30 + nameLength;
  final originalJson =
      utf8.decode(bytes.sublist(contentStart, contentStart + contentLength));
  final mutatedJson = mutate(originalJson);
  final mutatedBytes = utf8.encode(mutatedJson);
  expect(
    mutatedBytes.length,
    contentLength,
    reason: 'this fixture helper only supports same-length JSON mutations',
  );
  bytes.setRange(contentStart, contentStart + contentLength, mutatedBytes);
  final newCrc = _crc32(mutatedBytes);
  _setU32(bytes, 14, newCrc); // local header CRC-32
  final centralOffset = _u32(bytes, _eocdOffset(bytes) + 16);
  _setU32(bytes, centralOffset + 16, newCrc); // central record CRC-32
  return bytes;
}

String _flipHexChar(String hex) {
  final last = hex[hex.length - 1];
  final flipped = last == '0' ? '1' : '0';
  return hex.substring(0, hex.length - 1) + flipped;
}

/// A syntactically valid `sha256:<64 lowercase hex>` placeholder for
/// fixtures that need a well-formed hash but never verify it against real
/// content.
final String _placeholderSha256 = 'sha256:${'0' * 64}';

void main() {
  group('RestageBundleCodec decode — path traversal and canonical paths', () {
    test('rejects a leading-slash (absolute) path', () {
      final bytes = _validBundleBytes(
        entries: <RestageBundleEntry>[
          _entry('assets/aa/x.rfw', <int>[1, 2, 3])
        ],
      );
      _renameCentralEntry(bytes, 1, utf8.encode('/ssets/aa/x.rfw'));
      expect(() => RestageBundleCodec.decode(bytes), _rejected);
    });

    test('rejects a ".." path segment', () {
      final bytes = _validBundleBytes(
        entries: <RestageBundleEntry>[
          _entry('assets/aa/x.rfw', <int>[1, 2, 3])
        ],
      );
      _renameCentralEntry(bytes, 1, utf8.encode('assets/../x.rfw'));
      expect(() => RestageBundleCodec.decode(bytes), _rejected);
    });

    test('rejects a "." path segment', () {
      final bytes = _validBundleBytes(
        entries: <RestageBundleEntry>[
          _entry('assets/a/x.rfw', <int>[1, 2, 3])
        ],
      );
      _renameCentralEntry(bytes, 1, utf8.encode('assets/./x.rfw'));
      expect(() => RestageBundleCodec.decode(bytes), _rejected);
    });

    test('rejects an empty path segment', () {
      final bytes = _validBundleBytes(
        entries: <RestageBundleEntry>[
          _entry('assets/aa/x.rfw', <int>[1, 2, 3])
        ],
      );
      _renameCentralEntry(bytes, 1, utf8.encode('assets//x/x.rfw'));
      expect(() => RestageBundleCodec.decode(bytes), _rejected);
    });

    test('rejects a backslash in the path', () {
      final bytes = _validBundleBytes(
        entries: <RestageBundleEntry>[
          _entry('assets/aa/x.rfw', <int>[1, 2, 3])
        ],
      );
      _renameCentralEntry(bytes, 1, utf8.encode(r'assets\aa/x.rfw'));
      expect(() => RestageBundleCodec.decode(bytes), _rejected);
    });

    test('rejects a NUL byte in the path', () {
      final bytes = _validBundleBytes(
        entries: <RestageBundleEntry>[
          _entry('assets/aa/x.rfw', <int>[1, 2, 3])
        ],
      );
      _renameCentralEntry(bytes, 1,
          <int>[...utf8.encode('assets/a'), 0, ...utf8.encode('/x.rfw')]);
      expect(() => RestageBundleCodec.decode(bytes), _rejected);
    });

    test('rejects non-UTF-8 path bytes', () {
      final bytes = _validBundleBytes(
        entries: <RestageBundleEntry>[
          _entry('assets/aa/x.rfw', <int>[1, 2, 3])
        ],
      );
      final name = utf8.encode('assets/aa/x.rfw');
      final corrupted = List<int>.of(name)..[7] = 0xFF;
      _renameCentralEntry(bytes, 1, corrupted);
      expect(() => RestageBundleCodec.decode(bytes), _rejected);
    });

    test('rejects duplicate entry paths', () {
      final bytes = _validBundleBytes(
        entries: <RestageBundleEntry>[
          _entry('assets/aaa.rfw', <int>[1]),
          _entry('assets/bbb.rfw', <int>[2]),
        ],
      );
      // Both payload paths are the same byte length by construction; make
      // the second entry's (index 2) central name collide with the
      // first's (index 1; index 0 is always the metadata entry).
      _renameCentralEntry(bytes, 2, utf8.encode('assets/aaa.rfw'));
      expect(() => RestageBundleCodec.decode(bytes), _rejected);
    });

    test('rejects a payload entry duplicating the reserved metadata path', () {
      final metadataPathLength = utf8.encode(kRestageBundleMetadataPath).length;
      final payloadPath =
          'assets/${'a' * (metadataPathLength - 'assets/'.length)}';
      expect(utf8.encode(payloadPath).length, metadataPathLength);
      final bytes = _validBundleBytes(
        entries: <RestageBundleEntry>[
          _entry(payloadPath, <int>[1, 2, 3])
        ],
      );
      _renameCentralEntry(bytes, 1, utf8.encode(kRestageBundleMetadataPath));
      expect(() => RestageBundleCodec.decode(bytes), _rejected);
    });
  });

  group('RestageBundleCodec decode — ordering', () {
    test('rejects entries not in ascending UTF-8 path-byte order', () {
      final bytes = _validBundleBytes(
        entries: <RestageBundleEntry>[
          _entry('assets/aaa.rfw', <int>[1]),
          _entry('assets/bbb.rfw', <int>[2]),
        ],
      );
      final aName = utf8.encode('assets/aaa.rfw');
      final bName = utf8.encode('assets/bbb.rfw');
      // Swap the two payload entries' central-directory names so record[1]
      // (originally "aaa", ascending after "bbb") now reads "aaa" again but
      // ahead of a smaller path, i.e. records read [meta, bbb, aaa].
      _renameCentralEntry(bytes, 1, bName);
      _renameCentralEntry(bytes, 2, aName);
      expect(() => RestageBundleCodec.decode(bytes), _rejected);
    });
  });

  group('RestageBundleCodec decode — compression', () {
    test('rejects a central directory entry not in store mode', () {
      final bytes = _validBundleBytes(
        entries: <RestageBundleEntry>[
          _entry('assets/aaa.rfw', <int>[1, 2, 3])
        ],
      );
      final record = _centralRecords(bytes)[1];
      _setU16(bytes, record.offset + 10, 8); // deflate
      expect(() => RestageBundleCodec.decode(bytes), _rejected);
    });

    test('rejects a local header entry not in store mode', () {
      final bytes = _validBundleBytes(
        entries: <RestageBundleEntry>[
          _entry('assets/aaa.rfw', <int>[1, 2, 3])
        ],
      );
      final record = _centralRecords(bytes)[1];
      final localOffset = _u32(bytes, record.localHeaderOffsetField);
      _setU16(bytes, localOffset + 8, 8); // deflate
      expect(() => RestageBundleCodec.decode(bytes), _rejected);
    });

    test('rejects a central entry with mismatched compressed/uncompressed size',
        () {
      final bytes = _validBundleBytes(
        entries: <RestageBundleEntry>[
          _entry('assets/aaa.rfw', <int>[1, 2, 3])
        ],
      );
      final record = _centralRecords(bytes)[1];
      _setU32(bytes, record.offset + 20, 1); // compressed size != uncompressed
      expect(() => RestageBundleCodec.decode(bytes), _rejected);
    });
  });

  group('RestageBundleCodec — ZIP64', () {
    test('rejects sentinel (0xFFFFFFFF) sizes used to signal ZIP64', () {
      final bytes = _validBundleBytes(
        entries: <RestageBundleEntry>[
          _entry('assets/aaa.rfw', <int>[1, 2, 3])
        ],
      );
      final record = _centralRecords(bytes)[1];
      final localOffset = _u32(bytes, record.localHeaderOffsetField);
      const sentinel = 0xFFFFFFFF;
      _setU32(bytes, record.offset + 20, sentinel);
      _setU32(bytes, record.offset + 24, sentinel);
      _setU32(bytes, localOffset + 18, sentinel);
      _setU32(bytes, localOffset + 22, sentinel);
      expect(() => RestageBundleCodec.decode(bytes), _rejected);
    });

    test(
        'rejects a nonzero extra-field length (where a ZIP64 extra record would live)',
        () {
      final bytes = _validBundleBytes(
        entries: <RestageBundleEntry>[
          _entry('assets/aaa.rfw', <int>[1, 2, 3])
        ],
      );
      final record = _centralRecords(bytes)[1];
      _setU16(bytes, record.offset + 30, 4);
      expect(() => RestageBundleCodec.decode(bytes), _rejected);
    });

    test(
        'rejects bytes inserted before the end-of-central-directory record '
        '(where a ZIP64 EOCD locator would live)', () {
      final bytes = _validBundleBytes(
        entries: <RestageBundleEntry>[
          _entry('assets/aaa.rfw', <int>[1, 2, 3])
        ],
      );
      final splitPoint = bytes.length - 22;
      final spliced = Uint8List.fromList(<int>[
        ...bytes.sublist(0, splitPoint),
        ...List<int>.filled(20, 0xAB), // a bogus ZIP64 locator/record-sized gap
        ...bytes.sublist(splitPoint),
      ]);
      expect(() => RestageBundleCodec.decode(spliced), _rejected);
    });

    test(
        'encoder fails loudly rather than emitting ZIP64 for an oversized entry count',
        () {
      final tooMany = List<RestageBundleEntry>.generate(
        kRestageBundleMaxPayloadEntries + 1,
        (index) => _entry(
          'assets/${index.toString().padLeft(6, '0')}.rfw',
          const <int>[],
        ),
      );
      expect(
        () => RestageBundle(
          packageName: 'example_package',
          authoredLibraryPath: 'lib/features/welcome.dart',
          entries: tooMany,
        ),
        _rejected,
      );
    });
  });

  group('RestageBundleCodec decode — integrity', () {
    test('rejects a wrong CRC-32 (consistent between central and local)', () {
      final bytes = _validBundleBytes(
        entries: <RestageBundleEntry>[
          _entry('assets/aaa.rfw', <int>[1, 2, 3, 4, 5])
        ],
      );
      final record = _centralRecords(bytes)[1];
      final localOffset = _u32(bytes, record.localHeaderOffsetField);
      final actualCrc = _u32(bytes, record.offset + 16);
      final wrongCrc = actualCrc ^ 0xFFFFFFFF;
      _setU32(bytes, record.offset + 16, wrongCrc);
      _setU32(bytes, localOffset + 14, wrongCrc);
      expect(() => RestageBundleCodec.decode(bytes), _rejected);
    });

    test('rejects a wrong declared size (consistent between central and local)',
        () {
      final bytes = _validBundleBytes(
        entries: <RestageBundleEntry>[
          _entry('assets/aaa.rfw', <int>[1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
        ],
      );
      final record = _centralRecords(bytes)[1];
      final localOffset = _u32(bytes, record.localHeaderOffsetField);
      const wrongSize = 9;
      _setU32(bytes, record.offset + 20, wrongSize);
      _setU32(bytes, record.offset + 24, wrongSize);
      _setU32(bytes, localOffset + 18, wrongSize);
      _setU32(bytes, localOffset + 22, wrongSize);
      expect(() => RestageBundleCodec.decode(bytes), _rejected);
    });

    test('rejects a local-header CRC that disagrees with the central directory',
        () {
      final bytes = _validBundleBytes(
        entries: <RestageBundleEntry>[
          _entry('assets/aaa.rfw', <int>[1, 2, 3])
        ],
      );
      final record = _centralRecords(bytes)[1];
      final actualCrc = _u32(bytes, record.offset + 16);
      _setU32(
          bytes, record.offset + 16, actualCrc ^ 0xFFFFFFFF); // central only
      expect(() => RestageBundleCodec.decode(bytes), _rejected);
    });

    test(
        'rejects a local-header size that disagrees with the central directory',
        () {
      final bytes = _validBundleBytes(
        entries: <RestageBundleEntry>[
          _entry('assets/aaa.rfw', <int>[1, 2, 3])
        ],
      );
      final record = _centralRecords(bytes)[1];
      _setU32(bytes, record.offset + 20, 2); // central only
      _setU32(bytes, record.offset + 24, 2);
      expect(() => RestageBundleCodec.decode(bytes), _rejected);
    });

    test('rejects a truncated archive (footer cut off)', () {
      final bytes = _validBundleBytes(
        entries: <RestageBundleEntry>[
          _entry('assets/aaa.rfw', <int>[1, 2, 3])
        ],
      );
      expect(
        () => RestageBundleCodec.decode(bytes.sublist(0, bytes.length - 1)),
        _rejected,
      );
    });

    test('rejects a truncated archive (well short of any valid footer)', () {
      final bytes = _validBundleBytes(
        entries: <RestageBundleEntry>[
          _entry('assets/aaa.rfw', <int>[1, 2, 3])
        ],
      );
      expect(() => RestageBundleCodec.decode(bytes.sublist(0, 10)), _rejected);
    });

    test('rejects a truncated archive (central directory cut short)', () {
      final bytes = _validBundleBytes(
        entries: <RestageBundleEntry>[
          _entry('assets/aaa.rfw', <int>[1, 2, 3])
        ],
      );
      final eocd = _eocdOffset(bytes);
      expect(() => RestageBundleCodec.decode(bytes.sublist(0, eocd - 5)),
          _rejected);
    });

    test('rejects trailing garbage after the end-of-central-directory record',
        () {
      final bytes = _validBundleBytes(
        entries: <RestageBundleEntry>[
          _entry('assets/aaa.rfw', <int>[1, 2, 3])
        ],
      );
      final withGarbage = Uint8List.fromList(<int>[...bytes, 1, 2, 3, 4]);
      expect(() => RestageBundleCodec.decode(withGarbage), _rejected);
    });

    test(
        'rejects overlapping entries (a local-header offset that reuses '
        "another entry's region)", () {
      final bytes = _validBundleBytes(
        entries: <RestageBundleEntry>[
          _entry('assets/aaa.rfw', <int>[1, 2, 3]),
          _entry('assets/bbb.rfw', <int>[4, 5, 6, 7]),
        ],
      );
      final records = _centralRecords(bytes);
      final aLocalOffset = _u32(bytes, records[1].localHeaderOffsetField);
      // Point the second payload entry's local header back at the first
      // entry's region instead of its own, contiguous, offset.
      _setU32(bytes, records[2].localHeaderOffsetField, aLocalOffset);
      expect(() => RestageBundleCodec.decode(bytes), _rejected);
    });

    test(
        'rejects a payload entry physically present but absent from the '
        'central directory', () {
      final bytes = _validBundleBytes(
        entries: <RestageBundleEntry>[
          _entry('assets/aaa.rfw', <int>[1, 2, 3]),
          _entry('assets/bbb.rfw', <int>[4, 5, 6, 7]),
        ],
      );
      final records = _centralRecords(bytes);
      final lastRecord = records.last; // "assets/bbb.rfw" sorts last
      final eocd = _eocdOffset(bytes);
      final centralLength = _u32(bytes, eocd + 12);
      final newCentralLength = centralLength - lastRecord.length;
      final trimmed = Uint8List.fromList(<int>[
        ...bytes.sublist(0, lastRecord.offset),
        ...bytes.sublist(eocd),
      ]);
      final newEocd = trimmed.length - 22;
      _setU16(trimmed, newEocd + 8, records.length - 1);
      _setU16(trimmed, newEocd + 10, records.length - 1);
      _setU32(trimmed, newEocd + 12, newCentralLength);
      expect(() => RestageBundleCodec.decode(trimmed), _rejected);
    });
  });

  group('RestageBundleCodec decode — metadata', () {
    test('rejects a bundle whose sole entry is not the reserved metadata path',
        () {
      final bytes = _validBundleBytes();
      final metadataPathLength = utf8.encode(kRestageBundleMetadataPath).length;
      _renameEntryEverywhere(
          bytes, 0, List<int>.filled(metadataPathLength, 0x7A)); // 'z'
      expect(() => RestageBundleCodec.decode(bytes), _rejected);
    });

    test('rejects metadata whose declared path disagrees with the actual entry',
        () {
      final bytes = _validBundleBytes(
        entries: <RestageBundleEntry>[
          _entry('assets/welcome.rfw', <int>[1, 2, 3])
        ],
      );
      final mutated = _withMutatedMetadataJson(
        bytes,
        (json) =>
            json.replaceFirst('"assets/welcome.rfw"', '"assets/we1come.rfw"'),
      );
      expect(() => RestageBundleCodec.decode(mutated), _rejected);
    });

    test(
        'rejects metadata whose declared byte length disagrees with the actual entry',
        () {
      final bytes = _validBundleBytes(
        entries: <RestageBundleEntry>[
          _entry('assets/welcome.rfw', <int>[1, 2, 3, 4])
        ],
      );
      final mutated = _withMutatedMetadataJson(
        bytes,
        (json) => json.replaceFirst('"byteLength":4', '"byteLength":5'),
      );
      expect(() => RestageBundleCodec.decode(mutated), _rejected);
    });

    test(
        'rejects metadata whose declared SHA-256 disagrees with the actual entry',
        () {
      final bytes = _validBundleBytes(
        entries: <RestageBundleEntry>[
          _entry('assets/welcome.rfw', <int>[1, 2, 3])
        ],
      );
      final entryHash = RestageBundle(
        packageName: 'example_package',
        authoredLibraryPath: 'lib/features/welcome.dart',
        entries: <RestageBundleEntry>[
          _entry('assets/welcome.rfw', <int>[1, 2, 3])
        ],
      ).entries.single.sha256;
      final flipped = _flipHexChar(entryHash);
      final mutated = _withMutatedMetadataJson(
        bytes,
        (json) => json.replaceFirst('"$entryHash"', '"$flipped"'),
      );
      expect(() => RestageBundleCodec.decode(mutated), _rejected);
    });
  });

  group('RestageBundleMetadataCodec.decodeCanonicalJson — malformed metadata',
      () {
    String validJson() => RestageBundleMetadataCodec.encodeCanonicalJson(
          RestageBundleMetadata(
            packageName: 'example_package',
            authoredLibraryPath: 'lib/features/welcome.dart',
            entries: <RestageBundleMetadataEntry>[
              RestageBundleMetadataEntry(
                logicalPath: 'assets/welcome.rfw',
                role: RestageBundleEntryRole.screenBlob,
                byteLength: 3,
                sha256: _placeholderSha256,
              ),
            ],
          ),
        );

    test('rejects a missing required key', () {
      final json = validJson();
      final decoded = jsonDecode(json) as Map<String, Object?>;
      decoded.remove('authoredLibrary');
      expect(
        () =>
            RestageBundleMetadataCodec.decodeCanonicalJson(jsonEncode(decoded)),
        _rejected,
      );
    });

    test('rejects an unknown extra key', () {
      final json = validJson();
      final decoded = jsonDecode(json) as Map<String, Object?>;
      decoded['unexpected'] = true;
      expect(
        () =>
            RestageBundleMetadataCodec.decodeCanonicalJson(jsonEncode(decoded)),
        _rejected,
      );
    });

    test('rejects an unsupported schema version', () {
      final json = validJson();
      final decoded = jsonDecode(json) as Map<String, Object?>;
      decoded['schemaVersion'] = kRestageBundleSchemaVersion + 1;
      expect(
        () =>
            RestageBundleMetadataCodec.decodeCanonicalJson(jsonEncode(decoded)),
        _rejected,
      );
    });

    test('rejects non-canonical JSON (extra whitespace)', () {
      final json = validJson();
      expect(
        () => RestageBundleMetadataCodec.decodeCanonicalJson(' $json'),
        _rejected,
      );
    });

    test('rejects metadata entries out of sorted order', () {
      final unsorted = jsonEncode(<String, Object?>{
        'schemaVersion': kRestageBundleSchemaVersion,
        'package': 'example_package',
        'authoredLibrary': 'lib/features/welcome.dart',
        'entries': <Object?>[
          <String, Object?>{
            'path': 'assets/b.rfw',
            'role': 'screenBlob',
            'byteLength': 1,
            'sha256': _placeholderSha256,
          },
          <String, Object?>{
            'path': 'assets/a.rfw',
            'role': 'screenBlob',
            'byteLength': 1,
            'sha256': _placeholderSha256,
          },
        ],
      });
      expect(
        () => RestageBundleMetadataCodec.decodeCanonicalJson(unsorted),
        _rejected,
      );
    });

    test('rejects a metadata entry describing itself', () {
      final selfDescribing = jsonEncode(<String, Object?>{
        'schemaVersion': kRestageBundleSchemaVersion,
        'package': 'example_package',
        'authoredLibrary': 'lib/features/welcome.dart',
        'entries': <Object?>[
          <String, Object?>{
            'path': kRestageBundleMetadataPath,
            'role': 'screenBlob',
            'byteLength': 1,
            'sha256': _placeholderSha256,
          },
        ],
      });
      expect(
        () => RestageBundleMetadataCodec.decodeCanonicalJson(selfDescribing),
        _rejected,
      );
    });

    test('rejects duplicate metadata entry paths', () {
      final entry = <String, Object?>{
        'path': 'assets/a.rfw',
        'role': 'screenBlob',
        'byteLength': 1,
        'sha256': _placeholderSha256,
      };
      final duplicated = jsonEncode(<String, Object?>{
        'schemaVersion': kRestageBundleSchemaVersion,
        'package': 'example_package',
        'authoredLibrary': 'lib/features/welcome.dart',
        'entries': <Object?>[entry, entry],
      });
      expect(
        () => RestageBundleMetadataCodec.decodeCanonicalJson(duplicated),
        _rejected,
      );
    });
  });

  group('RestageBundleCodec — determinism', () {
    List<RestageBundleEntry> entries() => <RestageBundleEntry>[
          _entry('assets/a.rfw', utf8.encode('alpha')),
          _entry('assets/b.rfw', utf8.encode('beta')),
          _entry('assets/c.capability.json', utf8.encode('{"k":"v"}')),
        ];

    test('encoding twice yields byte-identical output', () {
      final bundle = RestageBundle(
        packageName: 'example_package',
        authoredLibraryPath: 'lib/features/welcome.dart',
        entries: entries(),
      );
      final first = RestageBundleCodec.encode(bundle);
      final second = RestageBundleCodec.encode(bundle);
      expect(first, orderedEquals(second));
    });

    test('encoding in shuffled insertion order yields byte-identical output',
        () {
      final baseline = RestageBundleCodec.encode(
        RestageBundle(
          packageName: 'example_package',
          authoredLibraryPath: 'lib/features/welcome.dart',
          entries: entries(),
        ),
      );
      final permutations = <List<RestageBundleEntry>>[
        entries().reversed.toList(),
        <RestageBundleEntry>[entries()[1], entries()[2], entries()[0]],
        <RestageBundleEntry>[entries()[2], entries()[0], entries()[1]],
      ];
      for (final permutation in permutations) {
        final shuffled = RestageBundleCodec.encode(
          RestageBundle(
            packageName: 'example_package',
            authoredLibraryPath: 'lib/features/welcome.dart',
            entries: permutation,
          ),
        );
        expect(shuffled, orderedEquals(baseline));
      }
    });

    test('fixes timestamps to the ZIP minimum on raw bytes', () {
      final bytes = _validBundleBytes(
        entries: <RestageBundleEntry>[
          _entry('assets/a.rfw', <int>[1])
        ],
      );
      final record = _centralRecords(bytes)[1];
      final localOffset = _u32(bytes, record.localHeaderOffsetField);
      // Local header: mod time at +10, mod date at +12.
      expect(_u16(bytes, localOffset + 10), 0);
      expect(_u16(bytes, localOffset + 12), 0x0021);
      // Central record: mod time at +12, mod date at +14.
      expect(_u16(bytes, record.offset + 12), 0);
      expect(_u16(bytes, record.offset + 14), 0x0021);
    });

    test('fixes platform metadata to a portable value on raw bytes', () {
      final bytes = _validBundleBytes(
        entries: <RestageBundleEntry>[
          _entry('assets/a.rfw', <int>[1])
        ],
      );
      final record = _centralRecords(bytes)[1];
      expect(_u16(bytes, record.offset + 4), 0x0314); // version made by
      expect(_u32(bytes, record.offset + 38),
          0x81A40000); // unix 0644 regular file
    });
  });

  group('RestageBundleCodec — round-trip', () {
    test('round-trips a text payload', () {
      final bundle = RestageBundle(
        packageName: 'example_package',
        authoredLibraryPath: 'lib/features/welcome.dart',
        entries: <RestageBundleEntry>[
          _entry('assets/welcome.rfwtxt', utf8.encode('widget Welcome;')),
        ],
      );
      final decoded =
          RestageBundleCodec.decode(RestageBundleCodec.encode(bundle));
      expect(
        utf8.decode(decoded.entries.single.bytes),
        'widget Welcome;',
      );
    });

    test('round-trips an arbitrary binary payload', () {
      final binary = List<int>.generate(256, (index) => index);
      final bundle = RestageBundle(
        packageName: 'example_package',
        authoredLibraryPath: 'lib/features/welcome.dart',
        entries: <RestageBundleEntry>[_entry('assets/welcome.rfw', binary)],
      );
      final decoded =
          RestageBundleCodec.decode(RestageBundleCodec.encode(bundle));
      expect(decoded.entries.single.bytes, orderedEquals(binary));
    });

    test('round-trips an empty-payload entry', () {
      final bundle = RestageBundle(
        packageName: 'example_package',
        authoredLibraryPath: 'lib/features/welcome.dart',
        entries: <RestageBundleEntry>[
          _entry('assets/empty.rfw', const <int>[])
        ],
      );
      final decoded =
          RestageBundleCodec.decode(RestageBundleCodec.encode(bundle));
      expect(decoded.entries.single.byteLength, 0);
      expect(decoded.entries.single.bytes, isEmpty);
    });

    test('round-trips a metadata-only bundle with zero payload entries', () {
      // The generated-output spec's stance is that a library with no
      // artifacts emits no bundle at all; that's a decision made upstream of
      // this codec. The codec itself takes no position against an empty
      // payload list, so this documents (rather than asserts a specific
      // policy for) that permissive stance: encode/decode is total for zero
      // entries.
      final bundle = RestageBundle(
        packageName: 'example_package',
        authoredLibraryPath: 'lib/features/welcome.dart',
        entries: const <RestageBundleEntry>[],
      );
      final decoded =
          RestageBundleCodec.decode(RestageBundleCodec.encode(bundle));
      expect(decoded.entries, isEmpty);
      expect(decoded.metadata.entries, isEmpty);
    });
  });
}
