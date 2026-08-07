import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

const _signature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
const _ihdr = <int>[73, 72, 68, 82];
const _plte = <int>[80, 76, 84, 69];
const _idat = <int>[73, 68, 65, 84];
const _iend = <int>[73, 69, 78, 68];

/// Maximum accepted encoded size for one render-bundle gallery snapshot.
const int renderBundleSnapshotMaxBytes = 4 * 1024 * 1024;

/// Maximum decoded scanline work for one render-bundle gallery snapshot.
const int renderBundleSnapshotMaxDecodedBytes = 2 * 1024 * 1024;

/// Maximum accepted width or height for one render-bundle gallery snapshot.
const int renderBundleSnapshotMaxDimension = 4096;

/// Validated PNG dimensions.
final class BoundedPngDimensions {
  /// Creates validated dimensions.
  const BoundedPngDimensions({required this.width, required this.height});

  /// IHDR width.
  final int width;

  /// IHDR height.
  final int height;
}

/// One fully validated render-bundle gallery snapshot.
final class ValidatedRenderBundleSnapshotPng {
  /// Creates a validated immutable PNG value.
  const ValidatedRenderBundleSnapshotPng({
    required this.bytes,
    required this.byteLength,
    required this.contentHash,
    required this.width,
    required this.height,
  });

  /// Defensive copy of the validated bytes.
  final Uint8List bytes;

  /// Exact encoded byte length.
  final int byteLength;

  /// SHA-256 identity prefixed with `sha256:`.
  final String contentHash;

  /// Validated IHDR width.
  final int width;

  /// Validated IHDR height.
  final int height;
}

/// Validates and snapshots one canonical render-bundle gallery PNG.
///
/// The theoretical scanline ceiling is checked before any inflate work. The
/// raw DEFLATE stream then writes into a fixed-capacity output that retains no
/// more than the already-approved decoded bound.
ValidatedRenderBundleSnapshotPng validateRenderBundleSnapshotPng(
  Uint8List source,
) {
  final dimensions = validateBoundedPng(
    source,
    maxBytes: renderBundleSnapshotMaxBytes,
    maxDimension: renderBundleSnapshotMaxDimension,
  );
  _validateSnapshotScanlines(
    source,
    width: dimensions.width,
    height: dimensions.height,
  );
  final bytes = Uint8List.fromList(source).asUnmodifiableView();
  return ValidatedRenderBundleSnapshotPng(
    bytes: bytes,
    byteLength: bytes.length,
    contentHash: 'sha256:${crypto.sha256.convert(bytes)}',
    width: dimensions.width,
    height: dimensions.height,
  );
}

/// Structurally validates a bounded PNG, including every chunk CRC.
BoundedPngDimensions validateBoundedPng(
  Uint8List source, {
  required int maxBytes,
  required int maxDimension,
}) {
  if (maxBytes < 45 ||
      maxDimension < 1 ||
      source.length < 45 ||
      source.length > maxBytes ||
      !_same(source.sublist(0, _signature.length), _signature)) {
    throw const FormatException('Invalid PNG.');
  }
  final data = ByteData.sublistView(source);
  var offset = _signature.length;
  var chunkIndex = 0;
  var sawPalette = false;
  var sawImageData = false;
  var imageDataEnded = false;
  var colorType = -1;
  var width = 0;
  var height = 0;

  while (offset < source.length) {
    if (source.length - offset < 12) {
      throw const FormatException('Invalid PNG.');
    }
    final chunkLength = data.getUint32(offset);
    final typeOffset = offset + 4;
    final payloadOffset = typeOffset + 4;
    final crcOffset = payloadOffset + chunkLength;
    final nextOffset = crcOffset + 4;
    if (nextOffset > source.length) throw const FormatException('Invalid PNG.');
    final type = source.sublist(typeOffset, payloadOffset);
    if (!_validChunkType(type)) throw const FormatException('Invalid PNG.');
    if (_crc32(source, typeOffset, crcOffset) != data.getUint32(crcOffset)) {
      throw const FormatException('Invalid PNG.');
    }

    if (chunkIndex == 0) {
      if (chunkLength != 13 || !_same(type, _ihdr)) {
        throw const FormatException('Invalid PNG.');
      }
      width = data.getUint32(payloadOffset);
      height = data.getUint32(payloadOffset + 4);
      final bitDepth = source[payloadOffset + 8];
      colorType = source[payloadOffset + 9];
      if (width < 1 ||
          width > maxDimension ||
          height < 1 ||
          height > maxDimension ||
          !_validBitDepth(bitDepth, colorType) ||
          source[payloadOffset + 10] != 0 ||
          source[payloadOffset + 11] != 0 ||
          source[payloadOffset + 12] > 1) {
        throw const FormatException('Invalid PNG.');
      }
    } else if (_same(type, _ihdr)) {
      throw const FormatException('Invalid PNG.');
    } else if (_same(type, _plte)) {
      if (sawPalette ||
          sawImageData ||
          colorType == 0 ||
          colorType == 4 ||
          chunkLength == 0 ||
          chunkLength > 768 ||
          chunkLength % 3 != 0) {
        throw const FormatException('Invalid PNG.');
      }
      sawPalette = true;
    } else if (_same(type, _idat)) {
      if (imageDataEnded || (colorType == 3 && !sawPalette)) {
        throw const FormatException('Invalid PNG.');
      }
      sawImageData = true;
    } else if (_same(type, _iend)) {
      if (!sawImageData || chunkLength != 0 || nextOffset != source.length) {
        throw const FormatException('Invalid PNG.');
      }
      return BoundedPngDimensions(width: width, height: height);
    } else if (type.first >= 0x41 && type.first <= 0x5a) {
      throw const FormatException('Invalid PNG.');
    }
    if (!_same(type, _idat) && sawImageData) imageDataEnded = true;
    offset = nextOffset;
    chunkIndex++;
  }
  throw const FormatException('Invalid PNG.');
}

