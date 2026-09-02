import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/runtime/context_data.dart';
import 'package:rfw/rfw.dart';

final class _CountingContent extends DynamicContent {
  int updates = 0;

  @override
  void update(String rootKey, Object value) {
    updates += 1;
    super.update(rootKey, value);
  }
}

enum _MapReadFailure { keys, iteration, currentKey, value }

final class _UnreadableMap extends MapBase<String, Object?> {
  _UnreadableMap(this.failure);

  final _MapReadFailure failure;

  @override
  Iterable<String> get keys {
    if (failure == _MapReadFailure.keys) {
      throw StateError('map keys unavailable');
    }
    if (failure == _MapReadFailure.iteration ||
        failure == _MapReadFailure.currentKey) {
      return _UnreadableKeys(failure);
    }
    return const <String>['first', 'second'];
  }

  @override
  Object? operator [](Object? key) {
    if (failure == _MapReadFailure.value && key == 'second') {
      throw StateError('map value unavailable');
    }
    return key == 'first' ? 'partial' : 'complete';
  }

  @override
  void operator []=(String key, Object? value) =>
      throw UnsupportedError('read only');

  @override
  void clear() => throw UnsupportedError('read only');

  @override
  Object? remove(Object? key) => throw UnsupportedError('read only');
}

final class _UnreadableKeys extends IterableBase<String> {
  const _UnreadableKeys(this.failure);

  final _MapReadFailure failure;

  @override
  Iterator<String> get iterator => _UnreadableKeyIterator(failure);
}

final class _UnreadableKeyIterator implements Iterator<String> {
  _UnreadableKeyIterator(this.failure);

  final _MapReadFailure failure;

  @override
  String get current {
    if (failure == _MapReadFailure.currentKey) {
      throw StateError('map key unavailable');
    }
    return 'first';
  }

  @override
  bool moveNext() {
    if (failure == _MapReadFailure.iteration) {
      throw StateError('map iteration unavailable');
    }
    return true;
  }
}

final class _EndlessMap extends MapBase<String, Object?> {
  @override
  Iterable<String> get keys => _EndlessKeys();

  @override
  Object? operator [](Object? key) => null;

  @override
  void operator []=(String key, Object? value) =>
      throw UnsupportedError('read only');

  @override
  void clear() => throw UnsupportedError('read only');

  @override
  Object? remove(Object? key) => throw UnsupportedError('read only');
}

final class _EndlessKeys extends IterableBase<String> {
  @override
  Iterator<String> get iterator => _EndlessKeyIterator();
}

final class _EndlessKeyIterator implements Iterator<String> {
  int _index = 0;

  @override
  String get current => 'value$_index';

  @override
  bool moveNext() {
    _index += 1;
    return true;
  }
}

final class _FiniteNullMap extends MapBase<String, Object?> {
  _FiniteNullMap(this.entryCount);

  final int entryCount;

  @override
  Iterable<String> get keys => Iterable<String>.generate(
        entryCount,
        (index) => 'value$index',
      );

  @override
  Object? operator [](Object? key) => null;

  @override
  void operator []=(String key, Object? value) =>
      throw UnsupportedError('read only');

  @override
  void clear() => throw UnsupportedError('read only');

  @override
  Object? remove(Object? key) => throw UnsupportedError('read only');
}

final class _DuplicateKeyMap extends MapBase<String, Object?> {
  _DuplicateKeyMap(this.values);

  @override
  final List<Object?> values;
  var _readIndex = 0;

  @override
  Iterable<String> get keys => List<String>.filled(values.length, 'value');

  @override
  Object? operator [](Object? key) => values[_readIndex++];

  @override
  void operator []=(String key, Object? value) =>
      throw UnsupportedError('read only');

  @override
  void clear() => throw UnsupportedError('read only');

  @override
  Object? remove(Object? key) => throw UnsupportedError('read only');
}

enum _ListReadFailure { length, element }

final class _UnreadableList extends ListBase<Object?> {
  _UnreadableList(this.failure);

  final _ListReadFailure failure;

  @override
  int get length {
    if (failure == _ListReadFailure.length) {
      throw StateError('list length unavailable');
    }
    return 2;
  }

  @override
  set length(int value) => throw UnsupportedError('read only');

  @override
  Object? operator [](int index) {
    if (failure == _ListReadFailure.element && index == 1) {
      throw StateError('list value unavailable');
    }
    return index == 0 ? 'partial' : 'complete';
  }

  @override
  void operator []=(int index, Object? value) =>
      throw UnsupportedError('read only');
}

final class _ShrinkingList extends ListBase<Object?> {
  final List<Object?> _values = <Object?>['partial', 'removed'];

  @override
  int get length => 2;

  @override
  set length(int value) => throw UnsupportedError('read only');

  @override
  Object? operator [](int index) {
    if (index == 0 && _values.length == 2) _values.removeLast();
    return _values[index];
  }

  @override
  void operator []=(int index, Object? value) =>
      throw UnsupportedError('read only');
}

final class _GrowingList extends ListBase<Object?> {
  int _length = 0;

  @override
  int get length => ++_length;

  @override
  set length(int value) => throw UnsupportedError('read only');

  @override
  Object? operator [](int index) => null;

  @override
  void operator []=(int index, Object? value) =>
      throw UnsupportedError('read only');
}

final class _FiniteNullList extends ListBase<Object?> {
  _FiniteNullList(this._length);

  final int _length;

  @override
  int get length => _length;

  @override
  set length(int value) => throw UnsupportedError('read only');

  @override
  Object? operator [](int index) => null;

  @override
  void operator []=(int index, Object? value) =>
      throw UnsupportedError('read only');
}

const String _hostTypeSentinel = 'host-type-private-value';

final class _HostileRuntimeType {
  @override
  Type get runtimeType => throw StateError(_hostTypeSentinel);

  @override
  String toString() => throw StateError(_hostTypeSentinel);
}

final class _HostileTypeText {
  @override
  Type get runtimeType => const _ThrowingTypeText();

  @override
  String toString() => throw StateError(_hostTypeSentinel);
}

final class _ThrowingTypeText implements Type {
  const _ThrowingTypeText();

  @override
  String toString() => throw StateError(_hostTypeSentinel);
}

Object _readKey(DynamicContent content, String key) {
  void noop(Object _) {}
  final value = content.subscribe(<Object>[key], noop);
  content.unsubscribe(<Object>[key], noop);
  return value;
}

ContextNormalizationPolicy _throwingPolicy() {
  return ContextNormalizationPolicy(
    throwOnViolation: true,
    reportError: (_) {},
  );
}

ContextNormalizationPolicy _reportingPolicy(List<FlutterErrorDetails> errors) {
  return ContextNormalizationPolicy(
    throwOnViolation: false,
    reportError: errors.add,
  );
}

