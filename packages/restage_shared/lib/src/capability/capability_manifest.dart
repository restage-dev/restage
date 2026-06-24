import 'package:meta/meta.dart';

/// One custom widget library a compiled surface requires, with the minimum
/// capability version of that library a client must have installed to render
/// the surface faithfully.
///
/// [minVersion] is a monotonic integer capability version — the library's own
/// render-support line — NOT a published package semantic version.
@immutable
final class LibraryRequirement {
  /// Creates a library requirement. [namespace] must be non-empty and
  /// [minVersion] a positive capability version.
  const LibraryRequirement({required this.namespace, required this.minVersion})
      : assert(namespace.length > 0, 'namespace must not be empty'),
        assert(
          minVersion >= 1,
          'minVersion must be a positive capability version',
        );

  /// Decodes a requirement from its JSON wire form.
  factory LibraryRequirement.fromJson(Map<String, dynamic> json) {
    final namespace = json['namespace'];
    final minVersion = json['minVersion'];
    if (namespace is! String || minVersion is! int) {
      throw FormatException('malformed LibraryRequirement: $json');
    }
    return LibraryRequirement(namespace: namespace, minVersion: minVersion);
  }

  /// Library namespace, e.g. `acme.widgets`.
  final String namespace;

  /// Minimum monotonic capability version of the library required.
  final int minVersion;

  /// JSON wire form.
  Map<String, dynamic> toJson() => {
        'namespace': namespace,
        'minVersion': minVersion,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LibraryRequirement &&
          other.namespace == namespace &&
          other.minVersion == minVersion;

  @override
  int get hashCode => Object.hash(namespace, minVersion);
}

/// What a compiled surface requires to render — a **format-general** value
/// type, assuming neither a particular delivery format nor a particular
/// surface kind. Targets (the native wire, A2UI) carry it their own way.
///
/// A client can render the surface iff its installed built-in catalog content
/// version is at least [builtInFloor] AND every entry in [requiredLibraries]
/// is satisfied by an installed library at or above its `minVersion`.
@immutable
final class CapabilityManifest {
  /// Creates a manifest. [requiredLibraries] is canonicalized to namespace
  /// order so the manifest encodes deterministically and value-compares
  /// independent of input order.
  ///
  /// Throws [ArgumentError] if [builtInFloor] is not a positive content-version
  /// floor. The invariant is enforced in release builds too, not only via
  /// [assert].
  factory CapabilityManifest({
    required int builtInFloor,
    required List<LibraryRequirement> requiredLibraries,
  }) {
    if (builtInFloor < 1) {
      throw ArgumentError.value(
        builtInFloor,
        'builtInFloor',
        'must be a positive content-version floor',
      );
    }
    return CapabilityManifest._(
      builtInFloor: builtInFloor,
      requiredLibraries: requiredLibraries,
    );
  }

  CapabilityManifest._({
    required this.builtInFloor,
    required List<LibraryRequirement> requiredLibraries,
  })  : assert(
          builtInFloor >= 1,
          'builtInFloor must be a positive content-version floor',
        ),
        requiredLibraries = List.unmodifiable(
          List<LibraryRequirement>.of(requiredLibraries)
            ..sort((a, b) => a.namespace.compareTo(b.namespace)),
        );

  /// Decodes a manifest from its JSON wire form. An absent `requiredLibraries`
  /// decodes to the empty list (tolerant of an encoder that omitted it),
  /// though the canonical encoder always emits the list.
  factory CapabilityManifest.fromJson(Map<String, dynamic> json) {
    final builtInFloor = json['builtInFloor'];
    if (builtInFloor is! int) {
      throw FormatException('malformed CapabilityManifest: $json');
    }
    final raw = json['requiredLibraries'];
    final List<LibraryRequirement> requiredLibraries;
    if (raw == null) {
      requiredLibraries = const [];
    } else if (raw is List) {
      requiredLibraries = [
        for (final entry in raw)
          LibraryRequirement.fromJson(entry as Map<String, dynamic>),
      ];
    } else {
      throw FormatException('requiredLibraries must be a list: $raw');
    }
    return CapabilityManifest(
      builtInFloor: builtInFloor,
      requiredLibraries: requiredLibraries,
    );
  }

  /// Minimum built-in catalog content version the surface requires (the
  /// maximum `sinceVersion` over the built-in widgets it uses).
  final int builtInFloor;

  /// The required custom libraries, canonical: sorted by namespace, and
  /// possibly empty. Always present (never null).
  final List<LibraryRequirement> requiredLibraries;

  /// JSON wire form. `requiredLibraries` is **always** emitted — including the
  /// empty list — so a consumer never has to distinguish "absent" from
  /// "empty", and the encoding is deterministic for golden comparison.
  Map<String, dynamic> toJson() => {
        'builtInFloor': builtInFloor,
        'requiredLibraries': requiredLibraries.map((r) => r.toJson()).toList(),
      };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! CapabilityManifest) return false;
    if (other.builtInFloor != builtInFloor) return false;
    if (other.requiredLibraries.length != requiredLibraries.length) {
      return false;
    }
    for (var i = 0; i < requiredLibraries.length; i++) {
      if (other.requiredLibraries[i] != requiredLibraries[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(builtInFloor, Object.hashAll(requiredLibraries));
}
