import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/widgets.dart';
import 'package:rfw/rfw.dart';

/// Reconstructs the native structured values used by scrollable grids.
abstract final class RestageGridValues {
  /// Decodes either standard grid delegate, preserving native defaults.
  static SliverGridDelegate? gridDelegate(
      DataSource source, List<Object> path) {
    if (!_map(source, path)) return null;
    final kind = source.v<String>([...path, '_s']);
    final mainSpacing = _number(source, [...path, 'mainAxisSpacing']) ?? 0.0;
    final crossSpacing = _number(source, [...path, 'crossAxisSpacing']) ?? 0.0;
    final ratio = _number(source, [...path, 'childAspectRatio']) ?? 1.0;
    final extent = _number(source, [...path, 'mainAxisExtent']);
    if (!(mainSpacing >= 0) ||
        !(crossSpacing >= 0) ||
        !(ratio > 0) ||
        (extent != null && !(extent >= 0))) {
      throw const FormatException('Invalid grid delegate dimensions.');
    }
    switch (kind) {
      case 'SliverGridDelegateWithFixedCrossAxisCount':
        final count = source.v<int>([...path, 'crossAxisCount']);
        if (count == null || count <= 0) {
          throw const FormatException(
              'Grid crossAxisCount must be a positive integer.');
        }
        return SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: count,
          mainAxisSpacing: mainSpacing,
          crossAxisSpacing: crossSpacing,
          childAspectRatio: ratio,
          mainAxisExtent: extent,
        );
      case 'SliverGridDelegateWithMaxCrossAxisExtent':
        final maximum = _number(source, [...path, 'maxCrossAxisExtent']);
        if (maximum == null || !(maximum > 0)) {
          throw const FormatException(
              'Grid maxCrossAxisExtent must be positive.');
        }
        return SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: maximum,
          mainAxisSpacing: mainSpacing,
          crossAxisSpacing: crossSpacing,
          childAspectRatio: ratio,
          mainAxisExtent: extent,
        );
      default:
        throw FormatException('Unknown grid delegate: $kind.');
    }
  }

  /// Decodes standard native physics and a structurally bounded parent chain.
  static ScrollPhysics? physics(DataSource source, List<Object> path) =>
      _physics(source, path, 0);

  static ScrollPhysics? _physics(
      DataSource source, List<Object> path, int depth) {
    if (!_map(source, path)) return null;
    if (depth >= 64) {
      throw const FormatException(
          'ScrollPhysics parent chain exceeds 64 nodes.');
    }
    final kind = source.v<String>([...path, '_s']);
    final parent = _physics(source, [...path, 'parent'], depth + 1);
    return switch (kind) {
      'ScrollPhysics' => ScrollPhysics(parent: parent),
      'RangeMaintainingScrollPhysics' =>
        RangeMaintainingScrollPhysics(parent: parent),
      'BouncingScrollPhysics' => BouncingScrollPhysics(
          parent: parent,
          decelerationRate:
              _deceleration(source, [...path, 'decelerationRate']),
        ),
      'ClampingScrollPhysics' => ClampingScrollPhysics(parent: parent),
      'AlwaysScrollableScrollPhysics' =>
        AlwaysScrollableScrollPhysics(parent: parent),
      'NeverScrollableScrollPhysics' =>
        NeverScrollableScrollPhysics(parent: parent),
      'PageScrollPhysics' => PageScrollPhysics(parent: parent),
      'FixedExtentScrollPhysics' => FixedExtentScrollPhysics(parent: parent),
      _ => throw FormatException('Unknown ScrollPhysics: $kind.'),
    };
  }

  /// Decodes the native pixel or viewport-multiplier cache extent.
  static ScrollCacheExtent? cacheExtent(DataSource source, List<Object> path) {
    if (!_map(source, path)) return null;
    final value = _number(source, [...path, 'value']);
    if (value == null) {
      throw const FormatException(
          'ScrollCacheExtent requires a numeric value.');
    }
    return switch (source.v<String>([...path, '_s'])) {
      'pixels' => ScrollCacheExtent.pixels(value),
      'viewport' => ScrollCacheExtent.viewport(value),
      final kind => throw FormatException('Unknown ScrollCacheExtent: $kind.'),
    };
  }
}

ScrollDecelerationRate _deceleration(DataSource source, List<Object> path) {
  if (!_present(source, path)) return ScrollDecelerationRate.normal;
  return switch (source.v<String>(path)) {
    'normal' => ScrollDecelerationRate.normal,
    'fast' => ScrollDecelerationRate.fast,
    _ => throw const FormatException('Unknown ScrollDecelerationRate.'),
  };
}

double? _number(DataSource source, List<Object> path) {
  final value = source.v<double>(path) ?? source.v<int>(path)?.toDouble();
  if (value == null && _present(source, path)) {
    throw FormatException('Expected a numeric value at $path.');
  }
  return value;
}

bool _map(DataSource source, List<Object> path) {
  if (source.isMap(path)) return true;
  if (_present(source, path)) {
    throw FormatException('Expected a structured value at $path.');
  }
  return false;
}

bool _present(DataSource source, List<Object> path) =>
    source.isMap(path) ||
    source.isList(path) ||
    source.v<int>(path) != null ||
    source.v<double>(path) != null ||
    source.v<bool>(path) != null ||
    source.v<String>(path) != null;
