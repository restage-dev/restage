import 'package:flutter_test/flutter_test.dart';
import 'package:restage_a2ui/src/a2ui_payload_scan.dart';

void main() {
  group('a2uiReferencedWidgetTypes', () {
    test('collects types from an UpdateComponents wire message', () {
      final types = a2uiReferencedWidgetTypes(const {
        'version': 'v0.9',
        'updateComponents': {
          'surfaceId': 's',
          'components': [
            {
              'id': 'root',
              'component': 'Column',
              'children': ['a', 'b'],
            },
            {'id': 'a', 'component': 'Text', 'text': 'Hi'},
            {'id': 'b', 'component': 'FilledButton'},
          ],
        },
      });
      expect(types, {'Column', 'Text', 'FilledButton'});
    });

    test('collects types from a SurfaceDefinition (components map)', () {
      final types = a2uiReferencedWidgetTypes(const {
        'surfaceId': 's',
        'catalogId': 'restage:catalog/1',
        'components': {
          'root': {'id': 'root', 'component': 'Card'},
          'a': {'id': 'a', 'component': 'Text'},
        },
      });
      expect(types, {'Card', 'Text'});
    });

    test('collects types nested inside component properties', () {
      final types = a2uiReferencedWidgetTypes(const {
        'components': [
          {
            'id': 'root',
            'component': 'Wrapper',
            'child': {'id': 'inner', 'component': 'Badge'},
          },
        ],
      });
      expect(types, {'Wrapper', 'Badge'});
    });

    test('does not collect instance ids or child id references as types', () {
      final types = a2uiReferencedWidgetTypes(const {
        'components': [
          {
            'id': 'root',
            'component': 'Column',
            'children': ['a', 'b', 'c'],
          },
        ],
      });
      // Only the `component` discriminator value — never `id` / child ids.
      expect(types, {'Column'});
    });

    test('does not collect a `component` key inside a property value', () {
      // A real component object always carries both `id` and `component`
      // (genui's Component.fromJson requires both). A `component` key buried in
      // a property bag (no `id`) is arbitrary data, NOT a referenced type —
      // collecting it would falsely reject a valid payload.
      final types = a2uiReferencedWidgetTypes(const {
        'components': [
          {
            'id': 'root',
            'component': 'Box',
            'decoration': {'component': 'not-a-widget-type'},
            'label': {'component': 'also-not-a-type', 'value': 'x'},
          },
        ],
      });
      expect(types, {'Box'});
    });

    test('returns empty for component-less / malformed / non-map input', () {
      expect(a2uiReferencedWidgetTypes(const {'surfaceId': 's'}), isEmpty);
      expect(a2uiReferencedWidgetTypes(null), isEmpty);
      expect(a2uiReferencedWidgetTypes('a string'), isEmpty);
      expect(a2uiReferencedWidgetTypes(const [1, 2, 3]), isEmpty);
      // A non-string `component` value is skipped, never throws.
      expect(
        a2uiReferencedWidgetTypes(const {
          'components': [
            {'id': 'x', 'component': 42},
          ],
        }),
        isEmpty,
      );
    });
  });
}
