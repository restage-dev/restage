// Golden fixtures for the pub `rfw` ArgumentDecoders the catalog leans on.
//
// The generated registration calls `ArgumentDecoders.color`, `.edgeInsets`,
// `.alignment`, `.gradient`, `.boxShadow`, and `.border` at hundreds of sites.
// Those depend on the decoder *semantics* (which keys are read, the defaults,
// the directional-vs-absolute mapping), not just the API shape — a behavioral
// change inside a `1.x` minor would compile clean and change rendered output
// across every catalog widget. These fixtures pin the current semantics so such
// a drift fails loudly here instead of silently in a customer's render.
//
// Inputs mirror the wire shape the codec/runtime feeds these decoders (the same
// shape the catalog emits). Keep these aligned with `rfw`'s documented formats.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rfw/rfw.dart';

void main() {
  group('ArgumentDecoders.color', () {
    test('reads an ARGB int into a Color', () {
      final source = _MapDataSource({'c': 0xFF112233});
      expect(
          ArgumentDecoders.color(source, const ['c']), const Color(0xFF112233));
    });

    test('returns null when the slot is absent or non-int', () {
      final source = _MapDataSource({'s': 'not-an-int'});
      expect(ArgumentDecoders.color(source, const ['missing']), isNull);
      expect(ArgumentDecoders.color(source, const ['s']), isNull);
    });
  });

  group('ArgumentDecoders.edgeInsets', () {
    test('reads [start, top, end, bottom] into EdgeInsetsDirectional.fromSTEB',
        () {
      final source = _MapDataSource({
        'p': [4.0, 8.0, 12.0, 16.0],
      });
      expect(
        ArgumentDecoders.edgeInsets(source, const ['p']),
        EdgeInsetsDirectional.fromSTEB(4, 8, 12, 16),
      );
    });

    test('expands a single value to all four sides', () {
      final source = _MapDataSource({
        'p': [10.0],
      });
      expect(
        ArgumentDecoders.edgeInsets(source, const ['p']),
        EdgeInsetsDirectional.fromSTEB(10, 10, 10, 10),
      );
    });

    test('returns null for an absent list', () {
      expect(
        ArgumentDecoders.edgeInsets(_MapDataSource(null), const ['p']),
        isNull,
      );
    });
  });

  group('ArgumentDecoders.alignment', () {
    test('reads {x, y} into an absolute Alignment', () {
      final source = _MapDataSource({
        'a': {'x': 1.0, 'y': -1.0},
      });
      expect(
        ArgumentDecoders.alignment(source, const ['a']),
        const Alignment(1, -1),
      );
    });

    test('reads {start, y} into an AlignmentDirectional', () {
      final source = _MapDataSource({
        'a': {'start': -1.0, 'y': 0.0},
      });
      expect(
        ArgumentDecoders.alignment(source, const ['a']),
        const AlignmentDirectional(-1, 0),
      );
    });

    test('returns null when not a map', () {
      final source = _MapDataSource({'a': 'center'});
      expect(ArgumentDecoders.alignment(source, const ['a']), isNull);
    });
  });

  group('ArgumentDecoders.gradient', () {
    test('reads a linear gradient with colors and stops', () {
      final source = _MapDataSource({
        'g': {
          'type': 'linear',
          'colors': [0xFF000000, 0xFFFFFFFF],
          'stops': [0.0, 1.0],
        },
      });
      expect(
        ArgumentDecoders.gradient(source, const ['g']),
        const LinearGradient(
          colors: [Color(0xFF000000), Color(0xFFFFFFFF)],
          stops: [0.0, 1.0],
        ),
      );
    });

    test('reads a radial gradient with a radius', () {
      final source = _MapDataSource({
        'g': {
          'type': 'radial',
          'radius': 0.75,
          'colors': [0xFF010203, 0xFF040506],
        },
      });
      final decoded = ArgumentDecoders.gradient(source, const ['g']);
      expect(decoded, isA<RadialGradient>());
      final radial = decoded! as RadialGradient;
      expect(radial.radius, 0.75);
      expect(
        radial.colors,
        const [Color(0xFF010203), Color(0xFF040506)],
      );
    });

    test('returns null when the type key is absent', () {
      final source = _MapDataSource({
        'g': <String, Object?>{'colors': <Object?>[]},
      });
      expect(ArgumentDecoders.gradient(source, const ['g']), isNull);
    });
  });

  group('ArgumentDecoders.boxShadow', () {
    test('reads color, offset, blurRadius, spreadRadius', () {
      final source = _MapDataSource({
        's': {
          'color': 0xFF112233,
          'offset': {'x': 1.0, 'y': 2.0},
          'blurRadius': 3.0,
          'spreadRadius': 4.0,
        },
      });
      expect(
        ArgumentDecoders.boxShadow(source, const ['s']),
        const BoxShadow(
          color: Color(0xFF112233),
          offset: Offset(1, 2),
          blurRadius: 3,
          spreadRadius: 4,
        ),
      );
    });

    test('defaults to a zero BoxShadow when the slot is not a map', () {
      expect(
        ArgumentDecoders.boxShadow(_MapDataSource(null), const ['s']),
        const BoxShadow(),
      );
    });
  });

  group('ArgumentDecoders.border', () {
    test('reads a single border side onto all four edges (directional)', () {
      final source = _MapDataSource({
        'b': [
          {'color': 0xFF112233, 'width': 2.0},
        ],
      });
      final decoded = ArgumentDecoders.border(source, const ['b']);
      expect(decoded, isA<BorderDirectional>());
      final border = decoded! as BorderDirectional;
      const side = BorderSide(color: Color(0xFF112233), width: 2);
      expect(border.start, side);
      expect(border.top, side);
      expect(border.end, side);
      expect(border.bottom, side);
    });

    test('returns null for an absent border list', () {
      expect(
        ArgumentDecoders.border(_MapDataSource(null), const ['b']),
        isNull,
      );
    });
  });
}

