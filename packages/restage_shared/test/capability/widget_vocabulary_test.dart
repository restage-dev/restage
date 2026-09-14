import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

void main() {
  group('WidgetVocabulary', () {
    test('input order does not change equality or JSON', () {
      const namesInOneOrder = {'restage.material:Icon', 'restage.core:Column'};
      const namesInAnotherOrder = {
        'restage.core:Column',
        'restage.material:Icon',
      };
      const iconsInOneOrder = {
        'CupertinoIcons': {0xf3d0},
        'MaterialIcons': {0xe88a, 0xe5d2},
      };
      const iconsInAnotherOrder = {
        'MaterialIcons': {0xe5d2, 0xe88a},
        'CupertinoIcons': {0xf3d0},
      };

      // The test is only meaningful while the two inputs really do iterate in
      // different orders, so fail loudly rather than silently if they do not.
      expect(
        namesInOneOrder.toList(),
        isNot(namesInAnotherOrder.toList()),
      );
      expect(
        iconsInOneOrder.keys.toList(),
        isNot(iconsInAnotherOrder.keys.toList()),
      );
      expect(
        iconsInOneOrder['MaterialIcons']!.toList(),
        isNot(iconsInAnotherOrder['MaterialIcons']!.toList()),
      );

      final a = WidgetVocabulary(
        widgetNames: namesInOneOrder,
        iconCodePoints: iconsInOneOrder,
      );
      final b = WidgetVocabulary(
        widgetNames: namesInAnotherOrder,
        iconCodePoints: iconsInAnotherOrder,
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.toJson(), b.toJson());
      expect(a.widgetNames.toList(), [
        'restage.core:Column',
        'restage.material:Icon',
      ]);
      expect(a.iconCodePoints.keys.toList(), [
        'CupertinoIcons',
        'MaterialIcons',
      ]);
      expect(a.iconCodePoints['MaterialIcons']!.toList(), [0xe5d2, 0xe88a]);
    });

    test('round-trips through JSON across several font families', () {
      final vocabulary = WidgetVocabulary(
        widgetNames: const {'restage.material:Icon', 'restage.core:Text'},
        iconCodePoints: const {
          'MaterialIcons': {0xe5d2, 0xe88a},
          'CupertinoIcons': {0xf3d0},
        },
      );

      final decoded = WidgetVocabulary.fromJson(vocabulary.toJson());

      expect(decoded, vocabulary);
      expect(decoded.hashCode, vocabulary.hashCode);
      expect(vocabulary.toJson(), {
        'widgetNames': ['restage.core:Text', 'restage.material:Icon'],
        'iconCodePoints': {
          'CupertinoIcons': [0xf3d0],
          'MaterialIcons': [0xe5d2, 0xe88a],
        },
      });
    });

    test('union names everything from both sides, per font family', () {
      final a = WidgetVocabulary(
        widgetNames: const {'restage.core:Column'},
        iconCodePoints: const {
          'MaterialIcons': {0xe5d2},
        },
      );
      final b = WidgetVocabulary(
        widgetNames: const {'restage.material:Icon'},
        iconCodePoints: const {
          'MaterialIcons': {0xe88a},
          'CupertinoIcons': {0xf3d0},
        },
      );

      expect(
        a.union(b),
        WidgetVocabulary(
          widgetNames: const {'restage.core:Column', 'restage.material:Icon'},
          iconCodePoints: const {
            'MaterialIcons': {0xe5d2, 0xe88a},
            'CupertinoIcons': {0xf3d0},
          },
        ),
      );
    });

    test('containsAll accepts a subset and rejects anything unnamed', () {
      final installed = WidgetVocabulary(
        widgetNames: const {'restage.core:Column', 'restage.material:Icon'},
        iconCodePoints: const {
          'MaterialIcons': {0xe5d2, 0xe88a},
        },
      );

      expect(installed.containsAll(WidgetVocabulary.empty), isTrue);
      expect(
        installed.containsAll(
          WidgetVocabulary(
            widgetNames: const {'restage.material:Icon'},
            iconCodePoints: const {
              'MaterialIcons': {0xe5d2},
            },
          ),
        ),
        isTrue,
      );

      expect(
        installed.containsAll(
          WidgetVocabulary(widgetNames: const {'restage.material:Chip'}),
        ),
        isFalse,
        reason: 'a widget name that is not installed',
      );
      expect(
        installed.containsAll(
          WidgetVocabulary(
            iconCodePoints: const {
              'MaterialIcons': {0xe000},
            },
          ),
        ),
        isFalse,
        reason: 'a code point missing from an installed font family',
      );
      expect(
        installed.containsAll(
          WidgetVocabulary(
            iconCodePoints: const {
              'CupertinoIcons': {0xf3d0},
            },
          ),
        ),
        isFalse,
        reason: 'a font family that is not installed at all',
      );
    });

    test('qualifiedName spells the full namespace, built-in or custom', () {
      expect(
        WidgetVocabulary.qualifiedName('restage.material', 'Icon'),
        'restage.material:Icon',
      );
      expect(
        WidgetVocabulary.qualifiedName('com.acme.widgets', 'Button'),
        'com.acme.widgets:Button',
      );
    });

    test('qualifiedName rejects an empty part or a stray separator', () {
      expect(
        () => WidgetVocabulary.qualifiedName('', 'Icon'),
        throwsArgumentError,
      );
      expect(
        () => WidgetVocabulary.qualifiedName('restage.material', ''),
        throwsArgumentError,
      );
      expect(
        () => WidgetVocabulary.qualifiedName('restage.material', 'a:b'),
        throwsArgumentError,
      );
      expect(
        () => WidgetVocabulary.qualifiedName('restage:material', 'Icon'),
        throwsArgumentError,
      );
    });

    test('decodes missing and null fields as empty', () {
      expect(WidgetVocabulary.fromJson(const {}), WidgetVocabulary.empty);
      expect(
        WidgetVocabulary.fromJson(
          const {'widgetNames': null, 'iconCodePoints': null},
        ),
        WidgetVocabulary.empty,
      );
      expect(WidgetVocabulary.empty.widgetNames, isEmpty);
      expect(WidgetVocabulary.empty.iconCodePoints, isEmpty);
    });

    test('rejects wrong-typed fields', () {
      expect(
        () => WidgetVocabulary.fromJson(
          const {'widgetNames': 'restage.core:Column'},
        ),
        throwsFormatException,
      );
      expect(
        () => WidgetVocabulary.fromJson(const {
          'widgetNames': [7],
        }),
        throwsFormatException,
      );
      expect(
        () => WidgetVocabulary.fromJson(const {'iconCodePoints': <int>[]}),
        throwsFormatException,
      );
      expect(
        () => WidgetVocabulary.fromJson(const {
          'iconCodePoints': {'MaterialIcons': 58834},
        }),
        throwsFormatException,
      );
      expect(
        () => WidgetVocabulary.fromJson(const {
          'iconCodePoints': {
            'MaterialIcons': ['e5d2'],
          },
        }),
        throwsFormatException,
      );
    });
  });
}
