import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';
import 'package:rfw/rfw.dart';

void main() {
  group('RestageDecoders.textInputType', () {
    test('decodes every supported keyboard name', () {
      const expected = <String, TextInputType>{
        'text': TextInputType.text,
        'multiline': TextInputType.multiline,
        'number': TextInputType.number,
        'phone': TextInputType.phone,
        'emailAddress': TextInputType.emailAddress,
        'url': TextInputType.url,
        'name': TextInputType.name,
      };
      for (final MapEntry(key: name, value: type) in expected.entries) {
        expect(
          RestageDecoders.textInputType(
            _MapDataSource({'keyboardType': name}),
            const ['keyboardType'],
          ),
          type,
          reason: name,
        );
      }
      expect(
        RestageDecoders.supportedTextInputTypeNames,
        expected.keys.toSet(),
      );
    });

    test('decodes an absent, unknown or non-string value to null', () {
      for (final value in <Object?>[
        null,
        'datetime',
        'TextInputType.text',
        3
      ]) {
        expect(
          RestageDecoders.textInputType(
            _MapDataSource({'keyboardType': value}),
            const ['keyboardType'],
          ),
          isNull,
          reason: '$value',
        );
      }
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
