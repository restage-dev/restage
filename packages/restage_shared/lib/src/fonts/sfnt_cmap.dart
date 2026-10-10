import 'dart:typed_data';

const int _trueTypeMagic = 0x00010000;
const int _appleTrueTypeMagic = 0x74727565; // 'true'
const int _openTypeCffMagic = 0x4f54544f; // 'OTTO'
const int _cmapTag = 0x636d6170; // 'cmap'
const int _maxUnicode = 0x10ffff;

/// The most code points a cmap may map, across all subtables read.
const int kMaxSfntMappedCodePoints = 0x10000;

/// Returns the Unicode code points an sfnt font (TrueType or OpenType) maps to
/// a glyph, read from its cmap format 4 and 12 subtables.
///
/// Throws a [FormatException] when the bytes are not a well-formed sfnt with a
/// Unicode cmap, or when its subtables map more than [kMaxSfntMappedCodePoints]
/// code points.
Set<int> readSfntCoveredCodePoints(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  final cmap = _findCmap(data);
  final numTables = _u16(data, cmap.offset + 2, cmap);
  final covered = _Coverage();
  var readUnicodeSubtable = false;
  final readOffsets = <int>{};
  for (var index = 0; index < numTables; index += 1) {
    final record = cmap.offset + 4 + index * 8;
    final platform = _u16(data, record, cmap);
    final encoding = _u16(data, record + 2, cmap);
    if (!_isUnicode(platform, encoding)) continue;
    final subtable = cmap.offset + _u32(data, record + 4, cmap);
    // Encoding records commonly share one subtable; read it once.
    if (!readOffsets.add(subtable)) continue;
    switch (_u16(data, subtable, cmap)) {
      case 4:
        _readFormat4(data, subtable, cmap, covered);
        readUnicodeSubtable = true;
      case 12:
        _readFormat12(data, subtable, cmap, covered);
        readUnicodeSubtable = true;
    }
  }
  if (!readUnicodeSubtable) {
    throw const FormatException(
      'The font has no Unicode cmap subtable of format 4 or 12.',
    );
  }
  return covered.codePoints;
}

final class _Coverage {
  final Set<int> codePoints = <int>{};
  int _visited = 0;

  void visit() {
    _visited += 1;
    if (_visited > kMaxSfntMappedCodePoints) {
      throw const FormatException('The font maps too many code points.');
    }
  }
}

typedef _Range = ({int offset, int end});

bool _isUnicode(int platform, int encoding) =>
    platform == 0 || (platform == 3 && (encoding == 1 || encoding == 10));

_Range _findCmap(ByteData data) {
  final file = (offset: 0, end: data.lengthInBytes);
  final magic = _u32(data, 0, file);
  if (magic != _trueTypeMagic &&
      magic != _appleTrueTypeMagic &&
      magic != _openTypeCffMagic) {
    throw const FormatException('Not an sfnt font.');
  }
  final numTables = _u16(data, 4, file);
  if (numTables == 0) {
    throw const FormatException('The font has no tables.');
  }
  _Range? cmap;
  for (var index = 0; index < numTables; index += 1) {
    final record = 12 + index * 16;
    final tag = _u32(data, record, file);
    final offset = _u32(data, record + 8, file);
    final length = _u32(data, record + 12, file);
    if (offset + length > data.lengthInBytes) {
      throw const FormatException('A font table extends past the file.');
    }
    if (tag == _cmapTag) cmap = (offset: offset, end: offset + length);
  }
  if (cmap == null) {
    throw const FormatException('The font has no cmap table.');
  }
  return cmap;
}

void _readFormat4(ByteData data, int at, _Range cmap, _Coverage out) {
  final segCount = _u16(data, at + 6, cmap) ~/ 2;
  final endAt = at + 14;
  final startAt = endAt + segCount * 2 + 2;
  final deltaAt = startAt + segCount * 2;
  final rangeAt = deltaAt + segCount * 2;
  for (var i = 0; i < segCount; i += 1) {
    final end = _u16(data, endAt + i * 2, cmap);
    final start = _u16(data, startAt + i * 2, cmap);
    final delta = _u16(data, deltaAt + i * 2, cmap);
    final rangeSlot = rangeAt + i * 2;
    final rangeOffset = _u16(data, rangeSlot, cmap);
    if (start > end) {
      throw const FormatException('A cmap segment ends before it starts.');
    }
    for (var codePoint = start; codePoint <= end; codePoint += 1) {
      if (codePoint == 0xffff) continue;
      out.visit();
      var glyph = 0;
      if (rangeOffset == 0) {
        glyph = (codePoint + delta) & 0xffff;
      } else {
        final glyphAt = rangeSlot + rangeOffset + (codePoint - start) * 2;
        final raw = _u16(data, glyphAt, cmap);
        if (raw != 0) glyph = (raw + delta) & 0xffff;
      }
      if (glyph != 0) out.codePoints.add(codePoint);
    }
  }
}

void _readFormat12(ByteData data, int at, _Range cmap, _Coverage out) {
  final groups = _u32(data, at + 12, cmap);
  for (var i = 0; i < groups; i += 1) {
    final group = at + 16 + i * 12;
    final start = _u32(data, group, cmap);
    final end = _u32(data, group + 4, cmap);
    final firstGlyph = _u32(data, group + 8, cmap);
    if (start > end || end > _maxUnicode) {
      throw const FormatException('A cmap group is outside Unicode.');
    }
    for (var codePoint = start; codePoint <= end; codePoint += 1) {
      out.visit();
      if (firstGlyph + (codePoint - start) != 0) out.codePoints.add(codePoint);
    }
  }
}

int _u16(ByteData data, int at, _Range range) {
  if (at < range.offset || at + 2 > range.end) {
    throw const FormatException('Truncated font table.');
  }
  return data.getUint16(at);
}

int _u32(ByteData data, int at, _Range range) {
  if (at < range.offset || at + 4 > range.end) {
    throw const FormatException('Truncated font table.');
  }
  return data.getUint32(at);
}
