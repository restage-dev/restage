/// The reserved-key denylist that keeps host-supplied render context
/// (`data.context.*`) out of the analytics wire.
///
/// Per the host-render-context boundary, `data.context.*` is local, inert,
/// host-supplied render data — it must never be uploaded. The analytics
/// transport serialises arbitrary author-supplied event payloads (e.g. a custom
/// event spreads its `args`), so omission is not enough: a denylist drops the
/// reserved namespaces at **both** the SDK transport and the ingest filter.
///
/// The guard is intentionally **broad** (the safe direction): the `data` and
/// `context` namespaces never legitimately carry analytics properties, so the
/// whole top-level `data.*` / `context.*` space is dropped — covering a
/// top-level `{'data': {'context': ...}}` value and a flattened
/// `'data.context.x'` key.
library;

/// Reserved property keys.
const Set<String> kReservedPropertyKeys = <String>{
  'data',
  'context',
  'experimentId',
  'variantId',
  'experimentEpoch',
};

const _topLevelNamespaceKeys = <String>{'data', 'context'};

bool _isTopLevelReserved(String key) {
  // Case-insensitive + whitespace-trimmed so property keys cannot bypass the
  // denylist. `data` and `context` also reserve their dotted namespaces.
  final normalized = key.trim().toLowerCase();
  return kReservedPropertyKeys.any(
        (reservedKey) => reservedKey.toLowerCase() == normalized,
      ) ||
      normalized.startsWith('data.') ||
      normalized.startsWith('context.');
}

bool _isRetiredPropertyKey(String key) {
  final normalized = key.trim().toLowerCase();
  return kReservedPropertyKeys.any(
    (reservedKey) =>
        !_topLevelNamespaceKeys.contains(reservedKey) &&
        reservedKey.toLowerCase() == normalized,
  );
}

/// Whether [properties] contains any reserved (render-context) key.
bool containsReservedKey(Map<String, Object?> properties) {
  for (final key in properties.keys) {
    if (_isTopLevelReserved(key)) return true;
  }
  return false;
}

/// Returns a new map with top-level namespaces and retired property keys
/// removed. Retired property keys are removed at every map depth.
Map<String, Object?> scrubReservedKeys(Map<String, Object?> properties) {
  final result = <String, Object?>{};
  for (final entry in properties.entries) {
    if (_isTopLevelReserved(entry.key)) continue;
    result[entry.key] = _scrubValue(entry.value);
  }
  return result;
}

Object? _scrubValue(Object? value) {
  if (value is Map<Object?, Object?>) return _scrubMap(value);
  if (value is List<Object?>) {
    return <Object?>[for (final item in value) _scrubValue(item)];
  }
  return value;
}

Map<Object?, Object?> _scrubMap(Map<Object?, Object?> value) {
  final result = <Object?, Object?>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is String && _isRetiredPropertyKey(key)) continue;
    result[key] = _scrubValue(entry.value);
  }
  return result;
}
