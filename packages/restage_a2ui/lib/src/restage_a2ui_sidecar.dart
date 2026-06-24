import 'package:flutter/foundation.dart';
import 'package:restage_shared/restage_shared.dart';

/// The Restage capability sidecar wrapping a cached A2UI payload.
///
/// A2UI's envelope has no native home for a per-payload version stamp
/// (versioning is catalog-wide), so Restage wraps a cached payload in an
/// envelope of `restageCapability` (the required capability stamp:
/// `builtInFloor`, `requiredLibraries`, `perItemSinceVersion`) and `a2ui` (the
/// payload). The app caches the wrapper; the pre-render check reads
/// `restageCapability` before handing `a2ui` to the genui render seam.
///
/// `restageCapability` reuses the format-general [CapabilityManifest] for its
/// two axes (built-in floor + required custom libraries) — `requiredCatalogVersion`
/// in the A2UI design is `builtInFloor` here, the canonical term — plus
/// [perItemSinceVersion], the version each referenced component depends on.
@immutable
final class RestageA2uiSidecar {
  /// Creates a sidecar pairing the required [capability] (+ [perItemSinceVersion])
  /// with the wrapped [a2ui] payload.
  const RestageA2uiSidecar({
    required this.capability,
    required this.perItemSinceVersion,
    required this.a2ui,
  });

  /// The key under which the capability stamp travels in the envelope.
  static const String capabilityKey = 'restageCapability';

  /// The key under which the wrapped A2UI payload travels.
  static const String payloadKey = 'a2ui';

  /// Decodes a sidecar from its JSON envelope. Fails closed: a missing or
  /// malformed `restageCapability`/`a2ui` throws [FormatException] rather than
  /// yielding a partial sidecar the check would then treat as renderable.
  factory RestageA2uiSidecar.fromJson(Map<String, Object?> json) {
    final rawCapability = json[capabilityKey];
    if (rawCapability is! Map<String, Object?>) {
      throw FormatException(
        'malformed Restage A2UI sidecar: $capabilityKey must be an object, '
        'got ${rawCapability.runtimeType}',
      );
    }
    if (!json.containsKey(payloadKey)) {
      throw FormatException(
        'malformed Restage A2UI sidecar: missing $payloadKey payload',
      );
    }
    // CapabilityManifest.fromJson reads only builtInFloor + requiredLibraries
    // (it ignores the sibling perItemSinceVersion), and throws on a malformed
    // manifest — propagating the fail-closed contract.
    final manifest = CapabilityManifest.fromJson(rawCapability);
    final rawPerItem = rawCapability['perItemSinceVersion'];
    final Map<String, int> perItem;
    if (rawPerItem == null) {
      perItem = const {};
    } else if (rawPerItem is Map) {
      perItem = <String, int>{
        for (final entry in rawPerItem.entries)
          _perItemKey(entry.key): _perItemValue(entry.value),
      };
    } else {
      throw FormatException(
        'malformed Restage A2UI sidecar: perItemSinceVersion must be an '
        'object, got ${rawPerItem.runtimeType}',
      );
    }
    return RestageA2uiSidecar(
      capability: manifest,
      perItemSinceVersion: perItem,
      a2ui: json[payloadKey],
    );
  }

  static String _perItemKey(Object? key) {
    if (key is! String) {
      throw FormatException('perItemSinceVersion key must be a string: $key');
    }
    return key;
  }

  static int _perItemValue(Object? value) {
    if (value is! int) {
      throw FormatException('perItemSinceVersion value must be an int: $value');
    }
    return value;
  }

  /// Whether [json] is a Restage sidecar envelope (carries [capabilityKey]) as
  /// opposed to a raw A2UI payload. A non-map is never a sidecar.
  static bool isRestageSidecar(Object? json) =>
      json is Map && json.containsKey(capabilityKey);

  /// The payload's required capability — the two-axis required side.
  final CapabilityManifest capability;

  /// The version each referenced component depends on, keyed by component name.
  /// Carried for diagnostics and forward use; the binding check rests on the
  /// two-axis [capability] compare plus component existence (sound under the
  /// catalog's cumulative-render-support invariant).
  final Map<String, int> perItemSinceVersion;

  /// The wrapped A2UI payload (opaque JSON — a genui A2UI message / surface).
  final Object? a2ui;

  /// Encodes the sidecar to its JSON envelope. `requiredLibraries` and
  /// `perItemSinceVersion` are always emitted (including empty) so a consumer
  /// never distinguishes "absent" from "empty".
  Map<String, Object?> toJson() => {
    capabilityKey: {
      ...capability.toJson(),
      'perItemSinceVersion': Map<String, int>.of(perItemSinceVersion),
    },
    payloadKey: a2ui,
  };
}
