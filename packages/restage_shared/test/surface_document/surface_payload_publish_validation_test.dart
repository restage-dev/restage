import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart';
import 'package:test/test.dart';

void main() {
  final font = _fixture('material_icons_subset.otf');

  group('icon font coverage', () {
    test('a payload without icon fonts is not checked', () {
      final payload = _blob(
        'widget Root = Icon(iconCodepoint: 0xe000);',
        minClient: 3,
      );
      expect(() => validatePayloadSectionsForPublish(payload), returnsNormally);
    });

    test('every literal icon covered by its family font passes', () {
      final payload = _blob(
        '''
widget Root = Column(children: [
  Icon(iconCodepoint: 0xe87d),
  Icon(iconCodepoint: 0xe5cc, iconFontFamily: "MaterialIcons"),
  TextField(prefixIconCodepoint: 0xf63a, prefixIconFontFamily: "MaterialIcons"),
]);
''',
        iconFonts: [DeliveredIconFont(family: 'MaterialIcons', bytes: font)],
      );
      expect(() => validatePayloadSectionsForPublish(payload), returnsNormally);
    });

    test('an uncovered code point is refused by family and code point', () {
      final payload = _blob(
        '''
widget Root = Column(children: [
  Icon(iconCodepoint: 0xe87d),
  Icon(iconCodepoint: 0xe000),
  Icon(iconCodepoint: 0xe87d, iconFontFamily: "CupertinoIcons"),
]);
''',
        iconFonts: [DeliveredIconFont(family: 'MaterialIcons', bytes: font)],
      );
      expect(
        () => validatePayloadSectionsForPublish(payload),
        throwsA(
          isA<IconFontCoverageException>().having(
            (e) => e.missing,
            'missing',
            {
              'CupertinoIcons': [0xe87d],
              'MaterialIcons': [0xe000],
            },
          ).having((e) => e.message, 'message', contains('U+E000')),
        ),
      );
    });

    test('both outputs of a literal switch must be covered', () {
      final payload = _blob(
        '''
widget Root = Icon(iconCodepoint: switch data.on { true: 0xe87d, false: 0xe001 });
''',
        iconFonts: [DeliveredIconFont(family: 'MaterialIcons', bytes: font)],
      );
      expect(
        () => validatePayloadSectionsForPublish(payload),
        throwsA(
          isA<IconFontCoverageException>().having(
            (e) => e.missing,
            'missing',
            {
              'MaterialIcons': [0xe001],
            },
          ),
        ),
      );
    });

    test('a data-bound code point is not checked', () {
      final payload = _blob(
        'widget Root = Icon(iconCodepoint: data.icon);',
        iconFonts: [DeliveredIconFont(family: 'MaterialIcons', bytes: font)],
      );
      expect(() => validatePayloadSectionsForPublish(payload), returnsNormally);
    });

    test('every flow screen is checked', () {
      final payload = _flow(
        {
          'a': 'widget A = Icon(iconCodepoint: 0xe87d);',
          'b': 'widget B = Icon(iconCodepoint: 0xe002);',
        },
        iconFonts: [DeliveredIconFont(family: 'MaterialIcons', bytes: font)],
      );
      expect(
        () => validatePayloadSectionsForPublish(payload),
        throwsA(isA<IconFontCoverageException>()),
      );
    });

    test('a font over the byte cap is refused', () {
      final big = Uint8List(kMaxDeliveredIconFontBytes + 1)
        ..setRange(0, font.length, font);
      final payload = _blob(
        'widget Root = Icon(iconCodepoint: 0xe87d);',
        iconFonts: [DeliveredIconFont(family: 'MaterialIcons', bytes: big)],
      );
      expect(
        () => validatePayloadSectionsForPublish(payload),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('MaterialIcons'),
          ),
        ),
      );
    });

    test('a font that is not an sfnt is refused', () {
      final payload = _blob(
        'widget Root = Icon(iconCodepoint: 0xe87d);',
        iconFonts: [
          DeliveredIconFont(
            family: 'MaterialIcons',
            bytes: Uint8List.fromList(utf8.encode('not a font')),
          ),
        ],
      );
      expect(
        () => validatePayloadSectionsForPublish(payload),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('MaterialIcons'),
          ),
        ),
      );
    });
  });

  group('reserved commerce events', () {
    Matcher refused(String name) => throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'The event name "$name" is reserved. Choose another name.',
          ),
        );

    test('a blob screen may not emit one', () {
      for (final name in kReservedCommerceEventNames) {
        expect(
          () => validatePayloadSectionsForPublish(
            _blob('widget Root = Button(onPressed: event "$name" {});'),
          ),
          refused(name),
          reason: name,
        );
      }
    });

    test('a flow screen may not emit one, inside a builder', () {
      expect(
        () => validatePayloadSectionsForPublish(
          _flow({
            'a': 'widget A = Text(text: "Hi");',
            'b': 'widget B = Sheet(builder: (scope) => '
                'Button(onPressed: event "purchase" { productId: "pro" }));',
          }),
        ),
        refused('purchase'),
      );
    });

    test('a name that only starts like one is accepted', () {
      expect(
        () => validatePayloadSectionsForPublish(
          _blob('widget Root = Button(onPressed: event "purchased" {});'),
        ),
        returnsNormally,
      );
    });
  });

  group('local seed roots', () {
    test('a blob seed must name a widget the blob declares', () {
      expect(
        () => validatePayloadSectionsForPublish(
          _blob(
            'widget Root = Text(text: data.local.answer);',
            localSeeds: {
              'Root': {'answer': ''},
            },
          ),
        ),
        returnsNormally,
      );
      expect(
        () => validatePayloadSectionsForPublish(
          _blob(
            'widget Root = Text(text: data.local.answer);',
            localSeeds: {
              'Other': {'answer': ''},
            },
          ),
        ),
        throwsFormatException,
      );
    });
  });
}

