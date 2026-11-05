import 'package:restage_compiler_core/src/surface_fit_projection.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart';
import 'package:test/test.dart';

Map<String, Object?> _reads(String design) {
  final reads = rfwLayoutReads(
    parseLibraryFile('''
      import core;
      widget Framed = Column(children: [args.child]);
      widget Paywall = $design;
    '''),
    'Paywall',
  );
  return SurfaceLayoutReadsV1(
    values: reads.values,
    islands: reads.constructors,
  ).toJson();
}

void main() {
  group('layout reads', () {
    test('return arms and their default', () {
      expect(
        _reads('switch data.context._hB {0: Text(text: data.context._hA), '
            'default: Badge(text: data.context.title)}'),
        {
          'values': {
            '_hA': [
              {
                '_hB': {
                  'oneOf': [0],
                },
              },
            ],
            'title': [
              {
                '_hB': {
                  'noneOf': [0],
                },
              },
            ],
          },
          'islands': {
            'Badge': [
              {
                '_hB': {
                  'noneOf': [0],
                },
              },
            ],
            'Text': [
              {
                '_hB': {
                  'oneOf': [0],
                },
              },
            ],
          },
        },
      );
    });

    test('a flow screen lists every read', () {
      final reads = rfwLayoutReads(
        parseLibraryFile('''
          import core;
          widget OnboardingScreen = Column(children: [Text(text: data.context._hA)]);
        '''),
        'OnboardingScreen',
        everyRead: true,
      );
      expect(SurfaceLayoutReadsV1(values: reads.values).toJson(), {
        'values': {
          '_hA': [<String, Object?>{}],
        },
      });
      expect(reads.constructors.keys, containsAll(['Column', 'Text']));
    });

    test('a native binding is read by its key', () {
      expect(
        _reads('switch data.context._hB {0: Text(text: "x", key: '
            '{ kind: "nativeBinding", key: "_hK", type: "flutter.Key", '
            'nullable: true })}')['values'],
        {
          '_hK': [
            {
              '_hB': {
                'oneOf': [0],
              },
            },
          ],
        },
      );
    });

    test('a presence loop, an item loop and a local widget argument', () {
      expect(
        _reads('Column(children: [...for presence in switch '
            'data.context._hG { true: [0], false: [] }: '
            'Framed(child: Column(children: [...for p in data.context._hL: '
            'switch p._hE { true: Text(text: p._hN) }]))])')['values'],
        {
          '_hE': [
            {
              '_hG': {
                'oneOf': [true],
              },
            },
          ],
          '_hL': [
            {
              '_hG': {
                'oneOf': [true],
              },
            },
          ],
          '_hN': [
            {
              '_hE': {
                'oneOf': [true],
              },
              '_hG': {
                'oneOf': [true],
              },
            },
          ],
        },
      );
    });
  });
}
