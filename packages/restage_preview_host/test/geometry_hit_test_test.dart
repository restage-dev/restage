import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_preview_host/restage_preview_host.dart';

void main() {
  group('hitTestGeometry', () {
    test('chooses the deepest authored path', () {
      final hit = hitTestGeometry(
        <String, Rect>{
          '["main"]': const Rect.fromLTWH(0, 0, 100, 100),
          '["main","child"]': const Rect.fromLTWH(10, 10, 80, 80),
          '["main","child","child"]': const Rect.fromLTWH(20, 20, 60, 60),
        },
        const Offset(30, 30),
      );

      expect(hit?.compactPath, <Object>['main', 'child', 'child']);
      expect(hit?.rect, const Rect.fromLTWH(20, 20, 60, 60));
    });

    test('treats list indices as sibling order, not authored depth', () {
      final hit = hitTestGeometry(
        <String, Rect>{
          '["main","child"]': const Rect.fromLTWH(0, 0, 20, 20),
          '["main","children",0]': const Rect.fromLTWH(0, 0, 20, 20),
          '["main","children",2]': const Rect.fromLTWH(0, 0, 20, 20),
        },
        const Offset(10, 10),
      );

      expect(hit?.compactPath, <Object>['main', 'children', 2]);
    });

    test('uses the last sibling index even below that sibling', () {
      final hit = hitTestGeometry(
        <String, Rect>{
          '["main","children",0,"child"]': const Rect.fromLTWH(0, 0, 20, 20),
          '["main","children",1,"child"]': const Rect.fromLTWH(0, 0, 20, 20),
        },
        const Offset(10, 10),
      );

      expect(
        hit?.compactPath,
        <Object>['main', 'children', 1, 'child'],
      );
    });

    test('uses smallest area after depth and sibling ties', () {
      final hit = hitTestGeometry(
        <String, Rect>{
          '["main","leading"]': const Rect.fromLTWH(0, 0, 40, 40),
          '["main","trailing"]': const Rect.fromLTWH(5, 5, 10, 10),
        },
        const Offset(8, 8),
      );

      expect(hit?.compactPath, <Object>['main', 'trailing']);
    });

    test('ignores malformed keys and returns null outside all rects', () {
      expect(
        hitTestGeometry(
          <String, Rect>{
            'not-json': const Rect.fromLTWH(0, 0, 100, 100),
            '["main"]': const Rect.fromLTWH(10, 10, 10, 10),
          },
          const Offset(1, 1),
        ),
        isNull,
      );
    });
  });

  group('orderedGeometryHits', () {
    test('orders by authored depth before index-heavy shallower paths', () {
      final hits = orderedGeometryHits(
        <String, Rect>{
          '["main","children",0,"children",0,"children",0,"children",0]':
              const Rect.fromLTWH(0, 0, 20, 20),
          '["main","children",1,"child","child","child","child"]':
              const Rect.fromLTWH(0, 0, 20, 20),
        },
        const Offset(10, 10),
      );

      expect(hits, hasLength(2));
      expect(
        hits.first.compactPath,
        <Object>['main', 'children', 1, 'child', 'child', 'child', 'child'],
      );
    });

    test('orders later siblings, smaller areas, then preserves map order', () {
      final hits = orderedGeometryHits(
        <String, Rect>{
          '["main","children",0]': const Rect.fromLTWH(0, 0, 20, 20),
          '["main","children",1]': const Rect.fromLTWH(0, 0, 20, 20),
          '["main","children",1,"leading"]': const Rect.fromLTWH(0, 0, 10, 10),
          '["main","children",1,"trailing"]': const Rect.fromLTWH(0, 0, 10, 10),
        },
        const Offset(5, 5),
      );

      expect(
        hits.map((hit) => hit.compactPath).toList(),
        <List<Object>>[
          <Object>['main', 'children', 1, 'leading'],
          <Object>['main', 'children', 1, 'trailing'],
          <Object>['main', 'children', 1],
          <Object>['main', 'children', 0],
        ],
      );
    });
  });
}