/// Minimal [DataSource] over a plain nested map/list tree, mirroring the wire
/// shape the rfw runtime feeds the argument decoders.
final class _MapDataSource implements DataSource {
  const _MapDataSource(this.root);

  final Object? root;

  @override
  T? v<T extends Object>(List<Object> argsKey) {
    final value = _lookup(argsKey);
    return value is T ? value : null;
  }

  @override
  bool isList(List<Object> argsKey) => _lookup(argsKey) is List<Object?>;

  @override
  int length(List<Object> argsKey) {
    final value = _lookup(argsKey);
    return value is List<Object?> ? value.length : 0;
  }

  @override
  bool isMap(List<Object> argsKey) => _lookup(argsKey) is Map<String, Object?>;

  @override
  Widget child(List<Object> argsKey) => ErrorWidget('missing child');

  @override
  List<Widget> childList(List<Object> argsKey) => const [];

  @override
  Widget builder(List<Object> argsKey, DynamicMap builderArg) =>
      ErrorWidget('missing builder');

  @override
  T? handler<T extends Function>(
    List<Object> argsKey,
    HandlerGenerator<T> generator,
  ) =>
      null;

  @override
  Widget? optionalBuilder(List<Object> argsKey, DynamicMap builderArg) => null;

  @override
  Widget? optionalChild(List<Object> argsKey) => null;

  @override
  VoidCallback? voidHandler(
    List<Object> argsKey, [
    DynamicMap? extraArguments,
  ]) =>
      null;

  Object? _lookup(List<Object> path) {
    Object? current = root;
    for (final segment in path) {
      if (current is Map<String, Object?> && segment is String) {
        current = current[segment];
      } else if (current is List<Object?> && segment is int) {
        if (segment < 0 || segment >= current.length) return null;
        current = current[segment];
      } else {
        return null;
      }
    }
    return current;
  }
}
