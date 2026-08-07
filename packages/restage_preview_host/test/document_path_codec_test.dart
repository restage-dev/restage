import 'package:flutter_test/flutter_test.dart';
import 'package:restage_preview_host/restage_preview_host.dart';

void main() {
  group('DocumentPathCodec', () {
    test('round-trips compact authored paths as strict JSON', () {
      const paths = <List<Object>>[
        <Object>['main'],
        <Object>['main', 'child'],
        <Object>['main', 'children', 0],
        <Object>['main', 'children', 3, 'child'],
        <Object>['main', 'args'],
      ];

      for (final path in paths) {
        expect(DocumentPathCodec.decode(DocumentPathCodec.encode(path)), path);
      }
      expect(
        DocumentPathCodec.encode(const <Object>['main', 'children', 0]),
        '["main","children",0]',
      );
    });

    test('rejects malformed JSON and malformed compact path shapes', () {
      const malformed = <String>[
        'not json',
        '"main"',
        '[]',
        '[0]',
        '["main",0]',
        '["main","children",-1]',
        '["main","children",0,1]',
        '["main",true]',
        '["main",1.5]',
        '["main",null]',
        '["main",{}]',
        '["main",[]]',
      ];

      for (final encoded in malformed) {
        expect(
          () => DocumentPathCodec.decode(encoded),
          throwsA(isA<FormatException>()),
          reason: encoded,
        );
      }
    });

    test('rejects noncanonical JSON spellings of valid paths', () {
      const noncanonical = <String>[
        '[ "main" ]',
        '["main" ]',
        '[\n"main"\n]',
        r'["ma\u0069n"]',
        '["main", "children", 0]',
      ];

      for (final encoded in noncanonical) {
        expect(
          () => DocumentPathCodec.decode(encoded),
          throwsA(isA<FormatException>()),
          reason: encoded,
        );
      }
    });

    test('rejects malformed paths before encoding', () {
      const malformed = <List<Object>>[
        <Object>[],
        <Object>[0],
        <Object>['main', 0],
        <Object>['main', 'children', -1],
        <Object>['main', 'children', 0, 1],
        <Object>['main', true],
      ];

      for (final path in malformed) {
        expect(
          () => DocumentPathCodec.encode(path),
          throwsA(isA<FormatException>()),
          reason: path.toString(),
        );
      }
    });
  });
}
