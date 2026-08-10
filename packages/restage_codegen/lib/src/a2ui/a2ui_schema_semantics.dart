import 'package:restage_codegen/src/a2ui/a2ui_schema_node.dart';

/// Synthetic definition id used when a widget schema hoists its anonymous
/// object root alongside recursive definitions.
const String a2uiSyntheticRootDefinitionId = '__a2ui_root__';

/// Assigns the emitter's collision-safe, readable `$defs` keys.
///
/// Canonical ids are sorted before assignment, so same-named types from
/// different libraries deterministically become `Node`, `Node_2`, and so on.
Map<String, String> assignA2uiSafeDefinitionKeys(
  Iterable<String> canonicalIds,
) {
  final keys = <String, String>{};
  final used = <String>{};
  final ids = canonicalIds.toSet().toList()..sort();
  for (final id in ids) {
    final hash = id.indexOf('#');
    var symbol = hash < 0 ? id : id.substring(hash + 1);
    final generic = symbol.indexOf('<');
    if (generic >= 0) symbol = symbol.substring(0, generic);
    final sanitized = symbol.replaceAll(RegExp('[^A-Za-z0-9_]'), '_');
    final base = sanitized.isEmpty ? 'def' : sanitized;
    var key = base;
    var suffix = 2;
    while (used.contains(key)) {
      key = '${base}_$suffix';
      suffix++;
    }
    used.add(key);
    keys[id] = key;
  }
  return keys;
}

/// Whether [fieldName] collides with GenUI's flattened built-in component
/// envelope.
///
/// Customer component fields live under `props` and do not use this
/// reservation. For flat built-ins it applies only to top-level widget field
/// roots; nested rich-data members remain ordinary schema fields.
bool isReservedA2uiComponentEnvelopeField(String fieldName) =>
    fieldName == 'id' || fieldName == 'component';

/// Whether [node] is the analyzer/catalog leaf admitted as `List<scalar>`.
bool isA2uiScalarListNode(A2uiSchemaNode? node) =>
    node is ListNode && node.element is ScalarNode;

/// Whether a bound data field exposes GenUI's literal/path/call reference
/// envelope in the emitted schema.
///
/// Every scalar list is a reactive binding. Scalar and enum leaves expose the
/// same envelope only when paired with a write-back callback.
bool a2uiUsesValueReferenceSchema(
  A2uiSchemaNode node, {
  required bool writeBack,
}) =>
    isA2uiScalarListNode(node) ||
    (writeBack && (node is ScalarNode || node is EnumNode));
