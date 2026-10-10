import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';

const _unitsPerLogicalPixel = 1024;
const _maximumLogicalPixels = 65536;
const int _maximumLogicalUnits = _maximumLogicalPixels * _unitsPerLogicalPixel;

/// A positive logical size stored in 1024 integer units per logical pixel.
@immutable
final class PlacementLogicalSizeV1 {
  /// Creates a size with each dimension in 1..67,108,864 units.
  PlacementLogicalSizeV1({
    required this.widthUnits,
    required this.heightUnits,
  }) {
    _requireUnits(widthUnits, 'widthUnits', size: true);
    _requireUnits(heightUnits, 'heightUnits', size: true);
  }

  /// Quantizes finite positive dimensions, rounding ties away from zero.
  factory PlacementLogicalSizeV1.fromLogical({
    required double width,
    required double height,
  }) =>
      PlacementLogicalSizeV1(
        widthUnits: _quantizeLogical(width, 'width', size: true),
        heightUnits: _quantizeLogical(height, 'height', size: true),
      );

  /// Decodes the closed integer-only size object.
  factory PlacementLogicalSizeV1.fromJson(Object? value) {
    final reader = _geometryReader(value, _keys, 'placementLogicalSize');
    return PlacementLogicalSizeV1(
      widthUnits: _readUnits(reader, 'widthUnits', size: true),
      heightUnits: _readUnits(reader, 'heightUnits', size: true),
    );
  }

  /// Decodes only the exact canonical byte representation.
  factory PlacementLogicalSizeV1.fromCanonicalBytes(List<int> bytes) =>
      PlacementLogicalSizeV1.fromJson(CanonicalJsonCodec.decode(bytes));

  static const _keys = {'widthUnits', 'heightUnits'};

  /// Width in integer logical units.
  final int widthUnits;

  /// Height in integer logical units.
  final int heightUnits;

  /// Quantized width in logical pixels.
  double get width => widthUnits / _unitsPerLogicalPixel;

  /// Quantized height in logical pixels.
  double get height => heightUnits / _unitsPerLogicalPixel;

  /// Encodes only the integer size fields.
  Map<String, Object?> toJson() => {
        'widthUnits': widthUnits,
        'heightUnits': heightUnits,
      };

  /// Exact canonical JSON bytes, returned as a fresh list.
  Uint8List get canonicalBytes => CanonicalJsonCodec.encode(toJson());

  @override
  bool operator ==(Object other) =>
      other is PlacementLogicalSizeV1 &&
      widthUnits == other.widthUnits &&
      heightUnits == other.heightUnits;

  @override
  int get hashCode => Object.hash(widthUnits, heightUnits);
}

/// A same-frame logical rectangle stored in 1024 units per logical pixel.
@immutable
final class PlacementLogicalRectV1 {
  /// Creates a bounded position and positive size in integer logical units.
  PlacementLogicalRectV1({
    required this.xUnits,
    required this.yUnits,
    required this.widthUnits,
    required this.heightUnits,
  }) {
    _requireUnits(xUnits, 'xUnits', size: false);
    _requireUnits(yUnits, 'yUnits', size: false);
    _requireUnits(widthUnits, 'widthUnits', size: true);
    _requireUnits(heightUnits, 'heightUnits', size: true);
  }

  /// Quantizes finite bounded geometry, rounding ties away from zero.
  factory PlacementLogicalRectV1.fromLogical({
    required double x,
    required double y,
    required double width,
    required double height,
  }) =>
      PlacementLogicalRectV1(
        xUnits: _quantizeLogical(x, 'x', size: false),
        yUnits: _quantizeLogical(y, 'y', size: false),
        widthUnits: _quantizeLogical(width, 'width', size: true),
        heightUnits: _quantizeLogical(height, 'height', size: true),
      );

