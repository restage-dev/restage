import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';
import 'package:rfw/formats.dart' as rfw;
import 'package:rfw/rfw.dart';

const _controller = NativeBindingContract(type: 'flutter.ScrollController');

class _Controller extends ScrollController {
  bool disposed = false;
  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

class _EqualValue {
  @override
  bool operator ==(Object other) => other is _EqualValue;
  @override
  int get hashCode => 1;
}

class _Source extends Fake implements DataSource {
  _Source(this.value);
  final Map<String, Object?> value;
  @override
  bool isMap(List<Object> path) => path.isEmpty;
  @override
  T? v<T extends Object>(List<Object> path) {
    final result = value[path.single];
    return result is T ? result : null;
  }
}

const _color = NativeBindingContract(type: 'flutter.Color');
const _root = LibraryName(['test']);
const _core = LibraryName(['restage', 'core']);

class _Palette extends InheritedWidget {
  const _Palette({required super.child, required this.ink});
  final Color ink;
  static _Palette of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_Palette>()!;
  @override
  bool updateShouldNotify(_Palette old) => ink != old.ink;
}

/// Computes the binding in its own build, as a generated mount does.
class _Mount extends StatelessWidget {
  const _Mount({required this.runtime, required this.data});
  final Runtime runtime;
  final DynamicContent data;
  @override
  Widget build(BuildContext context) => RestageNativeValues(
        bindings: {
          'ink':
              NativeBinding(contract: _color, value: _Palette.of(context).ink),
        },
        child: RemoteWidget(
            runtime: runtime,
            data: data,
            widget: const FullyQualifiedWidgetName(_root, 'Root')),
      );
}

void main() {
  testWidgets('isolated mounts borrow controllers and notify by identity',
      (tester) async {
    final first = _Controller();
    final second = _Controller();
    final replacement = _Controller();
    final seen = <ScrollController>[];
    Widget reader() => Builder(builder: (context) {
          final controller = RestageNativeValues.read<ScrollController>(
              context, _Source(_controller.reference('scroll')), const [],
              type: 'flutter.ScrollController')!;
          seen.add(controller);
          return ListView(
              controller: controller, children: const [SizedBox(height: 1000)]);
        });
    final left = reader();
    final right = reader();
    Widget mount(ScrollController controller) => Directionality(
          textDirection: TextDirection.ltr,
          child: Row(children: [
            Expanded(
                child: RestageNativeValues(bindings: {
              'scroll': NativeBinding(contract: _controller, value: controller),
            }, child: left)),
            Expanded(
                child: RestageNativeValues(bindings: {
              'scroll': NativeBinding(contract: _controller, value: second),
            }, child: right)),
          ]),
        );
    await tester.pumpWidget(mount(first));
    expect(seen[0], same(first));
    expect(seen[1], same(second));
    expect(first.positions, hasLength(1));
    expect(second.positions, hasLength(1));
    first.jumpTo(75);
    expect(first.offset, 75);
    seen.clear();
    await tester.pumpWidget(mount(replacement));
    expect(seen, hasLength(1));
    expect(seen.single, same(replacement));
    expect(first.hasClients, isFalse);
    expect(first.disposed, isFalse);
    await tester.pumpWidget(const SizedBox());
    expect(second.disposed, isFalse);
    expect(replacement.disposed, isFalse);
    for (final controller in [first, second, replacement]) {
      controller.dispose();
    }
  });

  testWidgets('equal but distinct native objects notify dependents',
      (tester) async {
    const contract = NativeBindingContract(type: 'app.EqualValue');
    final first = _EqualValue();
    final second = _EqualValue();
    final seen = <Object>[];
    final reader = Builder(builder: (context) {
      seen.add(RestageNativeValues.bindingOf<_EqualValue>(context, 'value',
          contract: contract)!);
      return const SizedBox();
    });
    Widget scope(_EqualValue value) => RestageNativeValues(bindings: {
          'value': NativeBinding(contract: contract, value: value),
        }, child: reader);
    await tester.pumpWidget(scope(first));
    await tester.pumpWidget(scope(second));
    expect(seen, hasLength(2));
    expect(seen.last, same(second));
  });

  testWidgets('present null differs from missing and retyped references',
      (tester) async {
    const nullable =
        NativeBindingContract(type: 'flutter.ScrollController', nullable: true);
    await tester.pumpWidget(RestageNativeValues(
        bindings: {
          'nullable':
              NativeBinding<ScrollController?>(contract: nullable, value: null),
          'wrongDart': NativeBinding(contract: _controller, value: Object()),
        },
        child: Builder(builder: (context) {
          expect(
              RestageNativeValues.bindingOf<ScrollController>(
                  context, 'nullable',
                  contract: nullable),
              isNull);
          expect(
              () => RestageNativeValues.bindingOf<ScrollController>(
                  context, 'missing',
                  contract: nullable),
              throwsFormatException);
          expect(
              () => RestageNativeValues.bindingOf<ScrollController>(
                  context, 'nullable',
                  contract: _controller),
              throwsFormatException);
          expect(
              () => RestageNativeValues.bindingOf<ScrollController>(
                  context, 'wrongDart',
                  contract: _controller),
              throwsFormatException);
          for (final reference in [
            {
              ...nullable.reference('nullable'),
              'type': 'flutter.TabController'
            },
            {...nullable.reference('nullable'), 'nullable': false},
            {...nullable.reference('nullable'), 'kind': 'native'},
          ]) {
            expect(
                () => RestageNativeValues.read<ScrollController>(
                    context, _Source(reference), const [],
                    type: 'flutter.ScrollController'),
                throwsFormatException);
          }
          return const SizedBox();
        })));
    expect(() => NativeBinding<Object?>(contract: _controller, value: null),
        throwsArgumentError);
  });

  testWidgets('typed callbacks retain actual details and native failure timing',
      (tester) async {
    const contract =
        NativeBindingContract(type: 'void Function(flutter.TapDownDetails)');
    TapDownDetails? received;
    final failure = StateError('native callback');
    void callback(TapDownDetails details) {
      received = details;
      throw failure;
    }

    final details = TapDownDetails(globalPosition: const Offset(4, 7));
    await tester.pumpWidget(RestageNativeValues(
        bindings: {
          'tap': NativeBinding(contract: contract, value: callback),
        },
        child: Builder(builder: (context) {
          final installed =
              RestageNativeValues.bindingOf<GestureTapDownCallback>(
                  context, 'tap',
                  contract: contract)!;
          expect(received, isNull);
          expect(installed, same(callback));
          expect(() => installed(details), throwsA(same(failure)));
          expect(received, same(details));
          return const SizedBox();
        })));
  });

  testWidgets(
      'a mount-computed Color repaints when its inherited source changes',
      (tester) async {
    final runtime = Runtime()
      ..update(_core, LocalWidgetLibrary(kCoreLibraryFactories))
      ..update(
          _root,
          rfw.parseLibraryFile('import restage.core; widget Root = '
              'ColoredBox(color: data.context.ink, child: SizedBox(width: 10.0, height: 10.0));'));
    final data = DynamicContent()
      ..update('context', <String, Object?>{
        'ink': <String, Object?>{
          'kind': 'nativeBinding',
          'key': 'ink',
          'type': 'flutter.Color',
          'nullable': false,
        },
      });
    addTearDown(runtime.dispose);
    const first = Color(0xff112233);
    final second = MaterialColor(0xff445566, const {500: Color(0xff445566)});
    Widget app(Color ink) => Directionality(
        textDirection: TextDirection.ltr,
        child: _Palette(ink: ink, child: _Mount(runtime: runtime, data: data)));
    await tester.pumpWidget(app(first));
    expect(tester.takeException(), isNull);
    expect(
        tester.widget<ColoredBox>(find.byType(ColoredBox)).color, same(first));
    await tester.pumpWidget(app(second));
    expect(tester.takeException(), isNull);
    expect(
        tester.widget<ColoredBox>(find.byType(ColoredBox)).color, same(second));
  });

  testWidgets('a missing native binding names its cause in debug builds',
      (tester) async {
    final runtime = Runtime()
      ..update(_core, LocalWidgetLibrary(kCoreLibraryFactories))
      ..update(
          _root,
          rfw.parseLibraryFile('import restage.core; widget Root = '
              'ColoredBox(color: data.context.ink);'));
    addTearDown(runtime.dispose);
    final data = DynamicContent()
      ..update('context', <String, Object?>{
        'ink': <String, Object?>{
          'kind': 'nativeBinding',
          'key': 'ink',
          'type': 'flutter.Color',
          'nullable': false,
        },
      });
    final printed = <String>[];
    final print = debugPrint;
    debugPrint = (message, {wrapWidth}) => printed.add(message ?? '');
    try {
      for (final (labels, message) in [
        (
          const <String, String>{},
          "[restage] This app build doesn't compute a value this design uses. "
              "The ColoredBox that uses it isn't shown.",
        ),
        (
          const {'ink': 'Palette.of(context).ink'},
          "[restage] 'Palette.of(context).ink' threw while the app computed "
              "it. The ColoredBox that uses it isn't shown.",
        ),
      ]) {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(Directionality(
            textDirection: TextDirection.ltr,
            child: RestageNativeValues(
                labels: labels,
                child: RemoteWidget(
                    runtime: runtime,
                    data: data,
                    widget: const FullyQualifiedWidgetName(_root, 'Root')))));
        expect(tester.takeException(), isNotNull);
        expect(printed, contains(message));
      }
    } finally {
      debugPrint = print;
    }
  });

  testWidgets('each list item reads its own computed native object',
      (tester) async {
    final runtime = Runtime()
      ..update(_core, LocalWidgetLibrary(kCoreLibraryFactories))
      ..update(
          _root,
          rfw.parseLibraryFile('import restage.core; widget Root = Column('
              'children: [...for item in data.context.items: '
              'ColoredBox(color: item.ink, '
              'child: SizedBox(width: 10.0, height: 10.0))]);'));
    addTearDown(runtime.dispose);
    final colors = <Color>[
      const Color(0xff112233),
      MaterialColor(0xff445566, const {500: Color(0xff445566)}),
    ];
    final data = DynamicContent()
      ..update('context', <String, Object?>{
        'items': [
          for (var i = 0; i < colors.length; i++)
            <String, Object?>{
              'ink': <String, Object?>{
                'kind': 'nativeBinding',
                'key': 'ink#$i',
                'type': 'flutter.Color',
                'nullable': false,
              },
            },
        ],
      });
    await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: RestageNativeValues(
            bindings: {
              for (var i = 0; i < colors.length; i++)
                'ink#$i': NativeBinding(contract: _color, value: colors[i]),
            },
            child: RemoteWidget(
                runtime: runtime,
                data: data,
                widget: const FullyQualifiedWidgetName(_root, 'Root')))));
    expect(tester.takeException(), isNull);
    final painted = tester
        .widgetList<ColoredBox>(find.byType(ColoredBox))
        .map((box) => box.color)
        .toList();
    for (var i = 0; i < colors.length; i++) {
      expect(painted[i], same(colors[i]));
    }
  });
}