Uint8List _rfw(String source) => encodeLibraryBlob(parseLibraryFile(source));

BlobSurfacePayload _blob(
  String source, {
  int minClient = kSurfaceFeatureClientFloor,
  List<DeliveredIconFont> iconFonts = const [],
  Map<String, Map<String, Object>> localSeeds = const {},
}) =>
    BlobSurfacePayload(
      minClient: minClient,
      blob: _rfw(source),
      iconFonts: iconFonts,
      localSeeds: localSeeds,
    );

FlowSurfacePayload _flow(
  Map<String, String> screens, {
  List<DeliveredIconFont> iconFonts = const [],
}) {
  final blobs = {
    for (final entry in screens.entries) entry.key: _rfw(entry.value),
  };
  final ids = screens.keys.toList();
  final json = <String, Object?>{
    'flow': 'screens',
    'initial': ids.first,
    'minClient': kSurfaceFeatureClientFloor,
    'schemaVersion': 1,
    'screenArtifacts': {
      for (final entry in blobs.entries)
        entry.key: {
          'contentHash': 'sha256:${crypto.sha256.convert(entry.value)}',
          'minClient': 3,
          'path': '${entry.key}.rfw',
          'schemaVersion': 1,
          'version': 1,
        },
    },
    'states': {
      for (var i = 0; i < ids.length; i += 1)
        ids[i]: {
          'kind': 'screen',
          'screen': ids[i],
          'on': {
            'act': {
              'target': i + 1 < ids.length ? ids[i + 1] : 'done',
              'type': 'goto',
            },
          },
        },
      'done': {'kind': 'end', 'result': <String, Object?>{}},
    },
    'version': 1,
  };
  return FlowSurfacePayload(
    flowDocument: FlowDocumentCodec.decodeJson(jsonEncode(json)),
    screenBlobs: blobs,
    iconFonts: iconFonts,
  );
}

Uint8List _fixture(String name) {
  const dir = 'test/fonts/fixtures';
  final workspace = File('packages/restage_shared/$dir/$name');
  return (workspace.existsSync() ? workspace : File('$dir/$name'))
      .readAsBytesSync();
}
