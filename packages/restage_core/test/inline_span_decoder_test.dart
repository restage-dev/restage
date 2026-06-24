import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';
import 'package:restage_shared/restage_shared.dart' show kMaxInlineSpanDepth;
import 'package:rfw/rfw.dart';

void main() {
  group('RestageDecoders.inlineSpan', () {
    test('decodes a flat two-child styled span tree', () {
      final source = _MapDataSource({
        'span': {
          'children': [
            {
              'text': r'$',
              'style': {
                'color': 0xFF112233,
                'fontSize': 13.0,
                'fontWeight': 'w600',
              },
            },
            {
              'text': '99',
              'style': {
                'color': 0xFF445566,
                'fontSize': 32.0,
                'fontWeight': 'w800',
              },
            },
          ],
        },
      });

      final span = RestageDecoders.inlineSpan(source, const ['span']);

      expect(span, isA<TextSpan>());
      final root = span! as TextSpan;
      expect(root.text, isNull);
      expect(root.children, hasLength(2));

      final prefix = root.children![0] as TextSpan;
      expect(prefix.text, r'$');
      expect(prefix.style!.color, const Color(0xFF112233));
      expect(prefix.style!.fontSize, 13.0);
      expect(prefix.style!.fontWeight, FontWeight.w600);

      final amount = root.children![1] as TextSpan;
      expect(amount.text, '99');
      expect(amount.style!.color, const Color(0xFF445566));
      expect(amount.style!.fontSize, 32.0);
      expect(amount.style!.fontWeight, FontWeight.w800);
    });

    test('decodes nested span children recursively', () {
      final source = _MapDataSource({
        'span': {
          'text': 'root',
          'children': [
            {
              'text': 'outer',
              'children': [
                {'text': 'inner'},
              ],
            },
          ],
        },
      });

      final root =
          RestageDecoders.inlineSpan(source, const ['span'])! as TextSpan;
      final outer = root.children!.single as TextSpan;
      final inner = outer.children!.single as TextSpan;

      expect(root.text, 'root');
      expect(outer.text, 'outer');
      expect(inner.text, 'inner');
    });

    test('terminates trees deeper than the depth cap', () {
      final source = _MapDataSource({
        'span': _deepSpan(kMaxInlineSpanDepth + 2),
      });

      var current =
          RestageDecoders.inlineSpan(source, const ['span'])! as TextSpan;
      for (var depth = 0; depth <= kMaxInlineSpanDepth; depth += 1) {
        expect(current.children, hasLength(1));
        current = current.children!.single as TextSpan;
      }

      expect(current.text, isNull);
      expect(current.children, isNull);
    });

    test('sanitizes non-finite style scalars', () {
      final source = _MapDataSource({
        'span': {
          'text': 'price',
          'style': {
            'color': 0xFFABCDEF,
            'fontSize': double.nan,
            'letterSpacing': double.infinity,
            'height': double.negativeInfinity,
          },
        },
      });

      final span =
          RestageDecoders.inlineSpan(source, const ['span'])! as TextSpan;

      expect(span.style!.color, const Color(0xFFABCDEF));
      expect(span.style!.fontSize, isNull);
      expect(span.style!.letterSpacing, isNull);
      expect(span.style!.height, isNull);
    });

    test('returns null when the requested slot is absent', () {
      final source = _MapDataSource({
        'other': {'text': 'present elsewhere'},
      });

      expect(RestageDecoders.inlineSpan(source, const ['span']), isNull);
    });

    test('decodes malformed child elements as empty TextSpans', () {
      final source = _MapDataSource({
        'span': {
          'children': [
            {'text': 'ok'},
            'not a map',
          ],
        },
      });

      final span =
          RestageDecoders.inlineSpan(source, const ['span'])! as TextSpan;

      expect(span.children, hasLength(2));
      expect((span.children![0] as TextSpan).text, 'ok');

      final malformed = span.children![1] as TextSpan;
      expect(malformed.text, isNull);
      expect(malformed.children, isNull);
      expect(malformed.style, isNull);
    });
  });
}

Map<String, Object?> _deepSpan(int remaining) {
  if (remaining == 0) {
    return {'text': 'leaf'};
  }
  return {
    'text': 'depth-$remaining',
    'children': [_deepSpan(remaining - 1)],
  };
}

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
