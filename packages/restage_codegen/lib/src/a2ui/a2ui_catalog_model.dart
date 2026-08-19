import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';
import 'package:restage_codegen/src/a2ui/a2ui_protocol.dart';
import 'package:restage_codegen/src/a2ui/rfc8785_canonical_json.dart';

/// Reserved placeholder for the catalog ID while its digest is computed.
///
/// Catalog content containing this exact value is rejected before hashing, so
/// the canonical digest preimage contains this sentinel exactly once: in the
/// producer identity instruction.
const String kA2uiCatalogIdentitySentinel =
    '{{RESTAGE_A2UI_CATALOG_ID_SHA256}}';

/// The producer instruction that binds `createSurface.catalogId` to
/// [catalogId].
String a2uiCatalogIdentityInstruction(String catalogId) =>
    'For every A2UI createSurface message, set catalogId to "$catalogId".';

/// One component in an emitted A2UI catalog: a component [name] and its
/// JSON-Schema [dataSchema] (the object schema the model is constrained to
/// when emitting that component).
///
/// [dataSchema] is the complete projected component schema: its data fields,
/// required set, nullability, and the required `component` discriminator.
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
  /// Creates the complete predefined-catalog registration contract.
  ///
  /// [systemPromptFragments] contains only non-identity guidance. The frozen
  /// identity instruction is added internally with a sentinel for hashing and
  /// with the final content address for producer/runtime output.
  RestageStampedA2uiCatalog({
    required this.stamp,
    required List<A2uiComponent> components,
    Map<String, Object?> functions = const {},
    List<String> systemPromptFragments = const [],
  })  : components = List<A2uiComponent>.unmodifiable(
          <A2uiComponent>[
            for (final component in components)
              A2uiComponent(
                name: component.name,
                dataSchema: _freezeJsonMap(component.dataSchema),
              ),
          ]..sort((a, b) => a.name.compareTo(b.name)),
        ),
        functions = _freezeJsonMap(functions),
        nonIdentitySystemPromptFragments =
            List.unmodifiable(systemPromptFragments) {
    canonicalDigestPreimage = canonicalizeJsonRfc8785(
      _registrationContract(
        stamp: stamp,
        components: this.components,
        functions: this.functions,
        identityCatalogId: kA2uiCatalogIdentitySentinel,
        nonIdentitySystemPromptFragments: nonIdentitySystemPromptFragments,
      ),
    );
    final sentinelCount =
        kA2uiCatalogIdentitySentinel.allMatches(canonicalDigestPreimage).length;
    if (sentinelCount != 1) {
      throw ArgumentError.value(
        sentinelCount,
        'registrationContract',
        'A2UI registration content must not contain the reserved catalog-ID '
            'sentinel; the canonical digest preimage must contain it exactly '
            'once in the identity instruction.',
      );
    }
  }

  /// The capability stamp travelling with the catalog.
  final RestageCapabilityStamp stamp;

  /// The catalog's components in sorted-name order.
  final List<A2uiComponent> components;

  /// Predefined function contracts keyed by function name.
  ///
  /// The map is empty until generated client functions are supported, but it
  /// remains an identity axis so adding a function cannot alias an older
  /// registration.
  final Map<String, Object?> functions;

  /// Producer guidance excluding the self-referential identity instruction.
  final List<String> nonIdentitySystemPromptFragments;

  /// The exact RFC 8785 canonical UTF-8 digest input, exposed for conformance
  /// and non-self-reference tests.
  late final String canonicalDigestPreimage;

  /// The catalog document identifier (the A2UI `$id` / `catalogId`).
  ///
  /// **This is a document identifier, NEVER a capability authority** —
  /// capability decisions read [stamp], not this string. The SHA-256 digest
  /// covers the complete predefined registration contract.
  late final String documentId = 'restage:catalog/sha256/'
      '${sha256.convert(utf8.encode(canonicalDigestPreimage))}';

  /// The A2UI schema dialect shared by the producer document and generated
  /// catalog metadata.
  String get schemaDialect => kA2uiSchemaDialect;

  /// The pinned A2UI protocol/schema version shared by the producer document
  /// and generated catalog metadata.
  String get a2uiProtocolVersion => kA2uiProtocolVersion;

  /// The content fingerprint carried by [documentId].
  ///
  /// Keeping the algorithm prefix in this value preserves the exact identity
  /// vocabulary (`sha256/<digest>`) without introducing a second hash or a
  /// second canonicalization pass for generated Dart.
  String get fingerprint => documentId.substring('restage:catalog/'.length);

  /// Prompt fragments exactly as the producer receives them: the finalized
  /// identity instruction followed by deterministic non-identity guidance.
  late final List<String> systemPromptFragments = List.unmodifiable([
    a2uiCatalogIdentityInstruction(documentId),
    ...nonIdentitySystemPromptFragments,
  ]);

  /// JSON wire form — `{ restageCapability, a2uiCatalog }`.
  Map<String, Object?> toJson() {
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
        'components': {for (final c in components) c.name: c.dataSchema},
        'functions': functions,
        'systemPromptFragments': List<String>.of(systemPromptFragments),
      },
    };
  }
}

Map<String, Object?> _registrationContract({
  required RestageCapabilityStamp stamp,
  required List<A2uiComponent> components,
  required Map<String, Object?> functions,
  required String identityCatalogId,
  required List<String> nonIdentitySystemPromptFragments,
}) =>
    {
      'restageCapability': stamp.toJson(),
      'a2uiCatalog': {
        r'$schema': kA2uiSchemaDialect,
        'a2uiProtocolVersion': kA2uiProtocolVersion,
        'components': {
          for (final component in components)
            component.name: component.dataSchema,
        },
        'functions': functions,
        'systemPromptFragments': [
          a2uiCatalogIdentityInstruction(identityCatalogId),
          ...nonIdentitySystemPromptFragments,
        ],
      },
    };

Map<String, Object?> _freezeJsonMap(Map<Object?, Object?> value) {
  final frozen = <String, Object?>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is! String) {
      throw ArgumentError.value(
        key,
        'json',
        'A2UI registration object keys must be strings.',
      );
    }
    frozen[key] = _freezeJsonValue(entry.value);
  }
  return Map.unmodifiable(frozen);
}

Object? _freezeJsonValue(Object? value) {
  if (value == null || value is bool || value is num || value is String) {
    return value;
  }
  if (value is List<Object?>) {
    return List<Object?>.unmodifiable(value.map<Object?>(_freezeJsonValue));
  }
  if (value is Map<Object?, Object?>) return _freezeJsonMap(value);
  throw ArgumentError.value(
    value,
    'json',
    'A2UI registration content must be JSON-safe.',
  );
}
