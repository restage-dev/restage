import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/src/runtime/grid_values.dart';
import 'package:rfw/formats.dart';
import 'package:rfw/rfw.dart';

void main() {
  SliverGridDelegate decodeGrid(Map<String, Object?> value) =>
      RestageGridValues.gridDelegate(_MapDataSource(value), const [])!;
  ScrollPhysics decodePhysics(Map<String, Object?> value) =>
      RestageGridValues.physics(_MapDataSource(value), const [])!;

  testWidgets('real RFW data source reconstructs native grid values',
      (tester) async {
    const local = LibraryName(['local']);
    const remote = LibraryName(['remote']);
    final runtime = Runtime()
      ..update(
          local,
          LocalWidgetLibrary({
            'Grid': (context, source) => GridView(
                  gridDelegate: RestageGridValues.gridDelegate(
                      source, const ['gridDelegate'])!,
                  physics: RestageGridValues.physics(source, const ['physics']),
                  scrollCacheExtent:
                      RestageGridValues.cacheExtent(source, const ['cache']),
                  children: const [SizedBox(), SizedBox()],
                ),
          }))
      ..update(remote, parseLibraryFile('''
import local;
widget Main = Grid(
  gridDelegate: {_s: "SliverGridDelegateWithFixedCrossAxisCount",
    crossAxisCount: 2, mainAxisExtent: 53.0, crossAxisSpacing: 9},
  physics: {_s: "BouncingScrollPhysics", decelerationRate: "fast",
    parent: {_s: "AlwaysScrollableScrollPhysics"}},
  cache: {_s: "viewport", value: 1.5}
);
'''));
    addTearDown(runtime.dispose);
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.rtl,
      child: RemoteWidget(
        runtime: runtime,
        data: DynamicContent(),
        widget: const FullyQualifiedWidgetName(remote, 'Main'),
      ),
    ));
    expect(tester.takeException(), isNull);
    final grid = tester.widget<GridView>(find.byType(GridView));
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 2);
    expect(delegate.mainAxisExtent, 53);
    expect(delegate.crossAxisSpacing, 9);
    expect(grid.physics, isA<BouncingScrollPhysics>());
    expect(grid.physics!.parent, isA<AlwaysScrollableScrollPhysics>());
    expect(grid.scrollCacheExtent, const ScrollCacheExtent.viewport(1.5));
  });

  test('fixed-count native layout, nullable extent and defaults', () {
    final defaults = decodeGrid({
      '_s': 'SliverGridDelegateWithFixedCrossAxisCount',
      'crossAxisCount': 3,
    }) as SliverGridDelegateWithFixedCrossAxisCount;
    expect(defaults.mainAxisSpacing, 0.0);
    expect(defaults.crossAxisSpacing, 0.0);
    expect(defaults.childAspectRatio, 1.0);
    expect(defaults.mainAxisExtent, isNull);
    final decoded = decodeGrid({
      '_s': 'SliverGridDelegateWithFixedCrossAxisCount',
      'crossAxisCount': 3,
      'mainAxisSpacing': 7,
      'crossAxisSpacing': 11.0,
      'childAspectRatio': 2.0,
      'mainAxisExtent': 53.0,
    });
    const native = SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 3,
      mainAxisSpacing: 7,
      crossAxisSpacing: 11,
      childAspectRatio: 2,
      mainAxisExtent: 53,
    );
    _expectLayouts(decoded, native);
    expect(decoded.shouldRelayout(native), isFalse);
  });

  test('max-extent delegate preserves native geometry in both axes', () {
    final defaults = decodeGrid({
      '_s': 'SliverGridDelegateWithMaxCrossAxisExtent',
      'maxCrossAxisExtent': 140,
      'mainAxisExtent': null,
    }) as SliverGridDelegateWithMaxCrossAxisExtent;
    expect(defaults.mainAxisExtent, isNull);
    expect(defaults.mainAxisSpacing, 0);
    expect(defaults.crossAxisSpacing, 0);
    expect(defaults.childAspectRatio, 1);
    final decoded = decodeGrid({
      '_s': 'SliverGridDelegateWithMaxCrossAxisExtent',
      'maxCrossAxisExtent': 140,
      'mainAxisSpacing': 5.0,
      'crossAxisSpacing': 9,
      'childAspectRatio': 1.7,
    });
    const native = SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 140,
      mainAxisSpacing: 5,
      crossAxisSpacing: 9,
      childAspectRatio: 1.7,
    );
    _expectLayouts(decoded, native);
    expect(decoded.shouldRelayout(native), isFalse);
  });

  test('all standard physics return actual native classes', () {
    for (final native in const <ScrollPhysics>[
      ScrollPhysics(),
      RangeMaintainingScrollPhysics(),
      BouncingScrollPhysics(),
      ClampingScrollPhysics(),
      AlwaysScrollableScrollPhysics(),
      NeverScrollableScrollPhysics(),
      PageScrollPhysics(),
      FixedExtentScrollPhysics(),
    ]) {
      final decoded = decodePhysics({'_s': '${native.runtimeType}'});
      expect(decoded.runtimeType, native.runtimeType);
      expect(decoded.parent, isNull);
      expect(decoded.allowUserScrolling, native.allowUserScrolling);
      expect(decoded.allowImplicitScrolling, native.allowImplicitScrolling);
    }
  });

  test('native physics parent chains and deceleration methods remain faithful',
      () {
    final decoded = decodePhysics({
      '_s': 'BouncingScrollPhysics',
      'decelerationRate': 'fast',
      'parent': {
        '_s': 'RangeMaintainingScrollPhysics',
        'parent': {'_s': 'AlwaysScrollableScrollPhysics'},
      },
    }) as BouncingScrollPhysics;
    const native = BouncingScrollPhysics(
      decelerationRate: ScrollDecelerationRate.fast,
      parent: RangeMaintainingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
    );
    expect(decoded.parent, isA<RangeMaintainingScrollPhysics>());
    expect(decoded.parent!.parent, isA<AlwaysScrollableScrollPhysics>());
    expect(decoded.decelerationRate, ScrollDecelerationRate.fast);
    expect(decoded.frictionFactor(0.4), native.frictionFactor(0.4));
    final metrics = FixedScrollMetrics(
      minScrollExtent: 0,
      maxScrollExtent: 800,
      pixels: 120,
      viewportDimension: 300,
      axisDirection: AxisDirection.down,
      devicePixelRatio: 1,
    );
    expect(decoded.applyPhysicsToUserOffset(metrics, 25),
        native.applyPhysicsToUserOffset(metrics, 25));
    expect(decoded.shouldAcceptUserOffset(metrics),
        native.shouldAcceptUserOffset(metrics));
    final applied = decoded.applyTo(const NeverScrollableScrollPhysics());
    expect(applied.decelerationRate, native.decelerationRate);
    expect(applied.parent!.parent!.parent, isA<NeverScrollableScrollPhysics>());
    final defaults =
        decodePhysics({'_s': 'BouncingScrollPhysics'}) as BouncingScrollPhysics;
    expect(defaults.decelerationRate, ScrollDecelerationRate.normal);
  });

  test('cache constructors retain native units and values', () {
    for (final kind in ['pixels', 'viewport']) {
      for (final value in [0, 1.5, -2.0, double.infinity]) {
        final decoded = RestageGridValues.cacheExtent(
          _MapDataSource({'_s': kind, 'value': value}),
          const [],
        );
        final native = kind == 'pixels'
            ? ScrollCacheExtent.pixels(value.toDouble())
            : ScrollCacheExtent.viewport(value.toDouble());
        expect(decoded, native);
        expect(decoded!.style, native.style);
        expect(decoded.value, native.value);
      }
    }
  });

  test('absent and explicit null slots remain absent', () {
    for (final value in [null, <String, Object?>{}]) {
      final source = _MapDataSource({'value': value});
      final path = value == null ? ['value'] : ['missing'];
      expect(RestageGridValues.gridDelegate(source, path), isNull);
      expect(RestageGridValues.physics(source, path), isNull);
      expect(RestageGridValues.cacheExtent(source, path), isNull);
    }
  });

  test('malformed structured values fail explicitly', () {
    for (final value in <Object?>[
      7,
      'ScrollPhysics',
      <Object?>[],
      <String, Object?>{},
      {'_s': 'CustomPhysics'},
      {'_s': 'ScrollPhysics', 'parent': 3},
      {'_s': 'BouncingScrollPhysics', 'decelerationRate': 'turbo'},
    ]) {
      expect(() => RestageGridValues.physics(_MapDataSource(value), const []),
          throwsFormatException,
          reason: '$value');
    }
    for (final value in <Map<String, Object?>>[
      {'_s': 'CustomDelegate'},
      {'_s': 'SliverGridDelegateWithFixedCrossAxisCount', 'crossAxisCount': 0},
      {
        '_s': 'SliverGridDelegateWithFixedCrossAxisCount',
        'crossAxisCount': 2.0
      },
      {
        '_s': 'SliverGridDelegateWithMaxCrossAxisExtent',
        'maxCrossAxisExtent': -1
      },
      {
        '_s': 'SliverGridDelegateWithFixedCrossAxisCount',
        'crossAxisCount': 2,
        'mainAxisSpacing': 'bad'
      },
      {
        '_s': 'SliverGridDelegateWithFixedCrossAxisCount',
        'crossAxisCount': 2,
        'childAspectRatio': 0
      },
    ]) {
      expect(() => decodeGrid(value), throwsFormatException, reason: '$value');
    }
    for (final value in <Map<String, Object?>>[
      {'_s': 'other', 'value': 1.0},
      {'_s': 'pixels'},
      {'_s': 'viewport', 'value': 'bad'},
    ]) {
      expect(
          () => RestageGridValues.cacheExtent(_MapDataSource(value), const []),
          throwsFormatException);
    }
  });

  test('parent structure bound rejects excess depth and cycles', () {
    var chain = <String, Object?>{'_s': 'ScrollPhysics'};
    for (var index = 1; index < 64; index++) {
      chain = {'_s': 'ScrollPhysics', 'parent': chain};
    }
    expect(decodePhysics(chain), isA<ScrollPhysics>());
    expect(() => decodePhysics({'_s': 'ScrollPhysics', 'parent': chain}),
        throwsFormatException);
    final cycle = <String, Object?>{'_s': 'ScrollPhysics'};
    cycle['parent'] = cycle;
    expect(() => decodePhysics(cycle), throwsFormatException);
  });
}