  /// Decodes the closed integer-only rectangle object.
  factory PlacementLogicalRectV1.fromJson(Object? value) {
    final reader = _geometryReader(value, _keys, 'placementLogicalRect');
    return PlacementLogicalRectV1(
      xUnits: _readUnits(reader, 'xUnits', size: false),
      yUnits: _readUnits(reader, 'yUnits', size: false),
      widthUnits: _readUnits(reader, 'widthUnits', size: true),
      heightUnits: _readUnits(reader, 'heightUnits', size: true),
    );
  }

  /// Decodes only the exact canonical byte representation.
  factory PlacementLogicalRectV1.fromCanonicalBytes(List<int> bytes) =>
      PlacementLogicalRectV1.fromJson(CanonicalJsonCodec.decode(bytes));

  static const _keys = {'xUnits', 'yUnits', 'widthUnits', 'heightUnits'};

  /// Horizontal position in integer logical units; off-screen values are valid.
  final int xUnits;

  /// Vertical position in integer logical units; off-screen values are valid.
  final int yUnits;

  /// Width in integer logical units.
  final int widthUnits;

  /// Height in integer logical units.
  final int heightUnits;

  /// Quantized horizontal position in logical pixels.
  double get x => xUnits / _unitsPerLogicalPixel;

  /// Quantized vertical position in logical pixels.
  double get y => yUnits / _unitsPerLogicalPixel;

  /// Quantized width in logical pixels.
  double get width => widthUnits / _unitsPerLogicalPixel;

  /// Quantized height in logical pixels.
  double get height => heightUnits / _unitsPerLogicalPixel;

  /// Encodes only the integer rectangle fields.
  Map<String, Object?> toJson() => {
        'xUnits': xUnits,
        'yUnits': yUnits,
        'widthUnits': widthUnits,
        'heightUnits': heightUnits,
      };

  /// Exact canonical JSON bytes, returned as a fresh list.
  Uint8List get canonicalBytes => CanonicalJsonCodec.encode(toJson());

  @override
  bool operator ==(Object other) =>
      other is PlacementLogicalRectV1 &&
      xUnits == other.xUnits &&
      yUnits == other.yUnits &&
      widthUnits == other.widthUnits &&
      heightUnits == other.heightUnits;

  @override
  int get hashCode => Object.hash(xUnits, yUnits, widthUnits, heightUnits);
}

/// A reduced positive raster-scale rational with a value in [1/8, 4].
@immutable
final class PlacementRasterScaleV1 {
  /// Creates a reduced rational with numerator <=4096 and denominator <=1024.
  PlacementRasterScaleV1({
    required this.numerator,
    required this.denominator,
  }) {
    if (!_validRasterScale(numerator, denominator)) {
      throw ArgumentError(
        'Raster scale must be a reduced positive rational in [1/8, 4] '
        'with numerator <=4096 and denominator <=1024.',
      );
    }
  }

  /// Quantizes a requested scale once to the nearest 1/1024, then reduces it.
  ///
  /// Pass the returned [value] to the raster encoder as its pixel ratio.
  factory PlacementRasterScaleV1.fromRequestedScale(double requestedScale) {
    if (!requestedScale.isFinite ||
        requestedScale < 1 / 8 ||
        requestedScale > 4) {
      throw ArgumentError.value(
        requestedScale,
        'requestedScale',
        'Must be finite and in [1/8, 4].',
      );
    }
    final numerator = (requestedScale * _unitsPerLogicalPixel).round();
    final divisor = numerator.gcd(_unitsPerLogicalPixel);
    return PlacementRasterScaleV1(
      numerator: numerator ~/ divisor,
      denominator: _unitsPerLogicalPixel ~/ divisor,
    );
  }

  /// Decodes the closed integer-only reduced-rational object.
  factory PlacementRasterScaleV1.fromJson(Object? value) {
    final reader = _geometryReader(value, _keys, 'placementRasterScale');
    final numerator = reader.integer('numerator');
    final denominator = reader.integer('denominator');
    if (!_validRasterScale(numerator, denominator)) {
      throw const CanonicalFormatException(
        'Raster scale is outside the bounded reduced-rational range.',
      );
    }
    return PlacementRasterScaleV1(
      numerator: numerator,
      denominator: denominator,
    );
  }

