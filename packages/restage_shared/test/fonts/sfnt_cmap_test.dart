import 'dart:io';
import 'dart:typed_data';

import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

void main() {
  group('a real subset icon font', () {
    test('covers exactly the code points it was subset to', () {
      final bytes = _fixture('material_icons_subset.otf');
      expect(readSfntCoveredCodePoints(bytes), {0xe87d, 0xe5cc, 0xf63a});
    });

    test('is refused once truncated', () {
      final bytes = _fixture('material_icons_subset.otf');
      expect(
        () => readSfntCoveredCodePoints(bytes.sublist(0, 200)),
        throwsFormatException,
      );
    });
  });

  group('cmap format 4', () {
    test('reads delta-mapped segments and skips the terminal segment', () {
      final font = _font(
        _cmap(
          platform: 3,
          encoding: 1,
          subtable: _format4([
            (start: 0x41, end: 0x43, delta: -0x40, rangeOffset: 0),
          ]),
        ),
      );
      expect(readSfntCoveredCodePoints(font), {0x41, 0x42, 0x43});
    });

    test('excludes code points whose glyph is zero', () {
      final font = _font(
        _cmap(
          platform: 3,
          encoding: 1,
          subtable: _format4(
            [(start: 0x61, end: 0x63, delta: 0, rangeOffset: 1)],
            glyphIds: [5, 0, 7],
          ),
        ),
      );
      expect(readSfntCoveredCodePoints(font), {0x61, 0x63});
    });

    test('excludes a delta that wraps to glyph zero', () {
      final font = _font(
        _cmap(
          platform: 0,
          encoding: 3,
          subtable: _format4([
            (start: 0x30, end: 0x31, delta: -0x30, rangeOffset: 0),
          ]),
        ),
      );
      expect(readSfntCoveredCodePoints(font), {0x31});
    });
  });

  group('cmap format 12', () {
    test('reads groups beyond the basic plane', () {
      final font = _font(
        _cmap(
          platform: 3,
          encoding: 10,
          subtable: _format12([
            (start: 0x1f600, end: 0x1f602, glyph: 1),
            (start: 0xe000, end: 0xe000, glyph: 9),
          ]),
        ),
      );
      expect(
        readSfntCoveredCodePoints(font),
        {0xe000, 0x1f600, 0x1f601, 0x1f602},
      );
    });

    test('a group starting at glyph zero skips only its first code point', () {
      final font = _font(
        _cmap(
          platform: 3,
          encoding: 10,
          subtable: _format12([(start: 0x100, end: 0x101, glyph: 0)]),
        ),
      );
      expect(readSfntCoveredCodePoints(font), {0x101});
    });

    test('a cmap mapping more than the code point limit is refused', () {
      final font = _font(
        _cmap(
          platform: 3,
          encoding: 10,
          subtable: _format12([
            (start: 0, end: kMaxSfntMappedCodePoints, glyph: 1),
          ]),
        ),
      );
      expect(() => readSfntCoveredCodePoints(font), throwsFormatException);
    });

    test('a subtable shared by two encoding records is read once', () {
      final subtable = _format12([(start: 0x10000, end: 0x18fff, glyph: 1)]);
      final header = ByteData(20)
        ..setUint16(2, 2)
        ..setUint16(4, 0)
        ..setUint16(6, 4)
        ..setUint32(8, 20)
        ..setUint16(12, 3)
        ..setUint16(14, 10)
        ..setUint32(16, 20);
      final cmap = (BytesBuilder()
            ..add(header.buffer.asUint8List())
            ..add(subtable))
          .toBytes();
      expect(readSfntCoveredCodePoints(_font(cmap)), hasLength(0x9000));
    });

    test('a group past the Unicode range is refused', () {
      final font = _font(
        _cmap(
          platform: 3,
          encoding: 10,
          subtable: _format12([(start: 0x10ffff, end: 0x110000, glyph: 1)]),
        ),
      );
      expect(() => readSfntCoveredCodePoints(font), throwsFormatException);
    });
  });

  group('sfnt sanity', () {
    test('accepts TrueType, true and OTTO magic', () {
      final cmap = _cmap(
        platform: 3,
        encoding: 1,
        subtable:
            _format4([(start: 0x41, end: 0x41, delta: 1, rangeOffset: 0)]),
      );
      for (final magic in [0x00010000, 0x74727565, 0x4f54544f]) {
        expect(readSfntCoveredCodePoints(_font(cmap, magic: magic)), {0x41});
      }
    });

    test('an unknown magic is refused', () {
      final font = _font(
        _cmap(
          platform: 3,
          encoding: 1,
          subtable: _format4([(start: 1, end: 1, delta: 1, rangeOffset: 0)]),
        ),
        magic: 0x774f4646,
      );
      expect(() => readSfntCoveredCodePoints(font), throwsFormatException);
    });

    test('a font without a cmap table is refused', () {
      final font = _font(Uint8List(8), tag: 'head');
      expect(() => readSfntCoveredCodePoints(font), throwsFormatException);
    });

    test('a table extending past the file is refused', () {
      final font = _font(
        _cmap(
          platform: 3,
          encoding: 1,
          subtable: _format4([(start: 1, end: 1, delta: 1, rangeOffset: 0)]),
        ),
      );
      final truncated = font.sublist(0, font.length - 4);
      expect(() => readSfntCoveredCodePoints(truncated), throwsFormatException);
    });

    test('a cmap with no Unicode subtable is refused', () {
      final font = _font(
        _cmap(
          platform: 1,
          encoding: 0,
          subtable: _format4([(start: 1, end: 1, delta: 1, rangeOffset: 0)]),
        ),
      );
      expect(() => readSfntCoveredCodePoints(font), throwsFormatException);
    });

    test('an empty input is refused', () {
      expect(
        () => readSfntCoveredCodePoints(Uint8List(0)),
        throwsFormatException,
      );
    });
  });
}