void _validateSnapshotScanlines(
  Uint8List source, {
  required int width,
  required int height,
}) {
  if (source[28] != 0) {
    throw const FormatException('Invalid PNG scanlines.');
  }
  final bitDepth = source[24];
  final colorType = source[25];
  final channels = switch (colorType) {
    0 || 3 => 1,
    2 => 3,
    4 => 2,
    6 => 4,
    _ => throw const FormatException('Invalid PNG scanlines.'),
  };
  final rowBytes = (width * bitDepth * channels + 7) ~/ 8;
  final stride = rowBytes + 1;
  if (stride > renderBundleSnapshotMaxDecodedBytes ||
      height > renderBundleSnapshotMaxDecodedBytes ~/ stride) {
    throw const FormatException('Invalid PNG scanlines.');
  }
  final expectedDecodedBytes = stride * height;
  final compressed = BytesBuilder(copy: false);
  final data = ByteData.sublistView(source);
  var offset = _signature.length;
  while (offset < source.length) {
    final length = data.getUint32(offset);
    final typeOffset = offset + 4;
    final payloadOffset = typeOffset + 4;
    if (_matchesAt(source, typeOffset, _idat)) {
      compressed.add(
        Uint8List.sublistView(source, payloadOffset, payloadOffset + length),
      );
    }
    offset = payloadOffset + length + 4;
  }
  _inflateScanlines(
    compressed.takeBytes(),
    stride: stride,
    expectedBytes: expectedDecodedBytes,
  );
}

void _inflateScanlines(
  Uint8List zlib, {
  required int stride,
  required int expectedBytes,
}) {
  if (zlib.length < 6) {
    throw const FormatException('Invalid PNG scanlines.');
  }
  final cmf = zlib[0];
  final flg = zlib[1];
  if ((cmf & 0x0f) != 8 ||
      (cmf >> 4) > 7 ||
      ((cmf << 8) | flg) % 31 != 0 ||
      (flg & 0x20) != 0) {
    throw const FormatException('Invalid PNG scanlines.');
  }
  final checksumOffset = zlib.length - 4;
  final expectedAdler = ByteData.sublistView(zlib).getUint32(checksumOffset);
  final output = _BoundedScanlineOutput(
    capacity: expectedBytes,
    stride: stride,
  );
  try {
    _StrictDeflateDecoder(
      Uint8List.sublistView(zlib, 2, checksumOffset),
      output,
      maximumDistance: 1 << ((cmf >> 4) + 8),
    ).decode();
  } on Object {
    throw const FormatException('Invalid PNG scanlines.');
  }
  if (output.length != expectedBytes || output.adler32 != expectedAdler) {
    throw const FormatException('Invalid PNG scanlines.');
  }
}

final class _BoundedScanlineOutput {
  _BoundedScanlineOutput({required int capacity, required this.stride})
      : _bytes = Uint8List(capacity);

  final Uint8List _bytes;
  final int stride;
  var _length = 0;
  var _adlerS1 = 1;
  var _adlerS2 = 0;

  int get length => _length;

