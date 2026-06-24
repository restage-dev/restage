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
/// whole top-level `data.*` / `context.*` space is dropped — covering both a
/// nested `{'data': {'context': ...}}` and a flattened `'data.context.x'` key.
library;

/// Top-level property keys that are always dropped.
const Set<String> kReservedPropertyKeys = <String>{'data', 'context'};

bool _isReserved(String key) {
  // Case-insensitive + whitespace-trimmed so `Data`, ` data`, `CONTEXT.x`, etc.
  // cannot bypass the denylist. The reserved namespaces are contract-reserved
  // at any casing; benign look-alikes (`database`, `contextual`) are unaffected
  // because the match is on the exact word or a `data.`/`context.` prefix.
  final k = key.trim().toLowerCase();
  return kReservedPropertyKeys.contains(k) ||
      k.startsWith('data.') ||
      k.startsWith('context.');
}

/// Whether [properties] contains any reserved (render-context) key.
bool containsReservedKey(Map<String, Object?> properties) {
  for (final key in properties.keys) {
    if (_isReserved(key)) return true;
  }
  return false;
}

/// Returns a new map with every reserved key removed. Non-mutating; benign
/// look-alikes (`database`, `contextual`, `metadata`) are preserved.
Map<String, Object?> scrubReservedKeys(Map<String, Object?> properties) {
  final result = <String, Object?>{};
  for (final entry in properties.entries) {
    if (_isReserved(entry.key)) continue;
    result[entry.key] = entry.value;
  }
  return result;
}
