import 'dart:collection';

import 'package:meta/meta.dart';
import 'package:restage_codegen/src/a2ui/a2ui_protocol.dart';

/// One component in an emitted A2UI catalog: a component [name] and its
/// JSON-Schema [dataSchema] (the object schema the model is constrained to
/// when emitting that component).
///
/// At this milestone the [dataSchema] is the discriminator-only object schema
/// (just the `component` const). The per-property schema body — derived from
/// the widget's catalog properties — is layered on in a later milestone; this
/// type is the stable carrier either way.
///
/// This is part of the **shape-isolation surface**: the in-memory model of the
/// A2UI catalog the adapter projects to. It is plain data — it imports nothing
/// from the genui SDK and serializes to maps directly.
@immutable
final class A2uiComponent {
  /// Creates a component carrier.
  const A2uiComponent({required this.name, required this.dataSchema});

  /// The component name — the key under the catalog's `components` map and the
  /// value of the schema's `component` discriminator.
  final String name;

  /// The component's JSON-Schema object (already a JSON-encodable map).
  final Map<String, Object?> dataSchema;
}

/// One custom library present in an emitted A2UI catalog, with the capability
/// [version] of that library the catalog provides.
///
/// This is the **available** (present) counterpart to the format-general
/// `LibraryRequirement` (a payload's **required** minimum). Same shape
/// (namespace + a monotonic int), distinct semantics: this is the version the
/// installed catalog HAS, against which a payload's required `minVersion` is
/// satisfied. Keeping the two as distinct types keeps "available" and
/// "required" from being confused at a call site.
@immutable
final class A2uiLibraryCapability {
  /// Creates an available-library entry.
  const A2uiLibraryCapability({required this.namespace, required this.version})
      : assert(namespace.length > 0, 'namespace must not be empty'),
        assert(version >= 1, 'version must be a positive capability version');

  /// The custom library's namespace, e.g. `acme.widgets`.
  final String namespace;

  /// The capability version of the library the catalog provides.
  final int version;

  /// JSON wire form.
  Map<String, Object?> toJson() => {'namespace': namespace, 'version': version};

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is A2uiLibraryCapability &&
          other.namespace == namespace &&
          other.version == version;

  @override
  int get hashCode => Object.hash(namespace, version);
}

/// The Restage capability stamp travelling with an emitted A2UI catalog.
///
/// The A2UI catalog format has no native home for a capability stamp
/// (versioning is catalog-wide via the catalog id; there is no per-component or
/// per-library version field), so Restage carries the capability metadata in a
/// sidecar. The stamp mirrors the format-general `CapabilityManifest`'s **two
/// axes**, describing what the installed catalog PROVIDES:
///  * [catalogContentVersion] — the built-in content version (the available
///    counterpart to `CapabilityManifest.builtInFloor`). The adapter derives
///    this from the catalog's built-in widgets via the single canonical
///    `contentVersionOf` formula, **not** by reading the runtime SDK's
///    `RestageBuiltInCatalogCapabilities.currentVersion` — the build-time
///    toolchain must not import the runtime SDK (a layering + two-tier
///    licensing boundary). Both derive from the same committed catalog, so they
///    are equal by construction (`max-over-union == max-of-per-library-maxes`).
///  * [availableLibraries] — the present custom libraries with their capability
///    versions (the available counterpart to
///    `CapabilityManifest.requiredLibraries`). A one-axis stamp would fail open
///    for custom libraries — a payload requiring a custom library could not be
///    checked — so both axes are carried.
///
/// [perItemSinceVersion] additionally records each component's content version.
/// The app-side check reuses the format-general satisfaction relation:
/// `payload.builtInFloor <= catalogContentVersion` AND every
/// `payload.requiredLibraries[r]` matched by an [availableLibraries] entry at
/// `version >= r.minVersion` — identical to the runtime resolver's two-axis
/// check by construction.
@immutable
final class RestageCapabilityStamp {
  /// Creates a stamp, canonicalizing both list/map axes (sorted) so the encoded
  /// form is deterministic for golden comparison.
  RestageCapabilityStamp({
    required this.catalogContentVersion,
    required List<A2uiLibraryCapability> availableLibraries,
    required Map<String, int> perItemSinceVersion,
  })  : assert(
          catalogContentVersion >= 1,
          'catalogContentVersion must be a positive content-version floor',
        ),
        availableLibraries = List.unmodifiable(
          List<A2uiLibraryCapability>.of(availableLibraries)
            ..sort((a, b) => a.namespace.compareTo(b.namespace)),
        ),
        perItemSinceVersion = UnmodifiableMapView(
          SplayTreeMap<String, int>.of(perItemSinceVersion),
        );

