import 'dart:collection';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/widgets.dart';
import 'package:restage_core/restage_core.dart'
    show NativeBinding, NativeBindingContract;
import 'package:rfw/rfw.dart' show DataSource;

import '../authoring/authoring_refusal_diagnostic.dart';
import '../authoring/onboarding_event.dart' as authoring;
import '../authoring/paywall_event_dispatch.dart';
import '../flow/flow_descriptors.dart' show SurfaceEvent;
import 'host_value.dart';
import 'island_scope.dart';

/// The values a generated mount's build records where the app computes them,
/// keyed as the surface reads them.
final class RestageRecording {
  /// Records for a mount; [owner] keys each island the build places, so it
  /// keeps its element when the design replaces the build's own widget.
  /// A step mount passes its [mount] context, which its events fire from;
  /// any other mount's events reach the surface that hosts [owner].
  RestageRecording({this.owner, BuildContext? mount}) : _mount = mount {
    if (owner case final owner?) RestageIslandScope.forgetUnmounted(owner);
  }

  /// The mount the islands belong to.
  final Object? owner;

  final BuildContext? _mount;

  /// The values recorded outside any loop, and each loop's items.
  final Map<String, Object?> values = {};

  /// The native objects recorded, by the key a binding reference names.
  final Map<String, Object?> natives = {};

  final Map<String, _Cursor> _cursors = {};

  final Map<String, Object> _islands = {};

  /// Records the app widget [widget] the design places as the island [name],
  /// or how to build it around the design's own content, and returns it.
  ///
  /// Placed inside a value reads place, through the [spots] those reads mark
  /// with [spot] (outermost first), it is keyed only at the spot they name.
  ///
  /// With [place], the design builds the widget itself: [widget] is placed
  /// through [place] and recorded nowhere, keyed as the design keys it (by
  /// the app's own key when it has one), so its State moves between the two.
  Widget island<W extends Widget>(
    String name,
    W widget, {
    String? items,
    Widget Function(BuildContext context, DataSource source)? build,
    List<int>? spots,
    Widget Function(W widget)? place,
  }) {
    final path = items == null ? const <int>[] : _cursors[items]!.path;
    final owner = this.owner;
    if (place != null) {
      final placed = place(widget);
      return owner == null
          ? placed
          : RestageIslandScope.keyed(owner, name, placed,
              items: path, appKey: widget.key);
    }
    final at = '$name#${path.join('.')}';
    _islands[at] = build ?? _builds[widget] ?? widget;
    _appKeys[at] = widget.key;
    final placed = widget;
    if (owner == null) return placed;
    final keyed = RestageIslandScope.keyed(owner, name, placed,
        items: path, appKey: widget.key);
    if (spots == null) return keyed;
    return Builder(
      builder: (context) =>
          listEquals(_IslandSpot.chainOf(context), spots) ? keyed : placed,
    );
  }

  /// Marks [value], placed by the build's read [id], so an island inside it
  /// knows which placement it is.
  Widget spot(int id, Widget value) => _IslandSpotScope(id: id, child: value);

  /// Marks each widget in [values], placed by the build's read [id], as
  /// [spot] does.
  List<Widget> spotEach(int id, Iterable<Widget> values) =>
      [for (final value in values) spot(id, value)];

  /// Places an app widget the design builds from its own factory as is.
  static Widget itself(Widget widget) => widget;

  final Map<String, Key?> _appKeys = {};

  /// [child], the content of a route the build pushes, carrying the event
  /// scopes of the surface this recording's mount shows.
  Widget route(Widget child) => authoring.recordedRoute(
        owner: owner,
        from: _mount,
        child: child,
      );

  /// A callback firing [event], as `context.surfaceEvent` does, on the
  /// surface this recording's mount shows.
  void Function([Object?]) surfaceEvent<T, V extends T>(
    SurfaceEvent<T> event, [
    V? value,
  ]) =>
      ([Object? widgetValue = authoring.noWidgetValue]) {
        final dispatched = authoring.withWidgetValue(value, widgetValue);
        _dispatch(
          event.id,
          switch (dispatched) {
            null => const <String, Object?>{},
            final Map<String, Object?> args => args,
            _ => <String, Object?>{'value': dispatched},
          },
          // Resolved as it fires: a step from its own context, any other
          // mount through the surface it hosts.
          otherwise: () => switch (_mount) {
            final mount? => authoring.fireSurfaceEventAt(
                mount, event.id, dispatched,
                recorded: true),
            null =>
              authoring.fireRecordedSurfaceEvent(owner, event.id, dispatched),
          },
        );
      };

