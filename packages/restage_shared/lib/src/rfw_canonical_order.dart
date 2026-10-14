import 'package:restage_shared/src/rfw_formats.dart';

/// Returns [library] with every map's keys sorted (recursively) and its
/// declarations sorted by name. List, switch-case and import order are kept.
RemoteWidgetLibrary canonicalizeLibrary(RemoteWidgetLibrary library) {
  final widgets = [
    for (final widget in library.widgets)
      WidgetDeclaration(
        widget.name,
        widget.initialState == null ? null : _map(widget.initialState!),
        _node(widget.root) as BlobNode,
      ),
  ]..sort((a, b) => a.name.compareTo(b.name));
  return RemoteWidgetLibrary(library.imports, widgets);
}

DynamicMap _map(Map<String, Object?> map) {
  final keys = map.keys.toList()..sort();
  return {for (final key in keys) key: _node(map[key])};
}

Object? _node(Object? value) => switch (value) {
      final Map<String, Object?> map => _map(map),
      final List<Object?> list => [for (final item in list) _node(item)],
      ConstructorCall() => ConstructorCall(value.name, _map(value.arguments)),
      EventHandler() =>
        EventHandler(value.eventName, _map(value.eventArguments)),
      SetStateHandler() =>
        SetStateHandler(value.stateReference, _node(value.value)!),
      Loop() => Loop(_node(value.input)!, _node(value.output)!),
      Switch() => Switch(_node(value.input)!, {
          for (final entry in value.outputs.entries)
            entry.key: _node(entry.value)!,
        }),
      WidgetBuilderDeclaration() => WidgetBuilderDeclaration(
          value.argumentName,
          _node(value.widget)! as BlobNode,
        ),
      _ => value,
    };
