import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

void main() {
  group('render-bundle snapshot PNG validation', () {
    test('accepts a normal canonical PNG and derives exact metadata', () {
      final png = Uint8List.fromList(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNg'
          'YAAAAAMAASsJTYQAAAAASUVORK5CYII=',
        ),
      );

      final validated = validateRenderBundleSnapshotPng(png);

      expect(validated.bytes, orderedEquals(png));
      expect(validated.byteLength, png.length);
      expect(validated.contentHash, CapabilitySidecar.hashBlob(png));
      expect(validated.width, 1);
      expect(validated.height, 1);
    });

    test('accepts complete fixed, dynamic, and stored DEFLATE blocks', () {
      final fixed = Uint8List.fromList(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNg'
          'YAAAAAMAASsJTYQAAAAASUVORK5CYII=',
        ),
      );
      final dynamic = _replaceIdat(
        _png(width: 512, height: 1, bitDepth: 8, colorType: 0),
        base64Decode(
          'eNql0YdWCAAAQNFKykgilFIkZIUihYpKMjOikGQkKilCaSpaGiRFQ0YalGRL'
          'GVlpiHZpyJbVMNrj/UOfcM8VEBi/1O5UWo3wJEOHMw8+9FNe4xid+UVMxdjl'
          '/PPvEmobPS5l/x42Z/ORxFdN0lrbfJML/o/SsQxILWkbo299/FZF17gle0Lv'
          'VQtNXLHvdMZ7kamrD0Y9/jxgxjrnc8/qxGdtcI99+WuohplXQl7jCM2tPklv'
          '/sks2HHsWnGr/EKr4JvlnWMX2568WyU4Yfne8PTavpNXHYh89Kn/tLWHYp5+'
          'G6S63u1i1s8hszd5xuc2DJ+7xfvK678jtS38U4pa5HR3Bd0o61BYtDvkTiUA'
          '+7D77wDsj3j4EYDT2SdfAbheePEDwOG4nHoARy/n/wHgd7WwGUDg9dJ2ACdu'
          'v+0GAL8PAPiiAOAPBAB/MAD4kgDgSwGALwsA/mgA8BUBwFcCAH8KAPjTAcCf'
          'CQC+OgD48wDAnw8Avh4A+AYA4C8DAH8lAPhGAOCbAIBvCgC+OQD42wHA3wkA'
          'vg2A3v71APkO/iY=',
        ),
      );
      final stored = _replaceIdat(
        _png(width: 1, height: 1, bitDepth: 8, colorType: 6),
        _storedZlib(const <int>[0, 0, 0, 0, 0]),
      );

      expect(_firstDeflateBlockType(_idat(fixed)), 1);
      expect(_firstDeflateBlockType(_idat(dynamic)), 2);
      expect(_firstDeflateBlockType(_idat(stored)), 0);
      expect(() => validateRenderBundleSnapshotPng(fixed), returnsNormally);
      expect(() => validateRenderBundleSnapshotPng(dynamic), returnsNormally);
      expect(() => validateRenderBundleSnapshotPng(stored), returnsNormally);
    });

    test('accepts a literal-only dynamic block with no distance alphabet', () {
      const scanline = <int>[0, 0, 0, 0, 0];
      final valid = _png(width: 1, height: 1, bitDepth: 8, colorType: 6);
      final literalOnly = _replaceIdat(
        valid,
        _emptyDistanceDynamicZlib(scanline, useLengthCode: false),
      );

      expect(_firstDeflateBlockType(_idat(literalOnly)), 2);
      expect(
        () => validateRenderBundleSnapshotPng(literalOnly),
        returnsNormally,
      );
    });

    test('rejects length use from an empty dynamic distance alphabet', () {
      const scanline = <int>[0, 0, 0, 0, 0];
      final valid = _png(width: 1, height: 1, bitDepth: 8, colorType: 6);
      final missingDistance = _replaceIdat(
        valid,
        _emptyDistanceDynamicZlib(scanline, useLengthCode: true),
      );

      expect(
        () => validateRenderBundleSnapshotPng(missingDistance),
        throwsFormatException,
      );
    });

    test('accepts decoded scanline work exactly at the ceiling', () {
      final boundary = _png(
        width: 511,
        height: 4096,
        bitDepth: 8,
        colorType: 0,
      );

      expect((511 + 1) * 4096, renderBundleSnapshotMaxDecodedBytes);
      final validated = validateRenderBundleSnapshotPng(boundary);
      expect(validated.width, 511);
      expect(validated.height, 4096);
    });

    test('rejects a compressed PNG over the decoded ceiling', () {
      final compressedBomb = _png(
        width: 1024,
        height: 1024,
        bitDepth: 8,
        colorType: 6,
      );

      expect(compressedBomb.length, lessThan(renderBundleSnapshotMaxBytes));
      expect(
        (1024 * 4 + 1) * 1024,
        greaterThan(renderBundleSnapshotMaxDecodedBytes),
      );
      expect(
        () => validateRenderBundleSnapshotPng(compressedBomb),
        throwsFormatException,
      );
    });

    test('rejects a small-IHDR stream that overruns its exact scanline size',
        () {
      final onePixel = _png(
        width: 1,
        height: 1,
        bitDepth: 8,
        colorType: 6,
      );
      final lyingStream = _replaceIdat(
        onePixel,
        const ZLibEncoder().encodeBytes(Uint8List(64 * 1024)),
      );

      expect(lyingStream.length, lessThan(renderBundleSnapshotMaxBytes));
      expect(
        () => validateRenderBundleSnapshotPng(lyingStream),
        throwsFormatException,
      );
    });

    test('rejects malformed chunks and bounded scanline envelopes', () {
      final valid = _png(width: 1, height: 1, bitDepth: 8, colorType: 6);
      final badCrc = Uint8List.fromList(valid)..[41] ^= 1;
      final invalidZlib = _replaceIdat(valid, const <int>[1, 2, 3]);
      final interlaced = _png(
        width: 1,
        height: 1,
        bitDepth: 8,
        colorType: 6,
        interlace: 1,
      );
      final invalidFilter = _replaceIdat(
        valid,
        const ZLibEncoder().encodeBytes(const <int>[5, 0, 0, 0, 0]),
      );
      final shortScanline = _replaceIdat(
        valid,
        const ZLibEncoder().encodeBytes(const <int>[0, 0, 0, 0]),
      );

      for (final malformed in <Uint8List>[
        badCrc,
        invalidZlib,
        interlaced,
        invalidFilter,
        shortScanline,
      ]) {
        expect(
          () => validateRenderBundleSnapshotPng(malformed),
          throwsFormatException,
        );
      }
    });

    test('rejects incomplete, malformed, and trailing DEFLATE data', () {
      final valid = _png(width: 1, height: 1, bitDepth: 8, colorType: 6);
      const scanline = <int>[0, 0, 0, 0, 0];
      final fixed = _fixedZlib(scanline);
      final stored = _storedZlib(scanline);
      final rawEnd = fixed.length - 4;
      final truncatedEndOfBlock = Uint8List.fromList(<int>[
        ...fixed.sublist(0, rawEnd - 1),
        ...fixed.sublist(rawEnd),
      ]);
      final invalidFinalBlock = Uint8List.fromList(<int>[
        0x78,
        0x01,
        0x07,
        ..._uint32(_adler32(scanline)),
      ]);
      final badStoredComplement = Uint8List.fromList(stored)..[5] ^= 1;
      final trailingRawByte = Uint8List.fromList(<int>[
        ...fixed.sublist(0, rawEnd),
        0,
        ...fixed.sublist(rawEnd),
      ]);
      final nonzeroTerminalPadding = Uint8List.fromList(fixed)
        ..[rawEnd - 1] |= 0x80;
      final badAdler = Uint8List.fromList(fixed)..[fixed.length - 1] ^= 1;
      final oversubscribedTree = _malformedDynamicZlib(
        codeLengthCodeLengths: const <int>[1, 1, 1, 0],
        scanline: scanline,
      );
      final incompleteTree = _malformedDynamicZlib(
        codeLengthCodeLengths: const <int>[2, 0, 0, 0],
        scanline: scanline,
      );
      final invalidDistanceWriter = _DeflateFixtureWriter()
        ..writeBits(1, 1)
        ..writeBits(1, 2);
      _writeFixedSymbol(invalidDistanceWriter, 257);
      invalidDistanceWriter.writeHuffmanCode(0, 5);
      final invalidDistance = _rawZlib(
        invalidDistanceWriter.takeBytes(),
        scanline,
      );

      for (final malformedZlib in <Uint8List>[
        truncatedEndOfBlock,
        invalidFinalBlock,
        badStoredComplement,
        trailingRawByte,
        nonzeroTerminalPadding,
        badAdler,
        oversubscribedTree,
        incompleteTree,
        invalidDistance,
      ]) {
        expect(
          () => validateRenderBundleSnapshotPng(
            _replaceIdat(valid, malformedZlib),
          ),
          throwsFormatException,
        );
      }
    });

    test('rejects a stream with output but no valid final EOB', () {
      final malformed = Uint8List.fromList(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAAAAAA6fptVAAAACklEQVR4'
          'nGJgAAAAAgABhAWk7wAAAABJRU5ErkJggg==',
        ),
      );

      expect(
        () => validateRenderBundleSnapshotPng(malformed),
        throwsFormatException,
      );
    });
  });

  group('placement screen-sample PNG validation', () {
    test('retains the encoded and dimension limits with a larger decoded bound',
        () {
      expect(placementScreenSampleMaxBytes, 4 * 1024 * 1024);
      expect(placementScreenSampleMaxDecodedBytes, 16 * 1024 * 1024);
      expect(placementScreenSampleMaxDimension, 4096);
      expect(renderBundleSnapshotMaxBytes, 4 * 1024 * 1024);
      expect(renderBundleSnapshotMaxDecodedBytes, 2 * 1024 * 1024);
      expect(renderBundleSnapshotMaxDimension, 4096);
    });

    test('accepts actual Flutter encoder bytes with exact immutable identity',
        () {
      final source = _flutterScreenSample();
      final original = Uint8List.fromList(source);

      final validated = validatePlacementScreenSamplePng(source);

      expect(validated.bytes, orderedEquals(original));
      expect(validated.byteLength, 98);
      expect(
        validated.contentHash,
        'sha256:'
        '0e3522ce70305eed445ac3d5f43b2e932a1c8991c8e443c52e8e4e48c35d05e8',
      );
      expect(validated.contentHash, CapabilitySidecar.hashBlob(original));
      expect(validated.width, 3);
      expect(validated.height, 2);
      source[0] ^= 1;
      expect(validated.bytes, orderedEquals(original));
      expect(() => validated.bytes[0] = 0, throwsUnsupportedError);
      expect(
        () => validated.bytes.buffer.asUint8List()[0] = 0,
        throwsUnsupportedError,
      );
      expect(() => validateRenderBundleSnapshotPng(original), returnsNormally);
    });

    for (final (type, payload) in <(String, List<int>)>[
      ('tEXt', utf8.encode('sample\u0000hidden text')),
      (
        'zTXt',
        <int>[
          ...utf8.encode('sample\u0000'),
          0,
          ...const ZLibEncoder().encodeBytes(utf8.encode('hidden text')),
        ],
      ),
      ('iTXt', utf8.encode('sample\u0000\u0000\u0000\u0000\u0000hidden text')),
      ('eXIf', const <int>[73, 73, 42, 0, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
    ]) {
      test('rejects valid-CRC $type metadata only for samples', () {
        final source = _flutterScreenSample();
        for (final beforeType in <String>['IDAT', 'IEND']) {
          final withMetadata = _insertChunkBefore(
            source,
            beforeType: beforeType,
            type: type,
            payload: payload,
          );

          expect(
            () => validateRenderBundleSnapshotPng(withMetadata),
            returnsNormally,
          );
          expect(
            () => validatePlacementScreenSamplePng(withMetadata),
            throwsFormatException,
          );
        }
      });
    }

    test('accepts color, palette, alpha and other ancillary chunks', () {
      var source = _png(width: 1, height: 1, bitDepth: 8, colorType: 3);
      for (final (type, payload) in <(String, List<int>)>[
        ('sRGB', const <int>[0]),
        ('gAMA', _uint32(45455)),
        ('PLTE', const <int>[255, 0, 0]),
        ('tRNS', const <int>[128]),
        ('vpAg', const <int>[1, 2, 3]),
      ]) {
        source = _insertChunkBefore(
          source,
          beforeType: 'IDAT',
          type: type,
          payload: payload,
        );
      }

      expect(() => validatePlacementScreenSamplePng(source), returnsNormally);
      expect(() => validateRenderBundleSnapshotPng(source), returnsNormally);
    });

    test('inflates a valid image above the gallery decoded ceiling', () {
      final source = _png(
        width: 1024,
        height: 1024,
        bitDepth: 8,
        colorType: 6,
      );
      const decodedBytes = (1024 * 4 + 1) * 1024;

      expect(decodedBytes, greaterThan(renderBundleSnapshotMaxDecodedBytes));
      expect(decodedBytes, lessThan(placementScreenSampleMaxDecodedBytes));
      expect(source.length, lessThan(placementScreenSampleMaxBytes));
      final validated = validatePlacementScreenSamplePng(source);
      expect(validated.width, 1024);
      expect(validated.height, 1024);
      expect(
        () => validateRenderBundleSnapshotPng(source),
        throwsFormatException,
      );
    });

    test('accepts decoded scanline work exactly at the sample ceiling', () {
      final boundary = _png(
        width: 4095,
        height: 4096,
        bitDepth: 8,
        colorType: 0,
      );

      expect((4095 + 1) * 4096, placementScreenSampleMaxDecodedBytes);
      final validated = validatePlacementScreenSamplePng(boundary);
      expect(validated.width, 4095);
      expect(validated.height, 4096);
    });

    test('rejects a compressed PNG above the sample decoded ceiling', () {
      final bomb = _png(
        width: 4096,
        height: 4096,
        bitDepth: 8,
        colorType: 0,
      );

      expect(bomb.length, lessThan(placementScreenSampleMaxBytes));
      expect(
        (4096 + 1) * 4096,
        greaterThan(placementScreenSampleMaxDecodedBytes),
      );
      expect(
        () => validatePlacementScreenSamplePng(bomb),
        throwsFormatException,
      );
    });

    test('accepts exact encoded and dimension limits and rejects overruns', () {
      final source = _flutterScreenSample();
      final encodedBoundary = _insertChunkBefore(
        source,
        beforeType: 'IDAT',
        type: 'vpAg',
        payload: Uint8List(placementScreenSampleMaxBytes - source.length - 12),
      );
      expect(encodedBoundary.length, placementScreenSampleMaxBytes);
      expect(
        validatePlacementScreenSamplePng(encodedBoundary).byteLength,
        placementScreenSampleMaxBytes,
      );
      expect(
        () => validatePlacementScreenSamplePng(
          Uint8List.fromList(<int>[...encodedBoundary, 0]),
        ),
        throwsFormatException,
      );

      for (final (width, height) in <(int, int)>[(4096, 1), (1, 4096)]) {
        expect(
          () => validatePlacementScreenSamplePng(
            _png(width: width, height: height, bitDepth: 8, colorType: 0),
          ),
          returnsNormally,
        );
      }
      for (final (width, height) in <(int, int)>[(4097, 1), (1, 4097)]) {
        expect(
          () => validatePlacementScreenSamplePng(
            _png(width: width, height: height, bitDepth: 8, colorType: 0),
          ),
          throwsFormatException,
        );
      }
    });

    test('rejects chunk source overruns, CRC errors and trailing PNG data', () {
      final source = _flutterScreenSample();
      final chunkOverrun = Uint8List.fromList(source);
      ByteData.sublistView(chunkOverrun).setUint32(33, 0xffffffff);
      final badCrc = Uint8List.fromList(source)..[source.length - 1] ^= 1;
      final trailingData = Uint8List.fromList(<int>[...source, 0]);

      for (final malformed in <Uint8List>[
        chunkOverrun,
        badCrc,
        trailingData,
        Uint8List.fromList(source.sublist(0, source.length - 1)),
      ]) {
        expect(
          () => validatePlacementScreenSamplePng(malformed),
          throwsFormatException,
        );
      }
    });

    test('rejects exact scanline overruns and malformed DEFLATE envelopes', () {
      final source = _png(width: 1, height: 1, bitDepth: 8, colorType: 6);
      const scanline = <int>[0, 0, 0, 0, 0];
      final fixed = _fixedZlib(scanline);
      final rawEnd = fixed.length - 4;
      final trailingRawByte = Uint8List.fromList(<int>[
        ...fixed.sublist(0, rawEnd),
        0,
        ...fixed.sublist(rawEnd),
      ]);
      final incompleteBlock = Uint8List.fromList(<int>[
        ...fixed.sublist(0, rawEnd - 1),
        ...fixed.sublist(rawEnd),
      ]);
      final badAdler = Uint8List.fromList(fixed)..[fixed.length - 1] ^= 1;

      for (final malformed in <List<int>>[
        const <int>[1, 2, 3],
        const ZLibEncoder().encodeBytes(Uint8List(64 * 1024)),
        const ZLibEncoder().encodeBytes(const <int>[0, 0, 0, 0]),
        const ZLibEncoder().encodeBytes(const <int>[5, 0, 0, 0, 0]),
        trailingRawByte,
        incompleteBlock,
        badAdler,
        _emptyDistanceDynamicZlib(scanline, useLengthCode: true),
      ]) {
        expect(
          () =>
              validatePlacementScreenSamplePng(_replaceIdat(source, malformed)),
          throwsFormatException,
        );
      }
      for (final valid in <List<int>>[
        fixed,
        _storedZlib(scanline),
        _emptyDistanceDynamicZlib(scanline, useLengthCode: false),
      ]) {
        expect(
          () => validatePlacementScreenSamplePng(_replaceIdat(source, valid)),
          returnsNormally,
        );
      }
    });
  });
}

Uint8List _flutterScreenSample() =>
    File('test/fixtures/placements/flutter_screen_sample.png')
        .readAsBytesSync();

Uint8List _png({
  required int width,
  required int height,
  required int bitDepth,
  required int colorType,
  int interlace = 0,
}) {
  final channels = switch (colorType) {
    0 || 3 => 1,
    2 => 3,
    4 => 2,
    6 => 4,
    _ => throw ArgumentError.value(colorType, 'colorType'),
  };
  final rowBytes = (width * bitDepth * channels + 7) ~/ 8;
  final scanlines = Uint8List((rowBytes + 1) * height);
  final ihdr = BytesBuilder(copy: false)
    ..add(_uint32(width))
    ..add(_uint32(height))
    ..add(<int>[bitDepth, colorType, 0, 0, interlace]);
  final compressed = const ZLibEncoder().encodeBytes(scanlines);

  return Uint8List.fromList(<int>[
    137,
    80,
    78,
    71,
    13,
    10,
    26,
    10,
    ..._chunk(const <int>[73, 72, 68, 82], ihdr.takeBytes()),
    ..._chunk(const <int>[73, 68, 65, 84], compressed),
    ..._chunk(const <int>[73, 69, 78, 68], const <int>[]),
  ]);
}

Uint8List _chunk(List<int> type, List<int> payload) {
  final crcInput = Uint8List.fromList(<int>[...type, ...payload]);
  return Uint8List.fromList(<int>[
    ..._uint32(payload.length),
    ...type,
    ...payload,
    ..._uint32(_crc32(crcInput)),
  ]);
}

Uint8List _insertChunkBefore(
  Uint8List source, {
  required String beforeType,
  required String type,
  required List<int> payload,
}) {
  final input = ByteData.sublistView(source);
  var offset = 8;
  while (offset < source.length) {
    final length = input.getUint32(offset);
    final typeOffset = offset + 4;
    if (ascii.decode(source.sublist(typeOffset, typeOffset + 4)) ==
        beforeType) {
      return Uint8List.fromList(<int>[
        ...source.sublist(0, offset),
        ..._chunk(ascii.encode(type), payload),
        ...source.sublist(offset),
      ]);
    }
    offset += length + 12;
  }
  throw StateError('PNG fixture is missing the insertion chunk.');
}

Uint8List _replaceIdat(Uint8List source, List<int> replacement) {
  final input = ByteData.sublistView(source);
  var offset = 8;
  while (offset < source.length) {
    final length = input.getUint32(offset);
    final typeOffset = offset + 4;
    final payloadOffset = typeOffset + 4;
    final end = payloadOffset + length + 4;
    final isIdat = source[typeOffset] == 73 &&
        source[typeOffset + 1] == 68 &&
        source[typeOffset + 2] == 65 &&
        source[typeOffset + 3] == 84;
    if (isIdat) {
      return Uint8List.fromList(<int>[
        ...source.sublist(0, offset),
        ..._chunk(const <int>[73, 68, 65, 84], replacement),
        ...source.sublist(end),
      ]);
    }
    offset = end;
  }
  throw StateError('PNG fixture has no IDAT.');
}

Uint8List _idat(Uint8List source) {
  final input = ByteData.sublistView(source);
  final result = BytesBuilder(copy: false);
  var offset = 8;
  while (offset < source.length) {
    final length = input.getUint32(offset);
    final typeOffset = offset + 4;
    final payloadOffset = typeOffset + 4;
    final end = payloadOffset + length + 4;
    if (source[typeOffset] == 73 &&
        source[typeOffset + 1] == 68 &&
        source[typeOffset + 2] == 65 &&
        source[typeOffset + 3] == 84) {
      result.add(source.sublist(payloadOffset, payloadOffset + length));
    }
    offset = end;
  }
  return result.takeBytes();
}

int _firstDeflateBlockType(Uint8List zlib) => (zlib[2] >> 1) & 3;

Uint8List _storedZlib(List<int> scanline) {
  if (scanline.length > 0xffff) throw ArgumentError.value(scanline.length);
  final length = scanline.length;
  return Uint8List.fromList(<int>[
    0x78,
    0x01,
    0x01,
    length & 0xff,
    length >> 8,
    (~length) & 0xff,
    ((~length) >> 8) & 0xff,
    ...scanline,
    ..._uint32(_adler32(scanline)),
  ]);
}

Uint8List _fixedZlib(List<int> scanline) {
  final writer = _DeflateFixtureWriter()
    ..writeBits(1, 1)
    ..writeBits(1, 2);
  for (final byte in scanline) {
    _writeFixedSymbol(writer, byte);
  }
  _writeFixedSymbol(writer, 256);
  return Uint8List.fromList(<int>[
    0x78,
    0x01,
    ...writer.takeBytes(),
    ..._uint32(_adler32(scanline)),
  ]);
}

Uint8List _malformedDynamicZlib({
  required List<int> codeLengthCodeLengths,
  required List<int> scanline,
}) {
  if (codeLengthCodeLengths.length != 4) {
    throw ArgumentError.value(codeLengthCodeLengths);
  }
  final writer = _DeflateFixtureWriter()
    ..writeBits(1, 1)
    ..writeBits(2, 2)
    ..writeBits(0, 5)
    ..writeBits(0, 5)
    ..writeBits(0, 4);
  for (final length in codeLengthCodeLengths) {
    writer.writeBits(length, 3);
  }
  return _rawZlib(writer.takeBytes(), scanline);
}

Uint8List _emptyDistanceDynamicZlib(
  List<int> scanline, {
  required bool useLengthCode,
}) {
  final writer = _DeflateFixtureWriter()
    ..writeBits(1, 1)
    ..writeBits(2, 2)
    ..writeBits(useLengthCode ? 1 : 0, 5)
    ..writeBits(0, 5)
    ..writeBits(14, 4);

  if (useLengthCode) {
    // Code-length symbols 0, 1, 2, and 18 each use two bits.
    for (final length in const <int>[
      0,
      0,
      2,
      2,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      2,
      0,
      2,
    ]) {
      writer.writeBits(length, 3);
    }
    writer
      ..writeHuffmanCode(1, 2)
      ..writeHuffmanCode(3, 2)
      ..writeBits(127, 7)
      ..writeHuffmanCode(3, 2)
      ..writeBits(106, 7)
      ..writeHuffmanCode(2, 2)
      ..writeHuffmanCode(2, 2)
      ..writeHuffmanCode(0, 2)
      ..writeHuffmanCode(0, 1)
      ..writeHuffmanCode(0, 1)
      ..writeHuffmanCode(3, 2);
  } else {
    // Code-length symbol 0 uses one bit; symbols 1 and 18 use two bits.
    for (final length in const <int>[
      0,
      0,
      2,
      1,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      2,
    ]) {
      writer.writeBits(length, 3);
    }
    writer
      ..writeHuffmanCode(2, 2)
      ..writeHuffmanCode(3, 2)
      ..writeBits(127, 7)
      ..writeHuffmanCode(3, 2)
      ..writeBits(106, 7)
      ..writeHuffmanCode(2, 2)
      ..writeHuffmanCode(0, 1);
    for (final byte in scanline) {
      if (byte != 0) throw ArgumentError.value(scanline, 'scanline');
      writer.writeHuffmanCode(0, 1);
    }
    writer.writeHuffmanCode(1, 1);
  }

  return _rawZlib(writer.takeBytes(), scanline);
}

Uint8List _rawZlib(Uint8List raw, List<int> decoded) =>
    Uint8List.fromList(<int>[
      0x78,
      0x01,
      ...raw,
      ..._uint32(_adler32(decoded)),
    ]);

void _writeFixedSymbol(_DeflateFixtureWriter writer, int symbol) {
  final (code, length) = switch (symbol) {
    >= 0 && <= 143 => (symbol + 0x30, 8),
    >= 144 && <= 255 => (symbol - 144 + 0x190, 9),
    >= 256 && <= 279 => (symbol - 256, 7),
    >= 280 && <= 287 => (symbol - 280 + 0xc0, 8),
    _ => throw ArgumentError.value(symbol),
  };
  writer.writeHuffmanCode(code, length);
}

final class _DeflateFixtureWriter {
  final _bytes = <int>[];
  var _current = 0;
  var _usedBits = 0;

  void writeBits(int value, int count) {
    for (var bit = 0; bit < count; bit++) {
      _writeBit((value >> bit) & 1);
    }
  }

  void writeHuffmanCode(int code, int length) {
    for (var bit = length - 1; bit >= 0; bit--) {
      _writeBit((code >> bit) & 1);
    }
  }

  void _writeBit(int bit) {
    _current |= bit << _usedBits;
    _usedBits++;
    if (_usedBits == 8) {
      _bytes.add(_current);
      _current = 0;
      _usedBits = 0;
    }
  }

  Uint8List takeBytes() {
    if (_usedBits != 0) _bytes.add(_current);
    return Uint8List.fromList(_bytes);
  }
}

Uint8List _uint32(int value) {
  final result = ByteData(4)..setUint32(0, value);
  return result.buffer.asUint8List();
}

int _adler32(List<int> bytes) {
  var s1 = 1;
  var s2 = 0;
  for (final byte in bytes) {
    s1 = (s1 + byte) % 65521;
    s2 = (s2 + s1) % 65521;
  }
  return (s2 << 16) | s1;
}

int _crc32(Uint8List bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc & 1) == 1 ? 0xedb88320 ^ (crc >>> 1) : crc >>> 1;
    }
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}
