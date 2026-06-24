import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';
import 'package:rfw/rfw.dart';

void main() {
  group('RestageDecoders.selectionOptionList', () {
    test('decodes an ordered list of {value, label} options', () {
      final source = _MapDataSource({
        'items': [
          {'value': 'basic', 'label': 'Basic'},
          {'value': 'pro', 'label': 'Pro'},
          {'value': 'team', 'label': 'Team'},
        ],
      });

      final options =
          RestageDecoders.selectionOptionList(source, const ['items']);

      expect(options, hasLength(3));
      expect(options![0],
          const RestageSelectionOption(value: 'basic', label: 'Basic'));
      expect(
          options[1], const RestageSelectionOption(value: 'pro', label: 'Pro'));
      expect(options[2],
          const RestageSelectionOption(value: 'team', label: 'Team'));
      // Order is preserved exactly as authored.
      expect(options.map((o) => o.value).toList(), ['basic', 'pro', 'team']);
    });

    test('returns null for an absent slot (not a list on the wire)', () {
      // Absent → null so the required-slot contract applies. Codegen guarantees
      // presence, so this is the corruption/tamper case.
      final source = _MapDataSource(const <String, Object?>{});
      expect(
        RestageDecoders.selectionOptionList(source, const ['items']),
        isNull,
      );
    });

    test('returns [] (not null) for a PRESENT empty list — fail-safe', () {
      // A present-but-empty list must NOT collapse to null: returning null would
      // trip the caller's required-slot throw and CRASH the render. The
      // fail-safe boundary is "present ⇒ a list (maybe empty)"; the compiled
      // widget renders its empty state (SizedBox.shrink) on [].
      final source = _MapDataSource({'items': const <Object?>[]});
      expect(
        RestageDecoders.selectionOptionList(source, const ['items']),
        isEmpty,
      );
      expect(
        RestageDecoders.selectionOptionList(source, const ['items']),
        isNotNull,
      );
    });

    test('falls a missing label back to the value (no blank rows)', () {
      final source = _MapDataSource({
        'items': [
          {'value': 'pro'},
        ],
      });

      final options =
          RestageDecoders.selectionOptionList(source, const ['items']);

      expect(options, hasLength(1));
      expect(options!.single.value, 'pro');
      expect(options.single.label, 'pro');
    });

    test('omits an entry missing its value (never fabricates a key)', () {
      final source = _MapDataSource({
        'items': [
          {'value': 'a', 'label': 'A'},
          {'label': 'orphan label'}, // no value — dropped
          {'value': 'b', 'label': 'B'},
        ],
      });

      final options =
          RestageDecoders.selectionOptionList(source, const ['items']);

      expect(options, hasLength(2));
      expect(options!.map((o) => o.value).toList(), ['a', 'b']);
    });

    test('omits a non-map entry rather than crashing the list', () {
      final source = _MapDataSource({
        'items': [
          {'value': 'a', 'label': 'A'},
          'not a map',
          {'value': 'b', 'label': 'B'},
        ],
      });

      final options =
          RestageDecoders.selectionOptionList(source, const ['items']);

      expect(options, hasLength(2));
      expect(options!.map((o) => o.value).toList(), ['a', 'b']);
    });

    test('returns [] (not null) when every entry is malformed — fail-safe', () {
      // A present list whose every entry is malformed must return [], NOT null:
      // null would trip the required-slot throw and crash the render. The
      // compiled widget renders its empty state on []. This is the
      // degenerate-tamper case that must fail safe, not crash.
      final source = _MapDataSource({
        'items': [
          {'label': 'no value'},
          'not a map',
        ],
      });

      expect(
        RestageDecoders.selectionOptionList(source, const ['items']),
        isEmpty,
      );
      expect(
        RestageDecoders.selectionOptionList(source, const ['items']),
        isNotNull,
      );
    });

    test('a non-list present value (e.g. a map) is treated as absent → null',
        () {
      // `isList` is false for a non-list value, so it routes to the absent
      // branch (the required-slot contract). Only a genuine list is decoded.
      final source = _MapDataSource({'items': const <String, Object?>{}});
      expect(
        RestageDecoders.selectionOptionList(source, const ['items']),
        isNull,
      );
    });
  });

  group('RestageSelectionOption', () {
    test('value equality and hashCode', () {
      const a = RestageSelectionOption(value: 'x', label: 'X');
      const b = RestageSelectionOption(value: 'x', label: 'X');
      const c = RestageSelectionOption(value: 'x', label: 'Y');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });
  });
}

final class _MapDataSource implements DataSource {
  const _MapDataSource(this.root);

  final Object? root;

  @override
  T? v<T extends Object>(List<Object> argsKey) {
    final value = _lookup(argsKey);
    return value is T ? value : null;
  }

  @override
  bool isList(List<Object> argsKey) => _lookup(argsKey) is List<Object?>;

  @override
  int length(List<Object> argsKey) {
    final value = _lookup(argsKey);
    return value is List<Object?> ? value.length : 0;
  }

  @override
  bool isMap(List<Object> argsKey) => _lookup(argsKey) is Map<String, Object?>;

  @override
  Widget child(List<Object> argsKey) => ErrorWidget('missing child');

  @override
  List<Widget> childList(List<Object> argsKey) => const [];

  @override
  Widget builder(List<Object> argsKey, DynamicMap builderArg) =>
      ErrorWidget('missing builder');

  @override
  T? handler<T extends Function>(
    List<Object> argsKey,
    HandlerGenerator<T> generator,
  ) =>
      null;

  @override
  Widget? optionalBuilder(List<Object> argsKey, DynamicMap builderArg) => null;

  @override
  Widget? optionalChild(List<Object> argsKey) => null;

  @override
  VoidCallback? voidHandler(
    List<Object> argsKey, [
    DynamicMap? extraArguments,
  ]) =>
      null;

  Object? _lookup(List<Object> path) {
    Object? current = root;
    for (final segment in path) {
      if (current is Map<String, Object?> && segment is String) {
        current = current[segment];
      } else if (current is List<Object?> && segment is int) {
        if (segment < 0 || segment >= current.length) return null;
        current = current[segment];
      } else {
        return null;
      }
    }
    return current;
  }
}
