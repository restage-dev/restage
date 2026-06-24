import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';
import 'package:rfw/rfw.dart';

void main() {
  group('RestageDecoders.booleanList', () {
    test('decodes an ordered list of booleans, order preserved', () {
      final source = _MapDataSource({
        'isSelected': const [true, false, true],
      });

      final values = RestageDecoders.booleanList(source, const ['isSelected']);

      expect(values, [true, false, true]);
    });

    test('returns null for an absent slot (not a list on the wire)', () {
      // Absent → null so the required-slot contract applies. Codegen guarantees
      // presence, so this is the corruption/tamper case.
      final source = _MapDataSource(const <String, Object?>{});
      expect(
        RestageDecoders.booleanList(source, const ['isSelected']),
        isNull,
      );
    });

    test('returns [] (not null) for a PRESENT empty list — fail-safe', () {
      // A present-but-empty list must NOT collapse to null: returning null
      // would trip the caller's required-slot throw and CRASH the render. The
      // fail-safe boundary is "present ⇒ a list (maybe empty)".
      final source = _MapDataSource({'isSelected': const <Object?>[]});
      expect(
        RestageDecoders.booleanList(source, const ['isSelected']),
        isEmpty,
      );
      expect(
        RestageDecoders.booleanList(source, const ['isSelected']),
        isNotNull,
      );
    });

    test('coerces a non-bool entry to false rather than crashing the list', () {
      // A malformed entry (not a bool on the wire) must NOT throw out the whole
      // list. It coerces to `false` (the unselected state) — the safe default
      // for a toggle — keeping list LENGTH stable so the per-index pairing with
      // `children` is preserved (a dropped entry would shift every later
      // selection onto the wrong button).
      final source = _MapDataSource({
        'isSelected': const [true, 'not a bool', false],
      });

      final values = RestageDecoders.booleanList(source, const ['isSelected']);

      expect(values, [true, false, false]);
    });

    test('a non-list present value (e.g. a map) is treated as absent → null',
        () {
      // `isList` is false for a non-list value, so it routes to the absent
      // branch (the required-slot contract). Only a genuine list is decoded.
      final source = _MapDataSource({'isSelected': const <String, Object?>{}});
      expect(
        RestageDecoders.booleanList(source, const ['isSelected']),
        isNull,
      );
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