  /// The built-in content version the catalog provides (the available
  /// counterpart to `CapabilityManifest.builtInFloor`).
  final int catalogContentVersion;

  /// The present custom libraries with their capability versions, sorted by
  /// namespace. Always present (possibly empty).
  final List<A2uiLibraryCapability> availableLibraries;

  /// Each component's content version, keyed by component name, sorted by name.
  final Map<String, int> perItemSinceVersion;

  /// JSON wire form. `availableLibraries` is **always** emitted — including the
  /// empty list — mirroring the manifest's always-emit rule, so a consumer
  /// never distinguishes "absent" from "empty".
  Map<String, Object?> toJson() => {
        'catalogContentVersion': catalogContentVersion,
        'availableLibraries': [
          for (final library in availableLibraries) library.toJson(),
        ],
        'perItemSinceVersion': Map<String, int>.of(perItemSinceVersion),
      };
}

/// An emitted A2UI catalog wrapped in its Restage capability stamp.
///
/// `toJson` produces `{ restageCapability, a2uiCatalog }`, where `a2uiCatalog`
/// is the A2UI protocol catalog document (a JSON-Schema doc whose `components`
/// map each component name to its schema) for the pinned protocol version, and
/// `restageCapability` is the sidecar two-axis stamp.
@immutable
final class RestageStampedA2uiCatalog {
  /// Creates a stamped catalog from its [stamp] and [components].
  const RestageStampedA2uiCatalog({
    required this.stamp,
    required this.components,
  });

  /// The capability stamp travelling with the catalog.
  final RestageCapabilityStamp stamp;

  /// The catalog's components. Encoded in sorted-name order by [toJson].
  final List<A2uiComponent> components;

  /// The catalog document identifier (the A2UI `$id` / `catalogId`).
  ///
  /// **This is a document identifier, NEVER a capability authority** —
  /// capability decisions read [stamp], not this string. It is derived from the
  /// capability vector (built-in content version + the sorted custom-library
  /// versions) so it is deterministic and unique per distinct catalog: under
  /// the cumulative render-support invariant (an incompatible change forks a
  /// new version), the same capability vector denotes the same cumulative
  /// catalog content.
  String get documentId {
    final libraries = stamp.availableLibraries;
    if (libraries.isEmpty) {
      return 'restage:catalog/${stamp.catalogContentVersion}';
    }
    final librarySuffix =
        libraries.map((l) => '${l.namespace}@${l.version}').join('_');
    return 'restage:catalog/${stamp.catalogContentVersion}+$librarySuffix';
  }

  /// JSON wire form — `{ restageCapability, a2uiCatalog }`.
  Map<String, Object?> toJson() {
    final sorted = [...components]..sort((a, b) => a.name.compareTo(b.name));
    final id = documentId;
    return {
      'restageCapability': stamp.toJson(),
      'a2uiCatalog': {
        r'$schema': kA2uiSchemaDialect,
        r'$id': id,
        'title': 'Restage A2UI Catalog',
        'description':
            'A2UI component catalog generated from Restage widget source.',
        'catalogId': id,
        'a2uiProtocolVersion': kA2uiProtocolVersion,
        'components': {for (final c in sorted) c.name: c.dataSchema},
        'functions': <String, Object?>{},
      },
    };
  }
}
