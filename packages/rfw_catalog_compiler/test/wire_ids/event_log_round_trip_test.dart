import 'dart:convert';
import 'dart:io';

import 'package:rfw_catalog_compiler/rfw_catalog_compiler.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

const _at = '2026-05-11T12:00:00Z';
const _by = 'rfw_catalog_compiler@0.1.0';

void main() {
  group('wire ID event log', () {
    test('round-trips events with canonical JSON key order', () {
      final events = [
        AllocWireIdEvent(
          type: WireIdKind.widget,
          id: WireId('w0001'),
          name: 'Center',
          source: 'package:flutter/src/widgets/basic.dart#Center',
          at: _at,
          by: _by,
        ),
        AllocWireIdEvent(
          type: WireIdKind.property,
          id: WireId('p0001'),
          owner: WireId('w0001'),
          name: 'width',
          source: 'package:flutter/src/widgets/basic.dart#Center.width',
          at: _at,
          by: _by,
        ),
        AllocWireIdEvent(
          type: WireIdKind.designToken,
          id: WireId('t0001'),
          name: 'primary',
          tokenType: 'color',
          resolver: const WireIdEventField<Map<String, Object?>?>.value(
            {'path': 'colorScheme.primary'},
          ),
          stability: 'stable',
          at: _at,
          by: _by,
        ),
        UpdateTokenWireIdEvent(
          id: WireId('t0001'),
          description: const WireIdEventField<String?>.value(
            'Primary brand color.',
          ),
          at: '2026-05-11T12:01:00Z',
          by: _by,
        ),
      ];

      final encoded = encodeWireIdEventsJsonl(events);
      final decoded = parseWireIdEventsJsonl(encoded);

      expect(encodeWireIdEventsJsonl(decoded), encoded);
      expect(
        encoded.split('\n').first,
        '{"at":"2026-05-11T12:00:00Z",'
        '"by":"rfw_catalog_compiler@0.1.0",'
        '"id":"w0001","kind":"alloc","name":"Center",'
        '"source":"package:flutter/src/widgets/basic.dart#Center",'
        '"type":"widget"}',
      );
    });

    test('rejects CRLF with a line number', () {
      expect(
        () => parseWireIdEventsJsonl(
          '{"kind":"alloc"}\r\n',
          sourceDescription: 'fixture',
        ),
        throwsA(
          isA<WireIdEventException>()
              .having((error) => error.lineNumber, 'lineNumber', 1)
              .having(
                (error) => error.message,
                'message',
                contains('CR/CRLF'),
              ),
        ),
      );
    });

    test('rejects unknown event fields strictly', () {
      expect(
        () => parseWireIdEventsJsonl(
          '{"kind":"alloc","type":"widget","id":"w0001",'
          '"name":"Center","source":"src#Center","extra":true,'
          '"at":"2026-05-11T12:00:00Z","by":"test"}\n',
        ),
        throwsA(
          isA<WireIdEventException>()
              .having((error) => error.lineNumber, 'lineNumber', 1)
              .having(
                (error) => error.message,
                'message',
                contains('unknown field'),
              ),
        ),
      );
    });

    test('rejects unknown event kinds and event types', () {
      expect(
        () => parseWireIdEventsJsonl(
          '{"kind":"move","type":"widget","id":"w0001",'
          '"name":"Center","source":"src#Center",'
          '"at":"2026-05-11T12:00:00Z","by":"test"}\n',
        ),
        throwsA(
          isA<WireIdEventException>().having(
            (error) => error.message,
            'message',
            contains('unknown wire ID event kind'),
          ),
        ),
      );
      expect(
        () => parseWireIdEventsJsonl(
          '{"kind":"alloc","type":"gesture","id":"w0001",'
          '"name":"Center","source":"src#Center",'
          '"at":"2026-05-11T12:00:00Z","by":"test"}\n',
        ),
        throwsA(
          isA<WireIdEventException>().having(
            (error) => error.message,
            'message',
            contains('unknown wire ID event type'),
          ),
        ),
      );
    });

    test('rejects sentinel IDs in JSON events', () {
      expect(
        () => parseWireIdEventsJsonl(
          '{"kind":"alloc","type":"widget","id":"w0000",'
          '"name":"Center","source":"src#Center",'
          '"at":"2026-05-11T12:00:00Z","by":"test"}\n',
        ),
        throwsA(
          isA<WireIdEventException>().having(
            (error) => error.message,
            'message',
            contains('positive decimal integer'),
          ),
        ),
      );
    });

    test('accepts zero-padded replace transitions and rejects bad forms', () {
      final event = parseWireIdEventsJsonl(
        '{"kind":"replace","type":"widget","from":"w0001","to":"w0002",'
        '"transition":"tx0001","at":"2026-05-11T12:00:00Z",'
        '"by":"test"}\n',
      ).single as ReplaceWireIdEvent;

      expect(event.transition, 'tx0001');

      for (final transition in ['tx0000', 'tx1', 'x0001', 'tt0001', 'txzzzz']) {
        expect(
          () => parseWireIdEventsJsonl(
            '{"kind":"replace","type":"widget","from":"w0001","to":"w0002",'
            '"transition":"$transition","at":"2026-05-11T12:00:00Z",'
            '"by":"test"}\n',
          ),
          throwsA(
            isA<WireIdEventException>().having(
              (error) => error.message,
              'message',
              contains('transition'),
            ),
          ),
          reason: transition,
        );
      }
    });

    test('validates variant source-kind conditional fields', () {
      for (final sourceKind in VariantSourceKind.values) {
        final json = sourceKind == VariantSourceKind.constructor
            ? '{"kind":"alloc","type":"variant","id":"v0001",'
                '"owner":"s0001","sourceKind":"constructor",'
                '"namedConstructor":null,"source":"src#Shape.",'
                '"at":"2026-05-11T12:00:00Z","by":"test"}\n'
            : '{"kind":"alloc","type":"variant","id":"v0001",'
                '"owner":"s0001","sourceKind":"${sourceKind.name}",'
                '"staticAccessor":"zero","source":"src#Shape.zero",'
                '"at":"2026-05-11T12:00:00Z","by":"test"}\n';
        expect(parseWireIdEventsJsonl(json), hasLength(1));
      }

      for (final json in [
        _eventJsonl({
          'kind': 'alloc',
          'type': 'variant',
          'id': 'v0001',
          'owner': 's0001',
          'sourceKind': 'constructor',
          'staticAccessor': 'zero',
          'source': 'src#Shape.zero',
          'at': _at,
          'by': 'test',
        }),
        _eventJsonl({
          'kind': 'alloc',
          'type': 'variant',
          'id': 'v0001',
          'owner': 's0001',
          'sourceKind': 'staticGetter',
          'namedConstructor': 'zero',
          'source': 'src#Shape.zero',
          'at': _at,
          'by': 'test',
        }),
        _eventJsonl({
          'kind': 'alloc',
          'type': 'variant',
          'id': 'v0001',
          'owner': 's0001',
          'sourceKind': 'constructor',
          'namedConstructor': '',
          'source': 'src#Shape.',
          'at': _at,
          'by': 'test',
        }),
      ]) {
        expect(
          () => parseWireIdEventsJsonl(json),
          throwsA(isA<WireIdEventException>()),
        );
      }
    });

    test('validates parameter allocation owners', () {
      final encoded = encodeWireIdEventJson(
        AllocWireIdEvent(
          type: WireIdKind.parameter,
          id: WireId('a0001'),
          owner: WireId('v0001'),
          name: 'radius',
          source: 'src#BorderRadius.circular.radius',
          at: _at,
          by: _by,
        ),
      );

      expect(
        encoded,
        '{"at":"2026-05-11T12:00:00Z",'
        '"by":"rfw_catalog_compiler@0.1.0",'
        '"id":"a0001","kind":"alloc","name":"radius",'
        '"owner":"v0001","source":"src#BorderRadius.circular.radius",'
        '"type":"parameter"}',
      );
      expect(parseWireIdEventsJsonl('$encoded\n'), hasLength(1));

      expect(
        () => parseWireIdEventsJsonl(
          '{"kind":"alloc","type":"parameter","id":"a0001",'
          '"owner":"s0001","name":"radius",'
          '"source":"src#BorderRadius.circular.radius",'
          '"at":"2026-05-11T12:00:00Z","by":"test"}\n',
        ),
        throwsA(
          isA<WireIdEventException>().having(
            (error) => error.message,
            'message',
            contains('parameter owner must be a variant wire ID'),
          ),
        ),
      );
    });

    test('distinguishes omitted updateToken patches from explicit nulls', () {
      expect(
        () => parseWireIdEventsJsonl(
          '{"kind":"updateToken","id":"t0001",'
          '"at":"2026-05-11T12:00:00Z","by":"test"}\n',
        ),
        throwsA(
          isA<WireIdEventException>().having(
            (error) => error.message,
            'message',
            contains('requires at least one'),
          ),
        ),
      );

      final event = parseWireIdEventsJsonl(
        '{"kind":"updateToken","id":"t0001","resolver":null,'
        '"literalFallback":null,"description":null,'
        '"at":"2026-05-11T12:00:00Z","by":"test"}\n',
      ).single as UpdateTokenWireIdEvent;
      expect(event.resolver.isPresent, isTrue);
      expect(event.resolver.value, isNull);
      expect(event.literalFallback.isPresent, isTrue);
      expect(event.literalFallback.value, isNull);
      expect(event.description.isPresent, isTrue);
      expect(event.description.value, isNull);

      for (final json in [
        _eventJsonl({
          'kind': 'updateToken',
          'id': 't0001',
          'stability': null,
          'at': _at,
          'by': 'test',
        }),
        _eventJsonl({
          'kind': 'updateToken',
          'id': 't0001',
          'description': 42,
          'at': _at,
          'by': 'test',
        }),
        _eventJsonl({
          'kind': 'updateToken',
          'id': 't0001',
          'resolver': 42,
          'at': _at,
          'by': 'test',
        }),
      ]) {
        expect(
          () => parseWireIdEventsJsonl(json),
          throwsA(isA<WireIdEventException>()),
        );
      }
    });

    test('validates design-token type and literal fallback shape', () {
      expect(
        parseWireIdEventsJsonl(
          '{"kind":"alloc","type":"design_token","id":"t0001",'
          '"name":"spacing","tokenType":"length","literalFallback":12.5,'
          '"at":"2026-05-11T12:00:00Z","by":"test"}\n',
        ),
        hasLength(1),
      );
      for (final json in [
        _eventJsonl({
          'kind': 'alloc',
          'type': 'design_token',
          'id': 't0001',
          'name': 'primary',
          'tokenType': 'typography',
          'literalFallback': 12,
          'at': _at,
          'by': 'test',
        }),
        _eventJsonl({
          'kind': 'alloc',
          'type': 'design_token',
          'id': 't0001',
          'name': 'primary',
          'tokenType': 'color',
          'literalFallback': 'red',
          'at': _at,
          'by': 'test',
        }),
        _eventJsonl({
          'kind': 'alloc',
          'type': 'design_token',
          'id': 't0001',
          'name': 'duration',
          'tokenType': 'duration',
          'literalFallback': 12.5,
          'at': _at,
          'by': 'test',
        }),
      ]) {
        expect(
          () => parseWireIdEventsJsonl(json),
          throwsA(isA<WireIdEventException>()),
        );
      }
    });

    test('validates typed events before encoding or writing', () {
      final invalidEvents = <WireIdEvent>[
        AllocWireIdEvent(
          type: WireIdKind.widget,
          id: WireId('w0001'),
          at: _at,
          by: _by,
        ),
        AllocWireIdEvent(
          type: WireIdKind.variant,
          id: WireId('v0001'),
          owner: WireId('s0001'),
          sourceKind: VariantSourceKind.constructor,
          staticAccessor: 'zero',
          source: 'src#Shape.zero',
          at: _at,
          by: _by,
        ),
        UpdateTokenWireIdEvent(
          id: WireId('t0001'),
          at: _at,
          by: _by,
        ),
        ReplaceWireIdEvent(
          type: WireIdKind.widget,
          from: WireId('w0001'),
          to: WireId('w0001'),
          transition: 'tx0001',
          at: _at,
          by: _by,
        ),
        ReplaceWireIdEvent(
          type: WireIdKind.widget,
          from: WireId('w0001'),
          to: WireId('p0001'),
          transition: 'tx0001',
          at: _at,
          by: _by,
        ),
        ReplaceWireIdEvent(
          type: WireIdKind.widget,
          from: WireId('w0001'),
          to: WireId('w0002'),
          transition: 'tx1',
          at: _at,
          by: _by,
        ),
      ];

      for (final event in invalidEvents) {
        expect(
          () => encodeWireIdEventJson(event),
          throwsA(isA<WireIdEventException>()),
          reason: event.runtimeType.toString(),
        );
      }

      final directory = Directory.systemTemp.createTempSync('wire_ids_');
      addTearDown(() => directory.deleteSync(recursive: true));
      final file = File('${directory.path}/wire_ids.events.jsonl');
      final valid = AllocWireIdEvent(
        type: WireIdKind.widget,
        id: WireId('w0001'),
        name: 'Center',
        source: 'src#Center',
        at: _at,
        by: _by,
      );

      expect(
        () => writeWireIdEventLogSync(file, [invalidEvents.first]),
        throwsA(isA<WireIdEventException>()),
      );
      writeWireIdEventLogSync(file, [valid]);
      expect(
        () => appendWireIdEventsSync(file, [invalidEvents.first]),
        throwsA(isA<WireIdEventException>()),
      );
    });
  });
}

String _eventJsonl(Map<String, Object?> json) => '${jsonEncode(json)}\n';
