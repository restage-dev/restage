import 'package:restage_shared/src/rfw_formats.dart';

/// The argument of a split widget's wrapper that holds the widget's body.
const String kSplitWidgetBodyArgument = 'restageWidget';

/// The suffix that names a split widget's wrapper after the widget.
const String kSplitWrapperSuffix = '__split';

/// Where rendering a design places one island relative to split widgets'
/// bodies: the widgets whose wrapper body places it, and how many times it
/// is placed outside every such body.
typedef RfwSplitIslandPlacements = ({Set<String> owners, int outside});

/// [RfwSplitIslandPlacements] of every constructor [root] of [library]
/// places, where [isSplitWrapper] names the wrappers of split widgets.
Map<String, RfwSplitIslandPlacements> rfwSplitIslandPlacements(
  RemoteWidgetLibrary library,
  String root, {
  required bool Function(String name) isSplitWrapper,
}) {
  final declarations = {
    for (final widget in library.widgets) widget.name: widget.root,
  };
  final owners = <String, Set<String>>{};
  final outside = <String, int>{};

  // [owner] is the split widget whose body [value] is written in, if any.
  void visit(
    Object? value,
    Set<String> expanding,
    _SplitScope scope,
    String? owner,
  ) {
    void add(Object? child, {_SplitScope? within, String? by}) =>
        visit(child, expanding, within ?? scope, by ?? owner);
    switch (value) {
      case ConstructorCall(:final name, :final arguments):
        if (owner == null) {
          outside[name] = (outside[name] ?? 0) + 1;
        } else {
          (owners[name] ??= {}).add(owner);
        }
        if (isSplitWrapper(name)) {
          final widget =
              name.substring(0, name.lastIndexOf(kSplitWrapperSuffix));
          for (final MapEntry(key: argument, value: child)
              in arguments.entries) {
            visit(
              child,
              expanding,
              scope,
              argument == kSplitWidgetBodyArgument ? widget : owner,
            );
          }
        } else if (declarations[name] case final local?
            when expanding.add(name)) {
          visit(local, expanding, _SplitScope(arguments, scope, owner, []),
              owner);
          expanding.remove(name);
        } else {
          add(arguments);
        }
      // An argument renders where the caller wrote it.
      case ArgsReference(:final parts) when scope.args != null:
        visit(_read(scope.args, parts), expanding, scope.outer!, scope.owner);
      case LoopReference(:final loop, :final parts)
          when loop < scope.loops.length:
        final (:input, :within, by: loopOwner) =
            scope.loops[scope.loops.length - 1 - loop];
        visit(
          input is List<Object?>
              ? [for (final item in input) _read(item, parts)]
              : _read(input, parts),
          expanding,
          within,
          loopOwner,
        );
      case Loop(:final input, :final output):
        add(input);
        add(
          output,
          within: _SplitScope(scope.args, scope.outer, scope.owner,
              [...scope.loops, (input: input, within: scope, by: owner)]),
        );
      case WidgetBuilderDeclaration(:final widget):
        add(widget);
      case Switch(:final input, :final outputs):
        add(input);
        outputs.values.forEach(add);
      case final Map<Object?, Object?> map:
        map.values.forEach(add);
      case final List<Object?> list:
        list.forEach(add);
    }
  }

  if (declarations[root] case final node?) {
    visit(node, {root}, const _SplitScope(null, null, null, []), null);
  }
  return {
    for (final name in {...owners.keys, ...outside.keys})
      name: (owners: owners[name] ?? const {}, outside: outside[name] ?? 0),
  };
}

// The arguments of the local widget being expanded, the scope they are read
// in and the split widget they were written in, and the loops around a value.
final class _SplitScope {
  const _SplitScope(this.args, this.outer, this.owner, this.loops);
  final Map<String, Object?>? args;
  final _SplitScope? outer;
  final String? owner;
  final List<({Object? input, _SplitScope within, String? by})> loops;
}

Object? _read(Object? value, List<Object> parts) {
  for (final part in parts) {
    switch ((value, part)) {
      case (final Map<Object?, Object?> map, final String key):
        value = map[key];
      case (final List<Object?> list, final int index)
          when index >= 0 && index < list.length:
        value = list[index];
      default:
        return value;
    }
  }
  return value;
}

/// Whether rendering [root] of [library] places an island outside every split
/// widget's body, where only the surface's own generated widget provides it.
bool rfwPlacesIslandOutsideSplitBodies(
  RemoteWidgetLibrary library,
  String root, {
  required bool Function(String name) isSplitWrapper,
  required bool Function(String name) isIsland,
}) =>
    rfwSplitIslandPlacements(library, root, isSplitWrapper: isSplitWrapper)
        .entries
        .any((entry) => entry.value.outside > 0 && isIsland(entry.key));