void _expectLayouts(SliverGridDelegate decoded, SliverGridDelegate native) {
  for (final direction in AxisDirection.values) {
    final constraints = SliverConstraints(
      axisDirection: direction,
      growthDirection: GrowthDirection.forward,
      userScrollDirection: ScrollDirection.idle,
      scrollOffset: 0,
      precedingScrollExtent: 0,
      overlap: 0,
      remainingPaintExtent: 600,
      crossAxisExtent: 480,
      crossAxisDirection: axisDirectionToAxis(direction) == Axis.vertical
          ? AxisDirection.left
          : AxisDirection.down,
      viewportMainAxisExtent: 600,
      remainingCacheExtent: 800,
      cacheOrigin: 0,
    );
    final actualLayout = decoded.getLayout(constraints);
    final expectedLayout = native.getLayout(constraints);
    for (final index in [0, 1, 3, 12]) {
      final actual = actualLayout.getGeometryForChildIndex(index);
      final expected = expectedLayout.getGeometryForChildIndex(index);
      expect(actual.scrollOffset, expected.scrollOffset);
      expect(actual.crossAxisOffset, expected.crossAxisOffset);
      expect(actual.mainAxisExtent, expected.mainAxisExtent);
      expect(actual.crossAxisExtent, expected.crossAxisExtent);
    }
    expect(actualLayout.computeMaxScrollOffset(23),
        expectedLayout.computeMaxScrollOffset(23));
  }
}

final class _MapDataSource implements DataSource {
  const _MapDataSource(this.root);
  final Object? root;

  Object? _lookup(List<Object> path) {
    Object? value = root;
    for (final segment in path) {
      if (value is! Map<String, Object?>) return null;
      value = value[segment];
    }
    return value;
  }

  @override
  T? v<T extends Object>(List<Object> path) {
    expect([int, double, bool, String], contains(T));
    final value = _lookup(path);
    return value is T ? value : null;
  }

  @override
  bool isMap(List<Object> path) => _lookup(path) is Map<String, Object?>;
  @override
  bool isList(List<Object> path) => _lookup(path) is List<Object?>;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
