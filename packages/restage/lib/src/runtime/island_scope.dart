import 'package:flutter/widgets.dart';
import 'package:restage_core/restage_core.dart'
    show RestageDecoders, RestageIslandStage;

import 'island_visit.dart';
import 'package:rfw/rfw.dart' show DataSource, LocalWidgetBuilder;

/// Supplies, by name, the builders of the widgets a published surface renders
/// from the app's own code.
///
/// A generated surface mount puts one above the published content; an island
/// factory finds its builder through [build].
final class RestageIslandScope extends InheritedWidget {
  /// Creates a scope for [builders] over [child]; [owner] is the mount the
  /// islands belong to, which keeps each island's identity across versions.
  const RestageIslandScope({
    required this.builders,
    required super.child,
    this.owner,
    this.explicitEvents = false,
    super.key,
  });

  /// Island builders by island name.
  final Map<String, LocalWidgetBuilder> builders;

  /// The mount the islands belong to.
  final Object? owner;

  /// Whether the mount's own build dispatches its events through [owner], so
  /// only islands that fire events build inside the event registration.
  final bool explicitEvents;

  /// Builds the island [name] from the nearest scope. Throws a [StateError]
  /// with [missing] when no scope above [context] has it.
  ///
  /// In a version staged beside the shown one the island waits for
  /// promotion; once shown it keeps its element across versions of the
  /// same mount.
  static Widget build(
    String name,
    String missing,
    BuildContext context,
    DataSource source,
  ) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<RestageIslandScope>();
    final builder = scope?.builders[name];
    if (builder == null) throw StateError(missing);
    if (RestageIslandStage.isCandidate(context)) return const SizedBox.shrink();
    final owner = scope!.owner;
    final island = builder(context, source);
    if (owner == null) return island;
    // Placed once per version and visit, an island keeps its element
    // wherever it moves.
    return KeyedSubtree(
      key: _keyOf(owner, name, _itemsOf(source), context, appKeys[island]),
      child: island,
    );
  }

  /// Builds a split widget's wrapper the design places, keyed as the
  /// recording keys its placement in the fallback, so its State moves with
  /// it between the design and the fallback and across versions.
  static Widget split(
    BuildContext context,
    DataSource source,
    Widget Function() build,
  ) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<RestageIslandScope>();
    // A staged version decodes the widget, so a bad design fails before it
    // is shown, but builds none of its app code: once shown it builds the
    // widget, taking its element where the shown one held it.
    if (RestageIslandStage.isCandidate(context)) {
      build();
      return const SizedBox.shrink();
    }
    final name = source.v<String>(const ['restageIsland']);
    final owner = scope?.owner;
    if (name == null || owner == null) return build();
    // The app's own key, which the definition passes on, identifies it as
    // it does an island.
    final appKey = RestageDecoders.nativeBinding<Key>(
        context, source, const <Object>['key'],
        type: 'flutter.Key');
    return KeyedSubtree(
      key: _keyOf(owner, name, _itemsOf(source), context, appKey),
      child: build(),
    );
  }

  // The placement's position in each loop around it, outermost first.
  static List<int> _itemsOf(DataSource source) => [
        for (var index = 0;
            index < source.length(const ['restageItems']);
            index++)
          source.v<int>(['restageItems', index])!,
      ];

  /// The key the app gives each island widget a recording builds, which
  /// identifies it in place of its position.
  static final appKeys = Expando<Key>();

  /// What shows the version [context] sits in, if a host marks it; the same
  /// object for every version that host shows.
  static Object? hostOf(BuildContext context) =>
      (RestageIslandStage.stageOf(context)?.widget as RestageIslandStage?)
          ?.host;

  /// Keys [island], the app's own widget in [owner]'s compiled fallback, as
  /// the island [name] at [items], its position in each loop around it, so
  /// it keeps its element when published content replaces the fallback.
  /// An island the app gives [appKey] is identified by it, as Flutter
  /// matches elements, in place of its position in the innermost loop.
  static Widget keyed(
    Object owner,
    String name,
    Widget island, {
    List<int> items = const [],
    Key? appKey,
  }) =>
      Builder(
        builder: (context) => KeyedSubtree(
          key: _keyOf(owner, name, items, context, appKey),
          child: island,
        ),
      );

  static GlobalKey _keyOf(
    Object owner,
    String name,
    List<int> items,
    BuildContext context,
    Key? appKey,
  ) {
    final visit = IslandVisit.of(context);
    final Object at = appKey == null
        ? '$name/${items.join('/')}${visit == null ? '' : '@$visit'}'
        // Flutter matches a key among its siblings: in place of the
        // innermost position, beside the outer ones.
        : (
            name,
            appKey,
            items.isEmpty ? '' : items.sublist(0, items.length - 1).join('/'),
            visit,
          );
    return (_keys[owner] ??= {})[at] ??= GlobalKey(debugLabel: name);
  }

  // Each island's key, per mount, island and app key or loop position.
  static final _keys = Expando<Map<Object, GlobalKey>>();

  /// Forgets [owner]'s island keys that no mounted element holds, as a build
  /// of the mount starts: an identity the app no longer gives has no element.
  static void forgetUnmounted(Object owner) =>
      _keys[owner]?.removeWhere((_, key) => key.currentContext == null);

  /// How many island keys [owner] holds.
  @visibleForTesting
  static int debugKeyCount(Object owner) => _keys[owner]?.length ?? 0;

  @override
  bool updateShouldNotify(RestageIslandScope oldWidget) =>
      !identical(builders, oldWidget.builders);
}

/// Stands in for an island that needs its surface's mount to render, showing
/// [label] and the published [children] it holds.
final class RestageIslandPlaceholder extends StatelessWidget {
  /// Creates a placeholder.
  const RestageIslandPlaceholder({
    required this.label,
    this.children = const [],
    super.key,
  });

  /// The widget the island renders in the app.
  final String label;

  /// The island's published slots.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0x66888888)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(label, textAlign: TextAlign.center),
            ...children,
          ],
        ),
      );
}