  // A mount a paywall renders dispatches through that paywall; any other
  // mount fires the helper as its build would have.
  void _dispatch(
    String name,
    Map<String, Object?> args, {
    required VoidCallback otherwise,
  }) {
    final owner = this.owner;
    if (owner == null ||
        !RestagePaywallEventDispatchAuthority.rendersMount(owner)) {
      return otherwise();
    }
    void onRefused(AuthoringRefusalKind refusal) =>
        reportAuthoringRefusal(refusal: refusal, recorded: true);
    final dispatcher = RestagePaywallEventDispatchAuthority.captureFor(owner,
        onRefused: onRefused);
    if (dispatcher != null) return dispatcher(name, args);
    onRefused(AuthoringRefusalKind.missingDispatcher);
  }

  /// Notes that the design builds the island [widget] stands for with
  /// [build], and returns [widget].
  T built<T extends Widget>(
    T widget,
    Widget Function(BuildContext context, DataSource source) build,
  ) {
    _builds[widget] = build;
    return widget;
  }

  final Expando<Widget Function(BuildContext, DataSource)> _builds = Expando();

  /// The island [name] at the item [path], as the build recorded it; empty
  /// where the build never reached it.
  Widget islandAt(
    String name,
    List<int> path,
    BuildContext context,
    DataSource source,
  ) =>
      switch (_islands['$name#${path.join('.')}']) {
        final Widget widget => _placed(name, path, context, widget),
        final Widget Function(BuildContext, DataSource) build =>
          _placed(name, path, context, build(context, source)),
        _ => const SizedBox.shrink(),
      };

  Widget _placed(
      String name, List<int> path, BuildContext context, Widget island) {
    final at = '$name#${path.join('.')}';
    if (_appKeys[at] case final key?) RestageIslandScope.appKeys[island] = key;
    return island;
  }

  /// Records [value] under [key] in the map of [items]' current item, or at
  /// the top when [items] is null, and returns it. A null [key] is an
  /// iteration the design reads nothing from.
  T value<T>(String? key, T value, [String? items]) {
    if (key != null) _frame(items)[key] = restageHostValue(value);
    return value;
  }

  /// Records that a condition held as [held] and returns [elements].
  List<T> mark<T>(String? key, bool held, List<T> elements, [String? items]) {
    value(key, held, items);
    return elements;
  }

  /// Records that a condition held as [held] and returns [result].
  T taken<T>(String? key, bool held, T result, [String? items]) {
    value(key, held, items);
    return result;
  }

  /// Records each of [values] under its key and returns [result].
  T exposing<T>(Map<String, Object?> values, T result) {
    for (final MapEntry(:key, :value) in values.entries) {
      this.value(key, value);
    }
    return result;
  }

  /// The native objects recorded so far and later, each declared by
  /// [contract], beside the [fixed] ones: a live view, so a builder that
  /// runs later adds its own.
  Map<String, NativeBinding<Object?>> bindings(
          NativeBindingContract Function(String key) contract,
          [Map<String, NativeBinding<Object?>> fixed = const {}]) =>
      _RecordedBindings(natives, contract, fixed);

  /// The text scalers recorded, by key.
  final Map<String, TextScaler?> scalers = {};

  /// Records the text scaler [value] under [key] and returns it.
  T scaler<T extends TextScaler?>(String? key, T value) {
    if (key != null) scalers[key] = value;
    return value;
  }

  /// Records which return the build took and returns [value].
  T branch<T>(String? key, int index, T value) {
    if (key != null) values[key] = index;
    return value;
  }

  /// Records [value] as a native object and returns it.
  T native<T>(
    String? key,
    T value, {
    String? items,
    required String type,
    required bool nullable,
  }) {
    if (key == null) return value;
    if (items == null) {
      natives[key] = value;
      return value;
    }
    final at = '$key#${_cursors[items]!.path.join('.')}';
    natives[at] = value;
    _frame(items)[key] = <String, Object?>{
      'kind': 'nativeBinding',
      'key': at,
      'type': type,
      'nullable': nullable,
    };
    return value;
  }

  /// Walks [iterable] as the app does, opening one item map per element in
  /// the list under [key], inside [outer]'s current item when given; each
  /// item map holds its position under [positions].
  Iterable<E> items<E>(
    String key,
    Iterable<E> iterable, [
    String? outer,
    List<String> positions = const [],
  ]) {
    final list = <Map<String, Object?>>[];
    final parent = outer == null ? null : _cursors[outer]!;
    // A second loop over the same key adds to the items the first opened.
    final existing = _frame(outer)[key];
    final into = existing is List<Map<String, Object?>> ? existing : list;
    _frame(outer)[key] = into;
    return _Recorded(iterable, () {
      final cursor = _Cursor(into, [...?parent?.path], positions);
      _cursors[key] = cursor;
      return cursor;
    });
  }

  final List<(int, _Snapshot)> _runs = [];