  int get adler32 => ((_adlerS2 % 65521) << 16) | (_adlerS1 % 65521);

  void writeByte(int value) {
    if (_length >= _bytes.length) {
      throw const FormatException('Invalid PNG scanlines.');
    }
    final byte = value & 0xff;
    if (_length % stride == 0 && byte > 4) {
      throw const FormatException('Invalid PNG scanlines.');
    }
    _bytes[_length++] = byte;
    _adlerS1 += byte;
    _adlerS2 += _adlerS1;
    if (_adlerS2 >= 0x3fffffff) {
      _adlerS1 %= 65521;
      _adlerS2 %= 65521;
    }
  }

  void copyFromDistance(int distance, int count) {
    if (distance < 1 ||
        distance > _length ||
        count < 0 ||
        count > _bytes.length - _length) {
      throw const FormatException('Invalid PNG scanlines.');
    }
    for (var index = 0; index < count; index++) {
      writeByte(_bytes[_length - distance]);
    }
  }
}

final class _StrictDeflateDecoder {
  _StrictDeflateDecoder(
    Uint8List bytes,
    this._output, {
    required int maximumDistance,
  })  : _maximumDistance = maximumDistance,
        _reader = _DeflateBitReader(bytes);

  final _DeflateBitReader _reader;
  final _BoundedScanlineOutput _output;
  final int _maximumDistance;

  static final _fixedLiteralLengthTable = _StrictHuffmanTable(
    <int>[
      ...List<int>.filled(144, 8),
      ...List<int>.filled(112, 9),
      ...List<int>.filled(24, 7),
      ...List<int>.filled(8, 8),
    ],
    allowSingleCode: false,
  );
  static final _fixedDistanceAlphabet = _DeflateDistanceAlphabet.fixed(
    List<int>.filled(32, 5),
  );

  static const _codeLengthOrder = <int>[
    16,
    17,
    18,
    0,
    8,
    7,
    9,
    6,
    10,
    5,
    11,
    4,
    12,
    3,
    13,
    2,
    14,
    1,
    15,
  ];
  static const _lengthBases = <int>[
    3,
    4,
    5,
    6,
    7,
    8,
    9,
    10,
    11,
    13,
    15,
    17,
    19,
    23,
    27,
    31,
    35,
    43,
    51,
    59,
    67,
    83,
    99,
    115,
    131,
    163,
    195,
    227,
    258,
  ];
  static const _lengthExtraBits = <int>[
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    1,
    1,
    1,
    1,
    2,
    2,
    2,
    2,
    3,
    3,
    3,
    3,
    4,
    4,
    4,
    4,
    5,
    5,
    5,
    5,
    0,
  ];
  static const _distanceBases = <int>[
    1,
    2,
    3,
    4,
    5,
    7,
    9,
    13,
    17,
    25,
    33,
    49,
    65,
    97,
    129,
    193,
    257,
    385,
    513,
    769,
    1025,
    1537,
    2049,
    3073,
    4097,
    6145,
    8193,
    12289,
    16385,
    24577,
  ];
  static const _distanceExtraBits = <int>[
    0,
    0,
    0,
    0,
    1,
    1,
    2,
    2,
    3,
    3,
    4,
    4,
    5,
    5,
    6,
    6,
    7,
    7,
    8,
    8,
    9,
    9,
    10,
    10,
    11,
    11,
    12,
    12,
    13,
    13,
  ];

  void decode() {
    var finalBlock = false;
    while (!finalBlock) {
      finalBlock = _reader.readBits(1) == 1;
      switch (_reader.readBits(2)) {
        case 0:
          _decodeStoredBlock();
        case 1:
          _decodeHuffmanBlock(
            _fixedLiteralLengthTable,
            _fixedDistanceAlphabet,
          );
        case 2:
          _decodeDynamicBlock();
        default:
          throw const FormatException('Invalid DEFLATE block.');
      }
    }
    _reader.requireZeroPaddingAndEnd();
  }

  void _decodeStoredBlock() {
    _reader.alignToByte();
    final length = _reader.readBits(16);
    final complement = _reader.readBits(16);
    if ((length ^ 0xffff) != complement) {
      throw const FormatException('Invalid DEFLATE stored block.');
    }
    if (length > _output._bytes.length - _output.length) {
      throw const FormatException('Invalid PNG scanlines.');
    }
    for (var index = 0; index < length; index++) {
      _output.writeByte(_reader.readBits(8));
    }
  }

