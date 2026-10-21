import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';
import 'package:rfw/formats.dart';
import 'package:rfw/rfw.dart';

const LibraryName _coreLibrary = LibraryName(<String>['restage', 'core']);
const LibraryName _rootLibrary = LibraryName(<String>['restage', 'paywall']);

void main() {
  group('RestageDecoders.string', () {
    test('reads a string', () {
      expect(
        RestageDecoders.string(_MapDataSource({'label': 'Go'}), ['label']),
        'Go',
      );
    });

    test('joins a list of parts in order', () {
      final source = _MapDataSource({
        'label': const ['Only ', r'$4', ' a month'],
      });
      expect(RestageDecoders.string(source, ['label']), r'Only $4 a month');
    });

    test('reads a non-string part as empty', () {
      final source = _MapDataSource({
        'label': const ['Day ', 3, null, '!'],
      });
      expect(RestageDecoders.string(source, ['label']), 'Day !');
    });

    test('is null for an absent slot', () {
      expect(
        RestageDecoders.string(const _MapDataSource({}), ['label']),
        isNull,
      );
    });
  });

  group('RestageDecoders.integerList', () {
    test('decodes ints and drops anything else', () {
      final source = _MapDataSource({
        'values': const [1, 2.5, 'three', 4],
      });
      expect(RestageDecoders.integerList(source, ['values']), [1, 4]);
    });

    test('is null when absent and empty when present and empty', () {
      expect(
        RestageDecoders.integerList(const _MapDataSource({}), ['values']),
        isNull,
      );
      expect(
        RestageDecoders.integerList(
          _MapDataSource({'values': const <Object?>[]}),
          ['values'],
        ),
        isEmpty,
      );
    });
  });

  group('RestageDecoders.realList', () {
    test('reads an int as a double and drops anything else', () {
      final source = _MapDataSource({
        'values': const [1.5, 2, 'three', null],
      });
      expect(RestageDecoders.realList(source, ['values']), [1.5, 2.0]);
    });

    test('is null when absent', () {
      expect(
        RestageDecoders.realList(const _MapDataSource({}), ['values']),
        isNull,
      );
    });
  });

  testWidgets('a String slot renders its joined parts', (tester) async {
    final runtime = Runtime()
      ..update(_coreLibrary, buildCoreWidgetLibrary())
      ..update(
        _rootLibrary,
        parseLibraryFile('''
import restage.core;
widget Paywall = Semantics(label: ["Only ", data.context.price, " a year"], child: SizedBox(width: 10.0, height: 10.0));
'''),
      );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RemoteWidget(
          runtime: runtime,
          data: DynamicContent(<String, Object>{
            'context': <String, Object>{'price': r'$40'},
          }),
          widget: const FullyQualifiedWidgetName(_rootLibrary, 'Paywall'),
          onEvent: (_, __) {},
        ),
      ),
    );
    await tester.pump();

    expect(
      tester.widget<Semantics>(find.byType(Semantics).first).properties.label,
      r'Only $40 a year',
    );
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
