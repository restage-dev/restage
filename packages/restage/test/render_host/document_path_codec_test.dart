import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/render_host/render_core.dart';

void main() {
  group('DocumentPathCodec', () {
    test('round-trips compact authored paths as strict JSON', () {
      const paths = <List<Object>>[
        <Object>['main'],
        <Object>['main', 'child'],
        <Object>['main', 'children', 0],
        <Object>['main', 'children', 3, 'child'],
        <Object>['main', 'args'],
        <Object>['main', r'$case', 1, 'child'],
        <Object>['main', 'children', 2, r'$output', 'children', 0],
        <Object>['main', 'builder', r'$body'],
        <Object>['main', 'config', r'$key', 'icon'],
        <Object>['main', r'$$case'],
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
        <Object>['main', r'$case'],
        <Object>['main', r'$case', 'x'],
        <Object>['main', r'$key'],
        <Object>['main', r'$unknown'],
        <Object>['main', r'$output', 0, 1],
        <Object>['main', r'$case', 0, 1, 2],
      ];

      for (final path in malformed) {
        expect(
          () => DocumentPathCodec.encode(path),
          throwsA(isA<FormatException>()),
          reason: path.toString(),
        );
      }
    });

    group('steps', () {
      test('a slot named like a marker stays a slot', () {
        const path = <Object>['main', r'$$case', r'$$$key', 'output', 'body'];
        final steps = DocumentPathCodec.parseCompact(path);
        expect(steps, const <PathStep>[
          SlotStep(r'$case'),
          SlotStep(r'$$key'),
          SlotStep('output'),
          SlotStep('body'),
        ]);
        expect(DocumentPathCodec.formatCompact('main', steps), path);
      });

      test('a plain-map key and a loop body never read alike', () {
        final key = DocumentPathCodec.parseCompact(const <Object>[
          'main',
          'config',
          r'$key',
          'output',
        ]);
        final loop = DocumentPathCodec.parseCompact(const <Object>[
          'main',
          'config',
          r'$output',
        ]);
        expect(key.last, const KeyStep('output'));
        expect(loop.last, const OutputStep());
      });

      test('compact and document dialects round-trip every step', () {
        const steps = <PathStep>[
          SlotStep('children'),
          IndexStep(2),
          OutputStep(),
          SlotStep('child'),
          CaseStep(1),
          SlotStep('builder'),
          BodyStep(),
          SlotStep('config'),
          KeyStep('args'),
          SlotStep('onTap'),
          ValueStep(),
        ];
        final document = DocumentPathCodec.formatDocument('main', steps);
        expect(document, const <Object>[
          'main', 'args', 'children', 2, 'output', 'args', 'child', //
          'cases', 1, 1, 'args', 'builder', 'body', 'args', 'config', //
          r'$key', 'args', 'args', 'onTap', 'value',
        ]);
        expect(DocumentPathCodec.parseDocument(document), steps);
        final compact = DocumentPathCodec.formatCompact('main', steps);
        expect(DocumentPathCodec.parseCompact(compact), steps);
      });

      test('an index follows a case, loop, body or value step', () {
        const steps = <PathStep>[
          SlotStep('children'),
          CaseStep(0),
          IndexStep(1),
          SlotStep('children'),
          OutputStep(),
          IndexStep(0),
          SlotStep('builder'),
          BodyStep(),
          IndexStep(2),
          SlotStep('onTap'),
          ValueStep(),
          IndexStep(3),
        ];
        final compact = DocumentPathCodec.formatCompact('main', steps);
        expect(DocumentPathCodec.parseCompact(compact), steps);
        final document = DocumentPathCodec.formatDocument('main', steps);
        expect(DocumentPathCodec.parseDocument(document), steps);
      });

      test('the document dialect rejects bare structure', () {
        for (final path in <List<Object>>[
          ['main', 'child'],
          ['main', 'cases', 0],
          ['main', 'cases', 0, 2],
          ['main', 'args'],
          ['main', 0],
        ]) {
          expect(
            () => DocumentPathCodec.parseDocument(path),
            throwsA(isA<FormatException>()),
            reason: '$path',
          );
        }
      });
    });
  });
}