  void _decodeDynamicBlock() {
    final literalLengthCount = _reader.readBits(5) + 257;
    final distanceCount = _reader.readBits(5) + 1;
    final codeLengthCount = _reader.readBits(4) + 4;
    if (literalLengthCount > 286 || distanceCount > 32) {
      throw const FormatException('Invalid DEFLATE dynamic block.');
    }

    final codeLengthLengths = List<int>.filled(19, 0);
    for (var index = 0; index < codeLengthCount; index++) {
      codeLengthLengths[_codeLengthOrder[index]] = _reader.readBits(3);
    }
    final codeLengthTable = _StrictHuffmanTable(
      codeLengthLengths,
      allowSingleCode: false,
    );
    final combined = <int>[];
    final targetLength = literalLengthCount + distanceCount;
    while (combined.length < targetLength) {
      final symbol = codeLengthTable.decode(_reader);
      if (symbol <= 15) {
        combined.add(symbol);
        continue;
      }
      final repeat = switch (symbol) {
        16 => _reader.readBits(2) + 3,
        17 => _reader.readBits(3) + 3,
        18 => _reader.readBits(7) + 11,
        _ => throw const FormatException('Invalid DEFLATE code lengths.'),
      };
      if (repeat > targetLength - combined.length) {
        throw const FormatException('Invalid DEFLATE code lengths.');
      }
      if (symbol == 16) {
        if (combined.isEmpty) {
          throw const FormatException('Invalid DEFLATE code lengths.');
        }
        combined.addAll(List<int>.filled(repeat, combined.last));
      } else {
        combined.addAll(List<int>.filled(repeat, 0));
      }
    }

    final literalLengths = combined.sublist(0, literalLengthCount);
    if (literalLengths[256] == 0) {
      throw const FormatException('Missing DEFLATE end-of-block code.');
    }
    _decodeHuffmanBlock(
      _StrictHuffmanTable(literalLengths, allowSingleCode: true),
      _DeflateDistanceAlphabet.dynamic(
        combined.sublist(literalLengthCount),
      ),
    );
  }

  void _decodeHuffmanBlock(
    _StrictHuffmanTable literalLengthTable,
    _DeflateDistanceAlphabet distanceAlphabet,
  ) {
    while (true) {
      final symbol = literalLengthTable.decode(_reader);
      if (symbol < 256) {
        _output.writeByte(symbol);
        continue;
      }
      if (symbol == 256) return;
      if (symbol > 285) {
        throw const FormatException('Invalid DEFLATE length code.');
      }
      final lengthIndex = symbol - 257;
      final length = _lengthBases[lengthIndex] +
          _reader.readBits(_lengthExtraBits[lengthIndex]);
      final distanceSymbol = distanceAlphabet.decode(_reader);
      if (distanceSymbol > 29) {
        throw const FormatException('Invalid DEFLATE distance code.');
      }
      final distance = _distanceBases[distanceSymbol] +
          _reader.readBits(_distanceExtraBits[distanceSymbol]);
      if (distance > _maximumDistance) {
        throw const FormatException('Invalid DEFLATE window distance.');
      }
      _output.copyFromDistance(distance, length);
    }
  }
}

final class _DeflateBitReader {
  _DeflateBitReader(this._bytes);

  final Uint8List _bytes;
  var _bitPosition = 0;

  int readBits(int count) {
    if (count < 0 || count > 16 || _bitPosition + count > _bytes.length * 8) {
      throw const FormatException('Truncated DEFLATE stream.');
    }
    var value = 0;
    for (var bit = 0; bit < count; bit++) {
      final source = _bytes[_bitPosition >> 3];
      value |= ((source >> (_bitPosition & 7)) & 1) << bit;
      _bitPosition++;
    }
    return value;
  }

  void alignToByte() {
    _bitPosition = (_bitPosition + 7) & ~7;
    if (_bitPosition > _bytes.length * 8) {
      throw const FormatException('Truncated DEFLATE stream.');
    }
  }

  void requireZeroPaddingAndEnd() {
    final padding = (8 - (_bitPosition & 7)) & 7;
    // Canonical render-bundle snapshots intentionally use a stricter envelope
    // than RFC 1951 by requiring every terminal pad bit to be zero.
    if (padding != 0 && readBits(padding) != 0) {
      throw const FormatException('Invalid DEFLATE terminal padding.');
    }
    if (_bitPosition != _bytes.length * 8) {
      throw const FormatException('Trailing DEFLATE bytes.');
    }
  }
}

final class _DeflateDistanceAlphabet {
  _DeflateDistanceAlphabet.fixed(List<int> codeLengths)
      : _table = _StrictHuffmanTable(
          codeLengths,
          allowSingleCode: false,
        );

