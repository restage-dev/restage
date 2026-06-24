/// The A2UI component-type discriminator key. A component object carries its
/// widget type under this key (genui's `Component.fromJson` reads
/// `json['component']`; its schema matcher keys on the same property).
const String _componentDiscriminator = 'component';

/// The component-instance id key. A genui component object always carries one
/// (`Component.fromJson` requires `id`); a plain property bag does not — which
/// is how a real component object is told apart from arbitrary property data
/// that happens to contain a `component` key.
const String _componentIdKey = 'id';

/// Collects every widget type a (raw, unwrapped) A2UI payload references — the
/// universal half of the pre-render check, valid for ANY payload including one
/// a model generated live.
///
/// The walk recurses the payload JSON to find component objects wherever the
/// envelope places them — `components` as a list (an `UpdateComponents`
/// message) or a map (a `SurfaceDefinition`), at any depth — and collects the
/// String value under each component's [_componentDiscriminator] key. It is
/// shape-agnostic on purpose, depending only on the A2UI component-object
/// signature, so when the envelope shape churns only this walk moves. This is
/// the genui-shape-isolation point.
///
/// A discriminator is collected ONLY from a component object — a map carrying
/// both an [_componentIdKey] and a String [_componentDiscriminator] (genui's
/// `Component` always has both). A `component` key buried in a property value
/// (no `id`) is arbitrary data, not a referenced type, and is NOT collected —
/// so a valid payload is never falsely rejected. Instance ids and child-id
/// references are likewise not collected. A non-map / null input, or a
/// non-string discriminator, yields no type rather than throwing (fail-closed:
/// a type the walk could not read is treated as absent, which the existence
/// check rejects if it is actually referenced).
Set<String> a2uiReferencedWidgetTypes(Object? payloadJson) {
  final types = <String>{};
  _collect(payloadJson, types);
  return types;
}

void _collect(Object? node, Set<String> into) {
  if (node is Map) {
    final discriminator = node[_componentDiscriminator];
    // Only a component object (has both `id` and a String `component`)
    // contributes a referenced type — never a property bag that merely
    // contains a `component` key.
    if (discriminator is String && node.containsKey(_componentIdKey)) {
      into.add(discriminator);
    }
    for (final value in node.values) {
      _collect(value, into);
    }
  } else if (node is List) {
    for (final element in node) {
      _collect(element, into);
    }
  }
}