  /// Starts a run of the kept builder [id]: its first run notes what was
  /// recorded before it, and each later run starts again from there.
  void frame(int id) {
    final index = _runs.indexWhere((run) => run.$1 == id);
    if (index < 0) {
      _runs.add((id, _snapshot()));
      return;
    }
    final snapshot = _runs[index].$2;
    _runs.length = index + 1;
    values
      ..clear()
      ..addAll(_copy(snapshot.values));
    natives
      ..clear()
      ..addAll(snapshot.natives);
    scalers
      ..clear()
      ..addAll(snapshot.scalers);
    _islands
      ..clear()
      ..addAll(snapshot.islands);
    _appKeys
      ..clear()
      ..addAll(snapshot.appKeys);
    _cursors.clear();
    _positions.clear();
  }

  _Snapshot _snapshot() => (
        values: _copy(values),
        natives: {...natives},
        scalers: {...scalers},
        islands: {..._islands},
        appKeys: {..._appKeys},
      );

  static Map<String, Object?> _copy(Map<String, Object?> map) => {
        for (final MapEntry(:key, :value) in map.entries)
          key: value is List<Map<String, Object?>>
              ? [for (final item in value) _copy(item)]
              : value,
      };

  final Map<int, int> _positions = {};

  /// Walks [iterable] as the app does, noting the position of each element
  /// in the loop [id] the design unrolls.
  Iterable<E> unrolled<E>(int id, Iterable<E> iterable) sync* {
    var position = 0;
    for (final element in iterable) {
      _positions[id] = position++;
      yield element;
    }
  }

  /// The key of the value the current iteration of [loops] records, from
  /// [keys] by position, or null for an iteration the design reads nothing
  /// from there.
  String? unrolledKey(Map<String, String> keys, List<int> loops) =>
      keys[loops.map((loop) => _positions[loop]).join('.')];

  /// The map [items]' current item records into.
  Map<String, Object?> _frame(String? items) =>
      items == null ? values : _cursors[items]!.frame;

  /// The item maps a loop over a screen input recorded, by position.
  Map<String, Object?> itemAt(String key, int index) {
    final recorded = values[key];
    return recorded is List<Map<String, Object?>> && index < recorded.length
        ? recorded[index]
        : const {};
  }
}

typedef _Snapshot = ({
  Map<String, Object?> values,
  Map<String, Object?> natives,
  Map<String, TextScaler?> scalers,
  Map<String, Object> islands,
  Map<String, Key?> appKeys,
});

final class _Cursor {
  _Cursor(this.list, this.outer, this.positions);

  final List<Map<String, Object?>> list;
  final List<int> outer;
  final List<String> positions;
  int index = -1;
  Map<String, Object?> frame = {};

  List<int> get path => [...outer, index];

  void advance() {
    index++;
    if (index < list.length) {
      frame = list[index];
    } else {
      frame = <String, Object?>{};
      list.add(frame);
    }
    for (final key in positions) {
      frame[key] = index;
    }
  }
}

final class _Recorded<E> extends Iterable<E> {
  _Recorded(this._inner, this._open);

  final Iterable<E> _inner;
  final _Cursor Function() _open;

  @override
  Iterator<E> get iterator => _RecordedIterator(_inner.iterator, _open());
}

final class _RecordedIterator<E> implements Iterator<E> {
  _RecordedIterator(this._inner, this._cursor);

  final Iterator<E> _inner;
  final _Cursor _cursor;

  @override
  E get current => _inner.current;

  @override
  bool moveNext() {
    if (!_inner.moveNext()) return false;
    _cursor.advance();
    return true;
  }
}

/// Calls [use] with [arguments], evaluated once where the call is written.
R restageOnce<A, R>(A arguments, R Function(A arguments) use) => use(arguments);

final class _RecordedBindings
    extends UnmodifiableMapBase<String, NativeBinding<Object?>> {
  _RecordedBindings(this._natives, this._contract, this._fixed);

  final Map<String, Object?> _natives;
  final NativeBindingContract Function(String key) _contract;
  final Map<String, NativeBinding<Object?>> _fixed;

  @override
  NativeBinding<Object?>? operator [](Object? key) =>
      _fixed[key] ??
      (key is String && _natives.containsKey(key)
          ? NativeBinding(contract: _contract(key), value: _natives[key])
          : null);

  @override
  Iterable<String> get keys => {..._fixed.keys, ..._natives.keys};
}

// Gives [child] the reads it was placed through, its own [id] last.
final class _IslandSpotScope extends StatelessWidget {
  const _IslandSpotScope({required this.id, required this.child});

  final int id;
  final Widget child;

  @override
  Widget build(BuildContext context) => _IslandSpot(
        chain: [..._IslandSpot.chainOf(context), id],
        child: child,
      );
}

final class _IslandSpot extends InheritedWidget {
  const _IslandSpot({required this.chain, required super.child});

  final List<int> chain;

  // The reads above [context], outermost first.
  static List<int> chainOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_IslandSpot>()?.chain ?? const [];

  @override
  bool updateShouldNotify(_IslandSpot oldWidget) => false;
}