Uint8List _fixture(String name) {
  const dir = 'test/fonts/fixtures';
  final workspace = File('packages/restage_shared/$dir/$name');
  return (workspace.existsSync() ? workspace : File('$dir/$name'))
      .readAsBytesSync();
}

/// A one-table sfnt around [table].
Uint8List _font(
  Uint8List table, {
  int magic = 0x00010000,
  String tag = 'cmap',
}) {
  const headerLength = 12 + 16;
  final out = ByteData(headerLength + table.length)
    ..setUint32(0, magic)
    ..setUint16(4, 1);
  for (var i = 0; i < 4; i += 1) {
    out.setUint8(12 + i, tag.codeUnitAt(i));
  }
  out
    ..setUint32(20, headerLength)
    ..setUint32(24, table.length);
  final bytes = out.buffer.asUint8List();
  bytes.setRange(headerLength, bytes.length, table);
  return bytes;
}

Uint8List _cmap({
  required int platform,
  required int encoding,
  required Uint8List subtable,
}) {
  final header = ByteData(12)
    ..setUint16(0, 0)
    ..setUint16(2, 1)
    ..setUint16(4, platform)
    ..setUint16(6, encoding)
    ..setUint32(8, 12);
  return (BytesBuilder()
        ..add(header.buffer.asUint8List())
        ..add(subtable))
      .toBytes();
}

typedef _Segment = ({int start, int end, int delta, int rangeOffset});

/// A format 4 subtable with [segments] plus the 0xFFFF terminal segment. A
/// segment with a non-zero rangeOffset reads its glyphs from [glyphIds].
Uint8List _format4(List<_Segment> segments, {List<int> glyphIds = const []}) {
  final all = [
    ...segments,
    (start: 0xffff, end: 0xffff, delta: 1, rangeOffset: 0),
  ];
  final segCount = all.length;
  final length = 16 + segCount * 8 + glyphIds.length * 2;
  final out = ByteData(length)
    ..setUint16(0, 4)
    ..setUint16(2, length)
    ..setUint16(6, segCount * 2);
  const endAt = 14;
  final startAt = endAt + segCount * 2 + 2;
  final deltaAt = startAt + segCount * 2;
  final rangeAt = deltaAt + segCount * 2;
  final glyphsAt = rangeAt + segCount * 2;
  for (var i = 0; i < segCount; i += 1) {
    final segment = all[i];
    out
      ..setUint16(endAt + i * 2, segment.end)
      ..setUint16(startAt + i * 2, segment.start)
      ..setUint16(deltaAt + i * 2, segment.delta & 0xffff);
    if (segment.rangeOffset != 0) {
      // Offset from this idRangeOffset slot to the first glyph id.
      out.setUint16(rangeAt + i * 2, glyphsAt - (rangeAt + i * 2));
    }
  }
  for (var i = 0; i < glyphIds.length; i += 1) {
    out.setUint16(glyphsAt + i * 2, glyphIds[i]);
  }
  return out.buffer.asUint8List();
}

Uint8List _format12(List<({int start, int end, int glyph})> groups) {
  final length = 16 + groups.length * 12;
  final out = ByteData(length)
    ..setUint16(0, 12)
    ..setUint32(4, length)
    ..setUint32(12, groups.length);
  for (var i = 0; i < groups.length; i += 1) {
    out
      ..setUint32(16 + i * 12, groups[i].start)
      ..setUint32(20 + i * 12, groups[i].end)
      ..setUint32(24 + i * 12, groups[i].glyph);
  }
  return out.buffer.asUint8List();
}