Map<String, Object?> _originalProfile() => <String, Object?>{
      'profile': <String, Object?>{
        'details': <String, Object?>{
          'name': 'original',
        },
        'labels': <Object?>['first'],
      },
    };

void _mutateProfile(Map<String, Object?> source) {
  final profile = source['profile']! as Map<String, Object?>;
  (profile['details']! as Map<String, Object?>)['name'] = 'changed';
  (profile['labels']! as List<Object?>).add('second');
}

Map<String, Object?> _contextAtDepth(int depth) {
  final root = <String, Object?>{};
  var current = root;
  for (var index = 0; index < depth; index += 1) {
    final child = <String, Object?>{};
    current['child'] = child;
    current = child;
  }
  current['value'] = 'leaf';
  return root;
}

const String _sensitiveContextKey = 'alice@example.invalid';

Object _cyclicContextValue() {
  final value = <String, Object?>{};
  value[_sensitiveContextKey] = value;
  return value;
}

Map<String, Object?> _oversizedContextValue() => <String, Object?>{
      for (var index = 0; index < 9999; index += 1) 'value$index': index,
    };

void main() {
  group('populateContextData', () {
    test('publishes normalized accepted context values', () {
      final content = DynamicContent();

      populateContextData(
        content,
        <String, Object?>{
          'text': 'hello',
          'integer': 3,
          'decimal': 2.5,
          'flag': true,
          'items': <Object?>['first', 2, 3.5, false],
          'nested': <String, Object?>{
            'levels': <Object?>[
              <String, Object?>{
                'value': 'deep',
              },
            ],
          },
        },
      );

      expect(
        _readKey(content, kContextDataKey),
        <String, Object?>{
          'text': 'hello',
          'integer': 3,
          'decimal': 2.5,
          'flag': true,
          'items': <Object?>['first', 2, 3.5, false],
          'nested': <String, Object?>{
            'levels': <Object?>[
              <String, Object?>{
                'value': 'deep',
              },
            ],
          },
        },
      );
    });

    test('omits null map values', () {
      final content = DynamicContent();

      populateContextData(
        content,
        <String, Object?>{
          'kept': 'value',
          'omitted': null,
        },
      );

      final context = _readKey(content, kContextDataKey) as Map;
      expect(context['kept'], 'value');
      expect(context.containsKey('omitted'), isFalse);
    });

    test('omits deeply nested null map values', () {
      final content = DynamicContent();

      populateContextData(
        content,
        <String, Object?>{
          'items': <Object?>[
            <String, Object?>{
              'details': <String, Object?>{
                'kept': 'value',
                'omitted': null,
              },
            },
          ],
        },
      );

      final context = _readKey(content, kContextDataKey) as Map;
      final items = context['items'] as List;
      final details = (items.single as Map)['details'] as Map;
      expect(details['kept'], 'value');
      expect(details.containsKey('omitted'), isFalse);
    });

    test('drops null list elements and compacts lists', () {
      final content = DynamicContent();

      populateContextData(
        content,
        <String, Object?>{
          'values': <Object?>[1, null, 3],
        },
      );

      final context = _readKey(content, kContextDataKey) as Map;
      expect(context['values'], <Object?>[1, 3]);
    });

    test('preserves empty maps and lists', () {
      final content = DynamicContent();

      populateContextData(
        content,
        <String, Object?>{
          'emptyMap': <String, Object?>{},
          'emptyList': <Object?>[],
        },
      );

      expect(
        _readKey(content, kContextDataKey),
        <String, Object?>{
          'emptyMap': <String, Object?>{},
          'emptyList': <Object?>[],
        },
      );
    });

    test('throws for an invalid value before publishing in debug mode', () {
      final content = DynamicContent();

      expect(
        () => populateContextData(
          content,
          <String, Object?>{
            'trial': <String, Object?>{
              'startedAt': DateTime.utc(2025),
            },
          },
        ),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message.toString(),
            'message',
            contains('context.trial.startedAt'),
          ),
        ),
      );
      expect(_readKey(content, kContextDataKey), same(missing));
    });

    test('throws for a non-string map key in debug mode', () {
      expect(
        () => ContextSnapshot.of(
          <String, Object?>{
            'trial': <Object, Object?>{
              7: 'unsupported',
            },
          },
          policy: _throwingPolicy(),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message.toString(),
            'message',
            contains('context.trial'),
          ),
        ),
      );
    });

    test('reports and omits invalid values when throwing is disabled', () {
      final errors = <FlutterErrorDetails>[];
      final content = DynamicContent();
      final snapshot = ContextSnapshot.of(
        <String, Object?>{
          'trial': <String, Object?>{
            'name': 'starter',
            'startedAt': DateTime.utc(2025),
          },
        },
        policy: _reportingPolicy(errors),
      );

      content.update(kContextDataKey, snapshot.value);

      expect(
        _readKey(content, kContextDataKey),
        <String, Object?>{
          'trial': <String, Object?>{
            'name': 'starter',
          },
        },
      );
      expect(errors.length, equals(1));
      expect(errors.single.library, 'restage');
      expect(
        errors.single.exception.toString(),
        contains('context.<map value>.<map value>'),
      );
    });

    final hostileTypeCases = <({String name, Object Function() create})>[
      (name: 'runtime type access', create: _HostileRuntimeType.new),
      (name: 'type text rendering', create: _HostileTypeText.new),
    ];

    for (final entry in hostileTypeCases) {
      test('throwing value diagnostics avoid ${entry.name}', () {
        Object? failure;
        try {
          ContextSnapshot.of(
            <String, Object?>{
              'hostile': entry.create(),
            },
            policy: _throwingPolicy(),
          );
        } on Object catch (error) {
          failure = error;
        }

        expect(failure, isA<ArgumentError>());
        expect(
          (failure! as ArgumentError).message,
          'Invalid render-context value at context.hostile: Object is not '
          'supported. Supported types: String, int, double, bool, List, and '
          'Map with String keys.',
        );
      });

      test('reporting value diagnostics avoid ${entry.name}', () {
        final errors = <FlutterErrorDetails>[];
        final snapshot = ContextSnapshot.of(
          <String, Object?>{
            'safe': 'published',
            'hostile': entry.create(),
          },
          policy: _reportingPolicy(errors),
        );

        expect(snapshot.value, <String, Object?>{'safe': 'published'});
        expect(errors, hasLength(1));
        expect(
          errors.single.exception,
          'Invalid render-context value at context.<map value>: Object is not '
          'supported. Supported types: String, int, double, bool, List, and '
          'Map with String keys.',
        );
        expect(errors.single.exception, isNot(contains(_hostTypeSentinel)));
      });

      test('throwing key diagnostics avoid ${entry.name}', () {
        Object? failure;
        try {
          ContextSnapshot.of(
            <String, Object?>{
              'entries': <Object?, Object?>{
                entry.create(): 'hidden',
              },
            },
            policy: _throwingPolicy(),
          );
        } on Object catch (error) {
          failure = error;
        }

        expect(failure, isA<ArgumentError>());
        expect(
          (failure! as ArgumentError).message,
          'Invalid render-context key at context.entries: keys must be String, '
          'but found Object.',
        );
      });

      test('reporting key diagnostics avoid ${entry.name}', () {
        final errors = <FlutterErrorDetails>[];
        final snapshot = ContextSnapshot.of(
          <String, Object?>{
            'safe': 'published',
            'entries': <Object?, Object?>{
              entry.create(): 'hidden',
              'visible': 'published',
            },
          },
          policy: _reportingPolicy(errors),
        );

        expect(
          snapshot.value,
          <String, Object?>{
            'safe': 'published',
            'entries': <String, Object?>{'visible': 'published'},
          },
        );
        expect(errors, hasLength(1));
        expect(
          errors.single.exception,
          'Invalid render-context key at context.<map value>: keys must be '
          'String, but found Object.',
        );
        expect(errors.single.exception, isNot(contains(_hostTypeSentinel)));
      });
    }

    final reportingPathCases = <({
      String name,
      Object? Function() value,
      String message,
      String path,
    })>[
      (
        name: 'unsupported values',
        value: () => Object(),
        message: 'Object is not supported',
        path: 'context.<map value>',
      ),
      (
        name: 'non-finite values',
        value: () => double.nan,
        message: 'non-finite doubles are not supported',
        path: 'context.<map value>',
      ),
      (
        name: 'cyclic collections',
        value: _cyclicContextValue,
        message: 'cyclic collections are not supported',
        path: 'context.<map value>.<map value>',
      ),
      (
        name: 'unreadable maps',
        value: () => _UnreadableMap(_MapReadFailure.keys),
        message: 'collection could not be read',
        path: 'context.<map value>',
      ),
      (
        name: 'unreadable lists',
        value: () => _UnreadableList(_ListReadFailure.length),
        message: 'collection could not be read',
        path: 'context.<map value>',
      ),
      (
        name: 'nesting overflow',
        value: () => _contextAtDepth(33),
        message: 'nesting exceeds 32 levels',
        path: 'context.<map value>.<map value>',
      ),
      (
        name: 'retained-node overflow',
        value: _oversizedContextValue,
        message: '10000 retained normalized nodes',
        path: 'context.<map value>.<map value>',
      ),
      (
        name: 'inspection overflow',
        value: () => _FiniteNullList(100000),
        message: '100000 inspected map entries or list elements',
        path: 'context.<map value>',
      ),
      (
        name: 'non-string keys',
        value: () => <Object?, Object?>{7: 'unsupported'},
        message: 'keys must be String, but found int',
        path: 'context.<map value>',
      ),
      (
        name: 'list positions',
        value: () => <Object?>[Object()],
        message: 'Object is not supported',
        path: 'context.<map value>[0]',
      ),
    ];

    for (final entry in reportingPathCases) {
      test('reporting paths hide map keys for ${entry.name}', () {
        final errors = <FlutterErrorDetails>[];

        ContextSnapshot.of(
          <String, Object?>{_sensitiveContextKey: entry.value()},
          policy: _reportingPolicy(errors),
        );

        expect(errors, hasLength(1));
        final message = errors.single.exception.toString();
        expect(message, contains(entry.path));
        expect(message, contains(entry.message));
        expect(message, isNot(contains(_sensitiveContextKey)));
      });
    }

    test('published context does not retain host collection references', () {
      final content = DynamicContent();
      final host = _originalProfile();

      populateContextData(content, host);
      _mutateProfile(host);

      expect(_readKey(content, kContextDataKey), _originalProfile());
    });

    test('snapshots do not retain source collection references', () {
      final source = _originalProfile();
      final snapshot = ContextSnapshot.of(source);

      _mutateProfile(source);

      expect(snapshot.value, _originalProfile());
    });

    test('reuses the previous snapshot for equal content', () {
      final snapshot = ContextSnapshot.of(
        <String, Object?>{
          'profile': <String, Object?>{
            'tags': <Object?>['new', 'trial'],
          },
        },
      );
      final reused = ContextSnapshot.of(
        <String, Object?>{
          'profile': <String, Object?>{
            'tags': <Object?>['new', 'trial'],
          },
        },
        previous: snapshot,
      );

      expect(identical(reused, snapshot), isTrue);
    });

    test('creates a new snapshot for a deep scalar change', () {
      final snapshot = ContextSnapshot.of(
        <String, Object?>{
          'profile': <String, Object?>{
            'items': <Object?>[
              <String, Object?>{
                'count': 1,
              },
            ],
          },
        },
      );
      final changed = ContextSnapshot.of(
        <String, Object?>{
          'profile': <String, Object?>{
            'items': <Object?>[
              <String, Object?>{
                'count': 2,
              },
            ],
          },
        },
        previous: snapshot,
      );

      expect(identical(changed, snapshot), isFalse);
      expect(
        snapshot.value,
        <String, Object?>{
          'profile': <String, Object?>{
            'items': <Object?>[
              <String, Object?>{
                'count': 1,
              },
            ],
          },
        },
      );
    });

    test('compares maps deeply and preserves list order', () {
      final first = ContextSnapshot.of(
        <String, Object?>{
          'outer': <String, Object?>{
            'first': 'one',
            'second': <Object?>['a', 'b'],
          },
        },
      );
      final reorderedMap = ContextSnapshot.of(
        <String, Object?>{
          'outer': <String, Object?>{
            'second': <Object?>['a', 'b'],
            'first': 'one',
          },
        },
      );
      final reorderedList = ContextSnapshot.of(
        <String, Object?>{
          'outer': <String, Object?>{
            'first': 'one',
            'second': <Object?>['b', 'a'],
          },
        },
      );

      expect(first, equals(reorderedMap));
      expect(first.hashCode, reorderedMap.hashCode);
      expect(first, isNot(equals(reorderedList)));
    });

    test('publishes an int-to-double transition', () {
      final initial = ContextSnapshot.of(<String, Object?>{'value': 1});
      final changed = ContextSnapshot.of(
        <String, Object?>{'value': 1.0},
        previous: initial,
      );
      final content = _CountingContent();
      final publisher = ContextPublisher(content);

      expect(identical(changed, initial), isFalse);
      publisher.publishSnapshot(initial);
      expect(content.updates, equals(1));
      publisher.publishSnapshot(changed);
      expect(content.updates, equals(2));
    });

    test('canonicalizes signed zero in snapshots', () {
      final negativeZero = ContextSnapshot.of(
        <String, Object?>{'value': -0.0},
      );
      final positiveZero = ContextSnapshot.of(
        <String, Object?>{'value': 0.0},
      );

      expect(negativeZero, equals(positiveZero));
      expect(negativeZero.hashCode, positiveZero.hashCode);
    });

    test('canonicalizes signed zero in the stored leaf value', () {
      final content = DynamicContent();
      final publisher = ContextPublisher(content);
      void listener(Object _) {}

      publisher.publish(<String, Object?>{'value': -0.0});
      final leaf = content.subscribe(
        <Object>[kContextDataKey, 'value'],
        listener,
      );
      content.unsubscribe(<Object>[kContextDataKey, 'value'], listener);

      expect((leaf as double).isNegative, isFalse);
    });

    test('skips a signed-zero transition for a leaf subscriber', () {
      final content = _CountingContent();
      final publisher = ContextPublisher(content);
      Object leaf = missing;
      void listener(Object value) {
        leaf = value;
      }

      content.subscribe(<Object>[kContextDataKey, 'value'], listener);
      publisher.publish(<String, Object?>{'value': 0.0});
      expect(content.updates, equals(1));
      publisher.publish(<String, Object?>{'value': -0.0});

      expect(content.updates, equals(1));
      expect(leaf, 0.0);
      content.unsubscribe(<Object>[kContextDataKey, 'value'], listener);
    });

    test('rejects non-finite double leaves under both policies', () {
      for (final value in <double>[
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        expect(
          () => ContextSnapshot.of(
            <String, Object?>{'value': value},
            policy: _throwingPolicy(),
          ),
          throwsA(
            isA<ArgumentError>().having(
              (error) => error.message.toString(),
              'message',
              contains('context.value'),
            ),
          ),
        );

        final errors = <FlutterErrorDetails>[];
        final snapshot = ContextSnapshot.of(
          <String, Object?>{'value': value},
          policy: _reportingPolicy(errors),
        );

        expect(snapshot.value, <String, Object?>{});
        expect(errors.length, equals(1));
        expect(
          errors.single.exception.toString(),
          contains('context.<map value>'),
        );
      }
    });

    test('rejects cyclic collections under both policies', () {
      final selfReferentialMap = <String, Object?>{};
      selfReferentialMap['self'] = selfReferentialMap;
      final selfReferentialList = <Object?>[];
      selfReferentialList.add(selfReferentialList);

      for (final value in <Object?>[
        selfReferentialMap,
        selfReferentialList,
      ]) {
        final raw = <String, Object?>{'value': value};
        expect(
          () => ContextSnapshot.of(raw, policy: _throwingPolicy()),
          throwsA(
            isA<ArgumentError>().having(
              (error) => error.message.toString(),
              'message',
              contains('context.value'),
            ),
          ),
        );

        final errors = <FlutterErrorDetails>[];
        final snapshot = ContextSnapshot.of(
          raw,
          policy: _reportingPolicy(errors),
        );
        expect(snapshot.value, isEmpty);
        expect(errors.length, equals(1));
        expect(
          errors.single.exception.toString(),
          contains('context.<map value>'),
        );

        final content = _CountingContent();
        final publisher = ContextPublisher(content);
        expect(
          () => publisher.publish(raw),
          throwsA(isA<ArgumentError>()),
        );
        expect(content.updates, equals(0));
        expect(_readKey(content, kContextDataKey), same(missing));
      }
    });

    test('omits an entire self-referential nested collection', () {
      final account = <String, Object?>{
        'prefix': 'first',
        'suffix': 'last',
      };
      account['firstBackEdge'] = account;
      account['secondBackEdge'] = account;
      final errors = <FlutterErrorDetails>[];

      final snapshot = ContextSnapshot.of(
        <String, Object?>{
          'before': 'retained',
          'account': account,
          'after': 'retained',
        },
        policy: _reportingPolicy(errors),
      );

      expect(snapshot.value, <String, Object?>{
        'before': 'retained',
        'after': 'retained',
      });
      expect(errors, hasLength(1));
      expect(errors.single.exception.toString(), contains('cyclic'));
    });

    test('omits mutually cyclic collections with one diagnostic', () {
      final first = <String, Object?>{
        'prefix': 'first',
        'suffix': 'last',
      };
      final second = <String, Object?>{
        'prefix': 'first',
        'suffix': 'last',
      };
      first['peer'] = second;
      second['firstBackEdge'] = first;
      second['secondBackEdge'] = first;
      final errors = <FlutterErrorDetails>[];

      final snapshot = ContextSnapshot.of(
        <String, Object?>{
          'safe': 'retained',
          'cycle': first,
        },
        policy: _reportingPolicy(errors),
      );

      expect(snapshot.value, <String, Object?>{'safe': 'retained'});
      expect(errors, hasLength(1));
    });

    test('a root cycle omits every root value with one diagnostic', () {
      final raw = <String, Object?>{
        'prefix': 'first',
        'suffix': 'last',
      };
      raw['firstBackEdge'] = raw;
      raw['secondBackEdge'] = raw;
      final errors = <FlutterErrorDetails>[];

      final snapshot = ContextSnapshot.of(
        raw,
        policy: _reportingPolicy(errors),
      );

      expect(snapshot.value, isEmpty);
      expect(errors, hasLength(1));
    });

    test('reports a cyclic collection identity once per normalization', () {
      final cyclic = <String, Object?>{
        'prefix': 'first',
        'suffix': 'last',
      };
      cyclic['firstBackEdge'] = cyclic;
      cyclic['secondBackEdge'] = cyclic;
      final errors = <FlutterErrorDetails>[];

      final snapshot = ContextSnapshot.of(
        <String, Object?>{
          'first': cyclic,
          'second': cyclic,
          'safe': 'retained',
        },
        policy: _reportingPolicy(errors),
      );

      expect(snapshot.value, <String, Object?>{'safe': 'retained'});
      expect(errors, hasLength(1));
    });

    test('deep-copies repeated acyclic collection references', () {
      final shared = <String, Object?>{
        'label': 'original',
        'items': <Object?>['first'],
      };

      final snapshot = ContextSnapshot.of(
        <String, Object?>{
          'first': shared,
          'second': shared,
        },
      );
      shared['label'] = 'changed';
      (shared['items']! as List<Object?>).add('second');

      final first = snapshot.value['first']! as Map<String, Object?>;
      final second = snapshot.value['second']! as Map<String, Object?>;
      expect(first, <String, Object?>{
        'label': 'original',
        'items': <Object?>['first'],
      });
      expect(second, first);
      expect(identical(first, second), isFalse);
    });

    test('publishes fresh context after omitting a cyclic collection', () {
      final cyclic = <String, Object?>{'prefix': 'discarded'};
      cyclic['self'] = cyclic;
      final errors = <FlutterErrorDetails>[];
      final content = _CountingContent();
      final publisher = ContextPublisher(
        content,
        normalizationPolicy: _reportingPolicy(errors),
      );

      publisher.publish(<String, Object?>{
        'safe': 'first',
        'cyclic': cyclic,
      });
      expect(_readKey(content, kContextDataKey), <String, Object?>{
        'safe': 'first',
      });

      publisher.publish(<String, Object?>{'safe': 'second'});
      expect(_readKey(content, kContextDataKey), <String, Object?>{
        'safe': 'second',
      });
      expect(errors, hasLength(1));
      expect(content.updates, 2);
    });

    test('accepts context nested at the depth limit', () {
      final snapshot = ContextSnapshot.of(
        _contextAtDepth(32),
        policy: _throwingPolicy(),
      );

      expect(snapshot.value.containsKey('child'), isTrue);
    });

    test('rejects context beyond the depth limit', () {
      final raw = _contextAtDepth(33);

      expect(
        () => ContextSnapshot.of(raw, policy: _throwingPolicy()),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message.toString(),
            'message',
            contains('context.child'),
          ),
        ),
      );

      final errors = <FlutterErrorDetails>[];
      final snapshot = ContextSnapshot.of(
        raw,
        policy: _reportingPolicy(errors),
      );
      Map<String, Object?> current = snapshot.value;
      for (var index = 0; index < 32; index += 1) {
        current = current['child']! as Map<String, Object?>;
      }
      expect(current.containsKey('child'), isFalse);
      expect(errors.length, equals(1));
      expect(
        errors.single.exception.toString(),
        contains('context.<map value>'),
      );
    });

    test('accepts exactly 10000 retained normalized nodes', () {
      final raw = <String, Object?>{
        for (var index = 0; index < 9999; index += 1) 'value$index': index,
      };

      final snapshot = ContextSnapshot.of(raw, policy: _throwingPolicy());

      expect(snapshot.value.length, 9999);
      expect(snapshot.value['value9998'], 9998);
    });

    test('duplicate keys consume capacity only for the committed value', () {
      final snapshot = ContextSnapshot.of(
        <String, Object?>{
          for (var index = 0; index < 9997; index += 1) 'item$index': index,
          'replacement': _DuplicateKeyMap(<Object?>['first', 'second']),
        },
        policy: _throwingPolicy(),
      );

      expect(snapshot.value, hasLength(9998));
      expect(snapshot.value['item9996'], 9996);
      expect(snapshot.value['replacement'], <String, Object?>{
        'value': 'second',
      });
    });

    test('duplicate keys refund differently sized normalized subtrees', () {
      final snapshot = ContextSnapshot.of(
        <String, Object?>{
          'replacement': _DuplicateKeyMap(<Object?>[
            <String, Object?>{
              'items': <Object?>['first', 'second'],
              'label': 'discarded',
            },
            <String, Object?>{'label': 'retained'},
          ]),
        },
        policy: _throwingPolicy(),
      );

      expect(snapshot.value['replacement'], <String, Object?>{
        'value': <String, Object?>{'label': 'retained'},
      });
    });

    test('null and invalid duplicate replacements remove earlier values', () {
      final errors = <FlutterErrorDetails>[];
      final snapshot = ContextSnapshot.of(
        <String, Object?>{
          'nullReplacement': _DuplicateKeyMap(<Object?>['discarded', null]),
          'invalidReplacement':
              _DuplicateKeyMap(<Object?>['discarded', Object()]),
        },
        policy: _reportingPolicy(errors),
      );

      expect(snapshot.value, <String, Object?>{
        'nullReplacement': <String, Object?>{},
        'invalidReplacement': <String, Object?>{},
      });
      expect(errors, hasLength(1));
    });

    test('failed duplicate replacement rolls back its retained subtree', () {
      final errors = <FlutterErrorDetails>[];
      final snapshot = ContextSnapshot.of(
        <String, Object?>{
          'replacement': _DuplicateKeyMap(<Object?>[
            <String, Object?>{'label': 'discarded'},
            _UnreadableList(_ListReadFailure.element),
          ]),
          'retained': <String, Object?>{
            for (var index = 0; index < 9997; index += 1) 'item$index': index,
          },
        },
        policy: _reportingPolicy(errors),
      );

      expect(snapshot.value['replacement'], <String, Object?>{});
      expect(snapshot.value['retained'], isA<Map<String, Object?>>());
      expect(
        snapshot.value['retained']! as Map<String, Object?>,
        hasLength(9997),
      );
      expect(errors, hasLength(1));
    });

    test('omitted values consume no normalized capacity', () {
      final errors = <FlutterErrorDetails>[];
      final raw = <String, Object?>{
        for (var index = 0; index < 9999; index += 1) 'value$index': index,
        'nullValue': null,
        'invalidValue': Object(),
      };

      final snapshot = ContextSnapshot.of(
        raw,
        policy: _reportingPolicy(errors),
      );

      expect(snapshot.value, hasLength(9999));
      expect(snapshot.value['value9998'], 9998);
      expect(errors, hasLength(1));
      expect(
        errors.single.exception.toString(),
        isNot(contains('10000 retained normalized nodes')),
      );
    });

    test('rejects 10001 retained normalized nodes under both policies', () {
      final raw = <String, Object?>{
        for (var index = 0; index < 10000; index += 1) 'value$index': index,
      };

      expect(
        () => ContextSnapshot.of(raw, policy: _throwingPolicy()),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message.toString(),
            'message',
            contains('10000 retained normalized nodes'),
          ),
        ),
      );

      final errors = <FlutterErrorDetails>[];
      final snapshot = ContextSnapshot.of(
        raw,
        policy: _reportingPolicy(errors),
      );
      expect(snapshot.value, isEmpty);
      expect(errors, hasLength(1));
    });

    test('an oversized nested collection preserves adjacent values', () {
      final errors = <FlutterErrorDetails>[];
      final snapshot = ContextSnapshot.of(
        <String, Object?>{
          'before': 'retained',
          'oversized': <String, Object?>{
            for (var index = 0; index < 10000; index += 1) 'value$index': index,
          },
          'after': 'retained',
        },
        policy: _reportingPolicy(errors),
      );

      expect(snapshot.value, <String, Object?>{
        'before': 'retained',
        'after': 'retained',
      });
      expect(errors, hasLength(1));
      expect(
        errors.single.exception.toString(),
        contains('10000 retained normalized nodes'),
      );
    });

    test('nested failure restores normalized capacity', () {
      final errors = <FlutterErrorDetails>[];
      final snapshot = ContextSnapshot.of(
        <String, Object?>{
          'discarded': <String, Object?>{
            for (var index = 0; index < 10000; index += 1) 'value$index': index,
          },
          'retained': <String, Object?>{
            for (var index = 0; index < 9998; index += 1) 'value$index': index,
          },
        },
        policy: _reportingPolicy(errors),
      );

      expect(snapshot.value.keys, <String>['retained']);
      final retained = snapshot.value['retained']! as Map<String, Object?>;
      expect(retained, hasLength(9998));
      expect(retained['value9997'], 9997);
      expect(errors, hasLength(1));
    });

    test('cycle failure restores normalized capacity', () {
      final cyclic = <String, Object?>{
        for (var index = 0; index < 9998; index += 1) 'value$index': index,
      };
      cyclic['self'] = cyclic;
      final errors = <FlutterErrorDetails>[];

      final snapshot = ContextSnapshot.of(
        <String, Object?>{
          'discarded': cyclic,
          'retained': <String, Object?>{
            for (var index = 0; index < 9998; index += 1) 'value$index': index,
          },
        },
        policy: _reportingPolicy(errors),
      );

      expect(snapshot.value.keys, <String>['retained']);
      expect(
        snapshot.value['retained']! as Map<String, Object?>,
        hasLength(9998),
      );
      expect(errors, hasLength(1));
      expect(errors.single.exception.toString(), contains('cyclic'));
    });

    test('accepts exactly 100000 inspected collection entries', () {
      for (final value in <Object?>[
        _FiniteNullMap(100000),
        _FiniteNullList(99999),
      ]) {
        final errors = <FlutterErrorDetails>[];
        final snapshot = value is Map<String, Object?>
            ? ContextSnapshot.of(value, policy: _reportingPolicy(errors))
            : ContextSnapshot.of(
                <String, Object?>{'value': value},
                policy: _reportingPolicy(errors),
              );

        expect(errors, isEmpty);
        if (value is List<Object?>) {
          expect(snapshot.value, <String, Object?>{'value': <Object?>[]});
        } else {
          expect(snapshot.value, isEmpty);
        }
      }
    });

    test('rejects 100001 inspected collection entries', () {
      for (final value in <Object?>[
        _FiniteNullMap(100001),
        _FiniteNullList(100000),
      ]) {
        expect(
          () => value is Map<String, Object?>
              ? ContextSnapshot.of(value, policy: _throwingPolicy())
              : ContextSnapshot.of(
                  <String, Object?>{'value': value},
                  policy: _throwingPolicy(),
                ),
          throwsA(
            isA<ArgumentError>().having(
              (error) => error.message.toString(),
              'message',
              contains('100000 inspected map entries or list elements'),
            ),
          ),
        );

        final errors = <FlutterErrorDetails>[];
        final snapshot = value is Map<String, Object?>
            ? ContextSnapshot.of(value, policy: _reportingPolicy(errors))
            : ContextSnapshot.of(
                <String, Object?>{'value': value},
                policy: _reportingPolicy(errors),
              );

        expect(snapshot.value, isEmpty);
        expect(errors, hasLength(1));
        expect(
          errors.single.exception.toString(),
          contains('100000 inspected map entries or list elements'),
        );
      }
    });

    test('converts unreadable maps to stable contract failures', () {
      for (final failure in _MapReadFailure.values) {
        expect(
          () => ContextSnapshot.of(
            <String, Object?>{'account': _UnreadableMap(failure)},
            policy: _throwingPolicy(),
          ),
          throwsA(
            isA<ArgumentError>().having(
              (error) => error.message.toString(),
              'message',
              contains('context.account'),
            ),
          ),
        );
      }
    });

    test('omits an unreadable map without retaining a partial prefix', () {
      for (final failure in _MapReadFailure.values) {
        final errors = <FlutterErrorDetails>[];
        final snapshot = ContextSnapshot.of(
          <String, Object?>{
            'safe': 'retained',
            'account': _UnreadableMap(failure),
          },
          policy: _reportingPolicy(errors),
        );

        expect(snapshot.value, <String, Object?>{'safe': 'retained'});
        expect(errors, hasLength(1));
      }
    });

    test('converts unreadable lists to stable contract failures', () {
      for (final failure in _ListReadFailure.values) {
        expect(
          () => ContextSnapshot.of(
            <String, Object?>{'items': _UnreadableList(failure)},
            policy: _throwingPolicy(),
          ),
          throwsA(
            isA<ArgumentError>().having(
              (error) => error.message.toString(),
              'message',
              contains('context.items'),
            ),
          ),
        );
      }
    });

    test('omits unreadable and concurrently shrinking lists completely', () {
      for (final value in <List<Object?>>[
        for (final failure in _ListReadFailure.values) _UnreadableList(failure),
        _ShrinkingList(),
      ]) {
        final errors = <FlutterErrorDetails>[];
        final snapshot = ContextSnapshot.of(
          <String, Object?>{'safe': 'retained', 'items': value},
          policy: _reportingPolicy(errors),
        );

        expect(snapshot.value, <String, Object?>{'safe': 'retained'});
        expect(errors, hasLength(1));
      }
    });

    test('bounds endlessly yielding map and list collections', () {
      for (final value in <Object?>[_EndlessMap(), _GrowingList()]) {
        final errors = <FlutterErrorDetails>[];
        final snapshot = ContextSnapshot.of(
          <String, Object?>{'stream': value},
          policy: _reportingPolicy(errors),
        );

        expect(snapshot.value, isEmpty);
        expect(errors, hasLength(1));
        expect(
          errors.single.exception.toString(),
          contains('100000 inspected map entries or list elements'),
        );
      }
    });

    test('publishes fresh context after an unreadable collection', () {
      final errors = <FlutterErrorDetails>[];
      final content = _CountingContent();
      final publisher = ContextPublisher(
        content,
        normalizationPolicy: _reportingPolicy(errors),
      );

      publisher.publish(<String, Object?>{
        'safe': 'first',
        'items': _UnreadableList(_ListReadFailure.element),
      });
      expect(_readKey(content, kContextDataKey), <String, Object?>{
        'safe': 'first',
      });

      publisher.publish(<String, Object?>{
        'safe': 'second',
        'items': <Object?>['complete'],
      });
      expect(_readKey(content, kContextDataKey), <String, Object?>{
        'safe': 'second',
        'items': <Object?>['complete'],
      });
      expect(errors, hasLength(1));
      expect(content.updates, 2);
    });

    test('skips equal but non-identical snapshots', () {
      final first = ContextSnapshot.of(
        <String, Object?>{
          'nested': <String, Object?>{'a': 1},
        },
      );
      final second = ContextSnapshot.of(
        <String, Object?>{
          'nested': <String, Object?>{'a': 1},
        },
      );
      final content = _CountingContent();
      final publisher = ContextPublisher(content);

      expect(identical(first, second), isFalse);
      publisher.publishSnapshot(first);
      expect(content.updates, equals(1));
      publisher.publishSnapshot(second);
      expect(content.updates, equals(1));
      expect(publisher.lastPublished, same(first));
    });

    test('skips equal raw maps', () {
      final content = _CountingContent();
      final publisher = ContextPublisher(content);

      publisher.publish(
        <String, Object?>{
          'nested': <String, Object?>{'a': 1},
        },
      );
      expect(content.updates, equals(1));
      publisher.publish(
        <String, Object?>{
          'nested': <String, Object?>{'a': 1},
        },
      );
      expect(content.updates, equals(1));
    });

    test('tracks whether the target may expose non-empty host context', () {
      final content = _CountingContent();
      final publisher = ContextPublisher(content);

      expect(publisher.mayExposeNonEmptyHostContext, isFalse);
      publisher.publish(<String, Object?>{});
      expect(publisher.mayExposeNonEmptyHostContext, isFalse);
      publisher.publish(<String, Object?>{'secret': 'local'});
      expect(publisher.mayExposeNonEmptyHostContext, isTrue);
      publisher.publish(null);
      expect(publisher.mayExposeNonEmptyHostContext, isFalse);

      void throwOnUpdate(Object _) => throw StateError('listener failure');
      content.subscribe(<Object>[kContextDataKey], throwOnUpdate);
      expect(
        () => publisher.publish(<String, Object?>{'secret': 'unknown'}),
        throwsA(isA<StateError>()),
      );
      expect(publisher.mayExposeNonEmptyHostContext, isTrue);
      content.unsubscribe(<Object>[kContextDataKey], throwOnUpdate);

      publisher.publish(null);
      expect(publisher.mayExposeNonEmptyHostContext, isFalse);
    });

    test('serializes reentrant publish requests', () {
      final content = _CountingContent();
      final publisher = ContextPublisher(content);
      final first = ContextSnapshot.of(<String, Object?>{'value': 'A'});
      final second = ContextSnapshot.of(<String, Object?>{'value': 'B'});
      var reentered = false;
      void listener(Object _) {
        if (!reentered) {
          reentered = true;
          publisher.publishSnapshot(second);
        }
      }

      content.subscribe(<Object>[kContextDataKey], listener);
      publisher.publishSnapshot(first);

      expect(_readKey(content, kContextDataKey), second.value);
      expect(publisher.lastPublished, same(second));
      expect(content.updates, equals(2));

      publisher.publishSnapshot(first);
      expect(content.updates, equals(3));
      content.unsubscribe(<Object>[kContextDataKey], listener);
    });

    test('serializes reentrant publish withdrawals', () {
      final content = _CountingContent();
      final publisher = ContextPublisher(content);
      final snapshot = ContextSnapshot.of(<String, Object?>{'value': 'A'});
      var reentered = false;
      void listener(Object _) {
        if (!reentered) {
          reentered = true;
          publisher.publishSnapshot(null);
        }
      }

      content.subscribe(<Object>[kContextDataKey], listener);
      publisher.publishSnapshot(snapshot);

      expect(_readKey(content, kContextDataKey), <String, Object?>{});
      expect(publisher.lastPublished, isNull);
      expect(content.updates, equals(2));
      content.unsubscribe(<Object>[kContextDataKey], listener);
    });

    test('serializes reentrant withdrawals followed by publishing', () {
      final content = _CountingContent();
      final publisher = ContextPublisher(content);
      final first = ContextSnapshot.of(<String, Object?>{'value': 'A'});
      final second = ContextSnapshot.of(<String, Object?>{'value': 'B'});
      var reentered = false;
      void listener(Object _) {
        if (!reentered) {
          reentered = true;
          publisher.publishSnapshot(second);
        }
      }

      publisher.publishSnapshot(first);
      content.subscribe(<Object>[kContextDataKey], listener);
      publisher.publishSnapshot(null);

      expect(_readKey(content, kContextDataKey), second.value);
      expect(publisher.lastPublished, same(second));
      expect(content.updates, equals(3));
      content.unsubscribe(<Object>[kContextDataKey], listener);
    });

    test('serializes reentrant leaf publish requests', () {
      final content = _CountingContent();
      final publisher = ContextPublisher(content);
      final first = ContextSnapshot.of(<String, Object?>{'value': 'A'});
      final second = ContextSnapshot.of(<String, Object?>{'value': 'B'});
      var reentered = false;
      void listener(Object _) {
        if (!reentered) {
          reentered = true;
          publisher.publishSnapshot(second);
        }
      }

      content.subscribe(<Object>[kContextDataKey, 'value'], listener);
      publisher.publishSnapshot(first);

      expect(_readKey(content, kContextDataKey), second.value);
      expect(publisher.lastPublished, same(second));
      expect(content.updates, equals(2));

      publisher.publishSnapshot(first);
      expect(content.updates, equals(3));
      content.unsubscribe(<Object>[kContextDataKey, 'value'], listener);
    });

    test('drains multiple reentrant publications in FIFO order', () {
      final content = _CountingContent();
      final publisher = ContextPublisher(content);
      final first = ContextSnapshot.of(<String, Object?>{'value': 'A'});
      final second = ContextSnapshot.of(<String, Object?>{'value': 'B'});
      final third = ContextSnapshot.of(<String, Object?>{'value': 'C'});
      var reentered = false;
      void listener(Object _) {
        if (!reentered) {
          reentered = true;
          publisher.publishSnapshot(second);
          publisher.publishSnapshot(third);
        }
      }

      content.subscribe(<Object>[kContextDataKey], listener);
      publisher.publishSnapshot(first);

      expect(_readKey(content, kContextDataKey), third.value);
      expect(publisher.lastPublished, same(third));
      expect(content.updates, equals(3));
      content.unsubscribe(<Object>[kContextDataKey], listener);
    });

    test('clears later queued work after a reentrant update fails', () {
      final content = _CountingContent();
      final publisher = ContextPublisher(content);
      final first = ContextSnapshot.of(<String, Object?>{'value': 'A'});
      final failing = ContextSnapshot.of(<String, Object?>{'value': 'B'});
      final stale = ContextSnapshot.of(<String, Object?>{'value': 'C'});
      final fresh = ContextSnapshot.of(<String, Object?>{'value': 'D'});
      var queued = false;
      void listener(Object value) {
        final current = (value as Map<Object?, Object?>)['value'];
        if (current == 'A' && !queued) {
          queued = true;
          publisher.publishSnapshot(failing);
          publisher.publishSnapshot(stale);
        } else if (current == 'B') {
          throw StateError('listener failure');
        }
      }

      content.subscribe(<Object>[kContextDataKey], listener);
      expect(
        () => publisher.publishSnapshot(first),
        throwsA(isA<StateError>()),
      );

      expect(_readKey(content, kContextDataKey), failing.value);
      expect(publisher.lastPublished, isNull);
      expect(content.updates, equals(2));

      publisher.publishSnapshot(fresh);
      expect(_readKey(content, kContextDataKey), fresh.value);
      expect(publisher.lastPublished, same(fresh));
      expect(content.updates, equals(3));
      content.unsubscribe(<Object>[kContextDataKey], listener);
    });

    test('reserves raw publications before synchronous reporting', () {
      final content = _CountingContent();
      final reports = <FlutterErrorDetails>[];
      final observed = <Object?>[];
      final first = ContextSnapshot.of(<String, Object?>{'value': 'A'});
      final third = ContextSnapshot.of(<String, Object?>{'value': 'C'});
      var rawReturned = false;
      late final ContextPublisher publisher;
      publisher = ContextPublisher(
        content,
        normalizationPolicy: ContextNormalizationPolicy(
          throwOnViolation: false,
          reportError: (details) {
            reports.add(details);
            expect(rawReturned, isFalse);
            publisher.publishSnapshot(third);
          },
        ),
      );
      var reentered = false;
      void listener(Object value) {
        observed.add((value as Map<Object?, Object?>)['value']);
        if (!reentered) {
          reentered = true;
          final raw = <String, Object?>{
            'value': 'B',
            'invalid': Object(),
          };
          publisher.publish(raw);
          raw['value'] = 'mutated';
          rawReturned = true;
        }
      }

      content.subscribe(<Object>[kContextDataKey], listener);
      publisher.publishSnapshot(first);

      expect(reports.length, equals(1));
      expect(observed, <Object?>['A', 'B', 'C']);
      expect(_readKey(content, kContextDataKey), third.value);
      expect(publisher.lastPublished, same(third));
      expect(content.updates, equals(3));
      content.unsubscribe(<Object>[kContextDataKey], listener);
    });

    test('withdraws only after context was published', () {
      final content = _CountingContent();
      final publisher = ContextPublisher(content);
      final snapshot = ContextSnapshot.of(<String, Object?>{'a': 1});

      publisher.publish(null);
      expect(content.updates, equals(0));
      publisher.publishSnapshot(snapshot);
      expect(content.updates, equals(1));
      publisher.publishSnapshot(null);
      expect(content.updates, equals(2));
      expect(_readKey(content, kContextDataKey), <String, Object?>{});
      expect(publisher.lastPublished, isNull);
      publisher.publishSnapshot(null);
      expect(content.updates, equals(2));
    });

    test('withdraws an empty published snapshot without another update', () {
      final content = _CountingContent();
      final publisher = ContextPublisher(content);

      publisher.publishSnapshot(ContextSnapshot.of(<String, Object?>{}));
      expect(content.updates, equals(1));
      publisher.publishSnapshot(null);
      expect(content.updates, equals(1));
      expect(publisher.lastPublished, isNull);
    });

    test('a failed update does not leave the prior value skippable', () {
      // The target keeps the failed value, so the previous one must republish.
      final content = _CountingContent();
      final publisher = ContextPublisher(content);
      final first = ContextSnapshot.of(<String, Object?>{
        'nested': <String, Object?>{'a': 1},
      });
      final second = ContextSnapshot.of(<String, Object?>{
        'nested': <String, Object?>{'a': 2},
      });
      var throwOnNext = false;
      void listener(Object _) {
        if (throwOnNext) {
          throwOnNext = false;
          throw StateError('listener failure');
        }
      }

      content.subscribe(<Object>[kContextDataKey], listener);
      publisher.publishSnapshot(first);
      expect(content.updates, equals(1));
      expect(publisher.lastPublished, same(first));

      throwOnNext = true;
      expect(
        () => publisher.publishSnapshot(second),
        throwsA(isA<StateError>()),
      );
      expect(content.updates, equals(2));
      expect(publisher.lastPublished, isNull);

      publisher.publishSnapshot(first);
      expect(content.updates, equals(3));
      expect(publisher.lastPublished, same(first));
      content.unsubscribe(<Object>[kContextDataKey], listener);
    });

    test('republishes after a subscriber throws during an update', () {
      final content = _CountingContent();
      final publisher = ContextPublisher(content);
      final snapshot = ContextSnapshot.of(
        <String, Object?>{
          'nested': <String, Object?>{'a': 1},
        },
      );
      var throwsOnce = true;
      void listener(Object _) {
        if (throwsOnce) {
          throwsOnce = false;
          throw StateError('listener failure');
        }
      }

      content.subscribe(<Object>[kContextDataKey], listener);
      expect(
        () => publisher.publishSnapshot(snapshot),
        throwsA(isA<StateError>()),
      );
      expect(content.updates, equals(1));
      expect(publisher.lastPublished, isNull);
      publisher.publishSnapshot(snapshot);
      expect(content.updates, equals(2));
      expect(publisher.lastPublished, same(snapshot));
      content.unsubscribe(<Object>[kContextDataKey], listener);
    });

    test('publishes context data unconditionally', () {
      final content = _CountingContent();
      final context = <String, Object?>{'a': 1};

      populateContextData(content, context);
      expect(content.updates, equals(1));
      populateContextData(content, context);
      expect(content.updates, equals(2));
    });

    test('context data leaves device and theme roots unchanged', () {
      final content = DynamicContent();
      final colorScheme = const ColorScheme.light().copyWith(
        primary: const Color(0xFF123456),
      );
      populateDeviceData(
        content,
        locale: const Locale('en', 'US'),
        mediaQuery: const MediaQueryData(
          size: Size(390, 844),
          devicePixelRatio: 2,
          padding: EdgeInsets.only(top: 10, bottom: 20),
        ),
        platform: 'ios',
      );
      populateThemeData(
        content,
        colorScheme: colorScheme,
        iconTheme: const IconThemeData(size: 24),
        defaultTextStyle: const TextStyle(fontSize: 16),
      );

      populateContextData(
        content,
        <String, Object?>{
          'device': 'x',
          'theme': 'y',
          'products': 'z',
        },
      );

      final device = _readKey(content, 'device') as Map;
      final theme = _readKey(content, 'theme') as Map;
      final context = _readKey(content, kContextDataKey) as Map;
      expect(device['platform'], 'ios');
      expect(device['screenWidth'], 390.0);
      expect((theme['colorScheme'] as Map)['primary'], 0xFF123456);
      expect((theme['iconTheme'] as Map)['size'], 24.0);
      expect(
        context,
        <String, Object?>{
          'device': 'x',
          'theme': 'y',
          'products': 'z',
        },
      );
      expect(_readKey(content, 'products'), same(missing));
    });
  });
}
