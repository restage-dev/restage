import 'dart:convert';

import 'package:build/build.dart';
import 'package:restage_codegen/src/a2ui/a2ui_example_loader.dart';
import 'package:test/test.dart';

const _anchor = A2uiExampleSourceAnchor(
  sourceClass: 'ProductCard',
  widgetName: 'ProductCard',
  exampleName: 'Default',
  asset: 'lib/a2ui_examples/product_card/default.json',
);

final class _MissingAssetBuildStep implements BuildStep {
  _MissingAssetBuildStep({required this.disappearsAfterCanRead});

  final bool disappearsAfterCanRead;

  @override
  AssetId get inputId => AssetId('customer_app', r'lib/$lib$');

  @override
  Future<bool> canRead(AssetId id) async => disappearsAfterCanRead;

  @override
  Future<String> readAsString(
    AssetId id, {
    Encoding encoding = utf8,
  }) =>
      throw AssetNotFoundException(id);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('A2UI example asset normalization', () {
    test('accepts an already-normalized same-package lib asset', () {
      expect(
        a2uiExampleAssetId('customer_app', _anchor),
        AssetId(
          'customer_app',
          'lib/a2ui_examples/product_card/default.json',
        ),
      );
    });

    for (final invalid in const <String>[
      '/tmp/default.json',
      r'C:\tmp\default.json',
      r'lib\a2ui_examples\default.json',
      '../lib/default.json',
      'lib/../default.json',
      'lib/./default.json',
      'lib//default.json',
      'assets/default.json',
      'package:other/default.json',
      'https://example.com/default.json',
      'lib/a2ui_examples/',
    ]) {
      test('rejects non-canonical asset "$invalid" with context', () {
        final anchor = _anchor.copyWith(asset: invalid);

        expect(
          () => a2uiExampleAssetId('customer_app', anchor),
          throwsA(
            isA<A2uiExampleException>()
                .having(
                  (error) => error.toString(),
                  'diagnostic',
                  contains('ProductCard'),
                )
                .having(
                  (error) => error.toString(),
                  'diagnostic',
                  contains('Default'),
                )
                .having(
                  (error) => error.toString(),
                  'diagnostic',
                  contains(invalid),
                ),
          ),
        );
      });
    }
  });

  group('A2UI example JSON decoding', () {
    test('preserves ordered JSON number kinds in a deeply immutable array', () {
      final components = decodeA2uiExampleComponents(
        '''
        [
          {
            "id": "root",
            "component": "ProductCard",
            "count": 2,
            "price": 2.0,
            "nested": {"flags": [true, null, "ok"]}
          }
        ]''',
        _anchor,
      );

      expect(components.single.keys, [
        'id',
        'component',
        'count',
        'price',
        'nested',
      ]);
      expect(components.single['count'], isA<int>());
      expect(components.single['price'], isA<double>());
      expect(
        () => components.add(const {'id': 'other', 'component': 'Other'}),
        throwsUnsupportedError,
      );
      expect(
        () => (components.single['nested']! as Map<String, Object?>)['x'] = 1,
        throwsUnsupportedError,
      );
      expect(
        () => ((components.single['nested']! as Map<String, Object?>)['flags']!
                as List<Object?>)
            .add(false),
        throwsUnsupportedError,
      );
    });

    final failures = <String, String>{
      'invalid JSON': '[{',
      'non-array root': '{"components": []}',
      'non-object entry': '["ProductCard"]',
      'missing id': '[{"component":"ProductCard"}]',
      'non-string id': '[{"id":1,"component":"ProductCard"}]',
      'missing component': '[{"id":"root"}]',
      'non-string component': '[{"id":"root","component":1}]',
      'internal constructor shape':
          '[{"id":"root","type":"ProductCard","properties":{}}]',
      'recursive non-finite number': '[{"id":"root","component":"ProductCard",'
          '"nested":{"items":[1e400]}}]',
    };

    for (final entry in failures.entries) {
      test('rejects ${entry.key} with full source context', () {
        expect(
          () => decodeA2uiExampleComponents(entry.value, _anchor),
          throwsA(
            isA<A2uiExampleException>()
                .having(
                  (error) => error.toString(),
                  'diagnostic',
                  contains('ProductCard'),
                )
                .having(
                  (error) => error.toString(),
                  'diagnostic',
                  contains('Default'),
                )
                .having(
                  (error) => error.toString(),
                  'diagnostic',
                  contains(_anchor.asset),
                ),
          ),
        );
      });
    }
  });

  test('missing and read-time deleted assets share one stable diagnostic',
      () async {
    const message =
        'asset does not exist or was deleted before it could be read';

    await expectLater(
      loadA2uiExample(
        _MissingAssetBuildStep(disappearsAfterCanRead: false),
        _anchor,
      ),
      throwsA(
        isA<A2uiExampleException>().having(
          (error) => error.toString(),
          'diagnostic',
          contains(message),
        ),
      ),
    );
    await expectLater(
      loadA2uiExample(
        _MissingAssetBuildStep(disappearsAfterCanRead: true),
        _anchor,
      ),
      throwsA(
        isA<A2uiExampleException>().having(
          (error) => error.toString(),
          'diagnostic',
          contains(message),
        ),
      ),
    );
  });
}