  _DeflateDistanceAlphabet.dynamic(List<int> codeLengths)
      : _table = codeLengths.length == 1 && codeLengths.single == 0
            ? null
            : _StrictHuffmanTable(
                codeLengths,
                allowSingleCode: true,
              );

  final _StrictHuffmanTable? _table;

  int decode(_DeflateBitReader reader) {
    final table = _table;
    if (table == null) {
      throw const FormatException('Missing DEFLATE distance alphabet.');
    }
    return table.decode(reader);
  }
}

final class _StrictHuffmanTable {
  _StrictHuffmanTable(
    List<int> codeLengths, {
    required bool allowSingleCode,
  }) {
    const maximumCodeLength = 15;
    final counts = List<int>.filled(maximumCodeLength + 1, 0);
    var nonzeroCount = 0;
    var maximumUsedLength = 0;
    for (final length in codeLengths) {
      if (length < 0 || length > maximumCodeLength) {
        throw const FormatException('Invalid DEFLATE Huffman length.');
      }
      if (length != 0) {
        counts[length]++;
        nonzeroCount++;
        if (length > maximumUsedLength) maximumUsedLength = length;
      }
    }
    if (nonzeroCount == 0) {
      throw const FormatException('Empty DEFLATE Huffman table.');
    }

    var unusedCodes = 1;
    for (var length = 1; length <= maximumUsedLength; length++) {
      unusedCodes = (unusedCodes << 1) - counts[length];
      if (unusedCodes < 0) {
        throw const FormatException('Oversubscribed DEFLATE Huffman table.');
      }
    }
    if (unusedCodes != 0 &&
        !(allowSingleCode && nonzeroCount == 1 && maximumUsedLength == 1)) {
      throw const FormatException('Incomplete DEFLATE Huffman table.');
    }

    _maximumCodeLength = maximumUsedLength;
    _symbolsByLength =
        List<Map<int, int>>.generate(maximumUsedLength + 1, (_) => {});
    final nextCode = List<int>.filled(maximumUsedLength + 1, 0);
    var code = 0;
    for (var length = 1; length <= maximumUsedLength; length++) {
      code = (code + counts[length - 1]) << 1;
      nextCode[length] = code;
    }
    for (var symbol = 0; symbol < codeLengths.length; symbol++) {
      final length = codeLengths[symbol];
      if (length != 0) {
        _symbolsByLength[length][nextCode[length]++] = symbol;
      }
    }
  }

  late final int _maximumCodeLength;
  late final List<Map<int, int>> _symbolsByLength;

  int decode(_DeflateBitReader reader) {
    var code = 0;
    for (var length = 1; length <= _maximumCodeLength; length++) {
      code = (code << 1) | reader.readBits(1);
      final symbol = _symbolsByLength[length][code];
      if (symbol != null) return symbol;
    }
    throw const FormatException('Invalid DEFLATE Huffman code.');
  }
}

bool _validChunkType(List<int> type) {
  if (type.length != 4 || type[2] < 0x41 || type[2] > 0x5a) return false;
  for (final byte in type) {
    final isUpper = byte >= 0x41 && byte <= 0x5a;
    final isLower = byte >= 0x61 && byte <= 0x7a;
    if (!isUpper && !isLower) return false;
  }
  return true;
}

bool _validBitDepth(int bitDepth, int colorType) => switch (colorType) {
      0 => const {1, 2, 4, 8, 16}.contains(bitDepth),
      2 => const {8, 16}.contains(bitDepth),
      3 => const {1, 2, 4, 8}.contains(bitDepth),
      4 || 6 => const {8, 16}.contains(bitDepth),
      _ => false,
    };

bool _matchesAt(Uint8List actual, int offset, List<int> expected) {
  if (offset < 0 || actual.length - offset < expected.length) return false;
  for (var index = 0; index < expected.length; index++) {
    if (actual[offset + index] != expected[index]) return false;
  }
  return true;
}

bool _same(List<int> actual, List<int> expected) {
  if (actual.length != expected.length) return false;
  for (var index = 0; index < actual.length; index++) {
    if (actual[index] != expected[index]) return false;
  }
  return true;
}

int _crc32(Uint8List bytes, int start, int end) {
  var crc = 0xffffffff;
  for (var index = start; index < end; index++) {
    crc ^= bytes[index];
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc & 1) == 1 ? 0xedb88320 ^ (crc >>> 1) : crc >>> 1;
    }
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}