  /// Decodes only the exact canonical byte representation.
  factory PlacementRasterScaleV1.fromCanonicalBytes(List<int> bytes) =>
      PlacementRasterScaleV1.fromJson(CanonicalJsonCodec.decode(bytes));

  static const _keys = {'numerator', 'denominator'};

  /// Reduced numerator in 1..4096.
  final int numerator;

  /// Reduced denominator in 1..1024.
  final int denominator;

  /// Actual quantized pixel ratio to use when encoding the raster.
  double get value => numerator / denominator;

  /// Encodes only the integer rational fields.
  Map<String, Object?> toJson() => {
        'numerator': numerator,
        'denominator': denominator,
      };

  /// Exact canonical JSON bytes, returned as a fresh list.
  Uint8List get canonicalBytes => CanonicalJsonCodec.encode(toJson());

  @override
  bool operator ==(Object other) =>
      other is PlacementRasterScaleV1 &&
      numerator == other.numerator &&
      denominator == other.denominator;

  @override
  int get hashCode => Object.hash(numerator, denominator);
}

/// Whether a raster extent is within one pixel of the logical extent's ceil.
///
/// This tolerance accounts for logical viewport quantization. Nonpositive or
/// unbounded inputs are refused before multiplication or subtraction.
bool placementRasterExtentIsConsistent({
  required int pixels,
  required int logicalUnits,
  required PlacementRasterScaleV1 scale,
}) {
  if (pixels <= 0 ||
      pixels > kMaximumPortableJsonInteger ||
      logicalUnits <= 0 ||
      logicalUnits > _maximumLogicalUnits) {
    return false;
  }
  final divisor = _unitsPerLogicalPixel * scale.denominator;
  // The largest dividend is 2^26 * 4096 + 1024^2 - 1, well below 2^53.
  final expectedPixels =
      (logicalUnits * scale.numerator + divisor - 1) ~/ divisor;
  return (pixels - expectedPixels).abs() <= 1;
}

int _quantizeLogical(double value, String name, {required bool size}) {
  if (!value.isFinite ||
      value > _maximumLogicalPixels ||
      (size ? value <= 0 : value < -_maximumLogicalPixels)) {
    throw ArgumentError.value(
      value,
      name,
      size
          ? 'Must be finite and in (0, 65536] logical pixels.'
          : 'Must be finite and in [-65536, 65536] logical pixels.',
    );
  }
  final units = (value * _unitsPerLogicalPixel).round();
  _requireUnits(units, name, size: size);
  return units;
}

void _requireUnits(int value, String name, {required bool size}) {
  if (!_validUnits(value, size: size)) {
    throw ArgumentError.value(
      value,
      name,
      size
          ? 'Must be in 1..67,108,864 logical units.'
          : 'Must be in -67,108,864..67,108,864 logical units.',
    );
  }
}

bool _validUnits(int value, {required bool size}) =>
    value >= (size ? 1 : -_maximumLogicalUnits) &&
    value <= _maximumLogicalUnits;

int _readUnits(CanonicalObjectReader reader, String key, {required bool size}) {
  final units = reader.integer(key);
  if (!_validUnits(units, size: size)) {
    throw CanonicalFormatException('${reader.path}.$key is out of range.');
  }
  return units;
}

CanonicalObjectReader _geometryReader(
  Object? value,
  Set<String> keys,
  String path,
) =>
    CanonicalObjectReader(
      requireCanonicalObject(value, path),
      allowedKeys: keys,
      requiredKeys: keys,
      path: path,
    );

bool _validRasterScale(int numerator, int denominator) =>
    numerator >= 1 &&
    numerator <= 4096 &&
    denominator >= 1 &&
    denominator <= 1024 &&
    numerator * 8 >= denominator &&
    numerator <= denominator * 4 &&
    numerator.gcd(denominator) == 1;
