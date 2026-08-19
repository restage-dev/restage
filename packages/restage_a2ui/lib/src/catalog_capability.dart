import 'package:flutter/foundation.dart';

import 'installed_capability.dart';

/// The compact identity and capability metadata compiled alongside a generated
/// A2UI catalog.
///
/// The code generator creates this as a `const` value from the same canonical
/// registration model that writes `restage_a2ui_catalog.a2ui.json`. It carries
/// metadata only: catalog components, JSON schemas, and widget builders remain
/// represented by the generated GenUI Dart catalog rather than being copied
/// into this value.
@immutable
final class RestageA2uiCapability {
  /// Creates generated A2UI catalog metadata.
  const RestageA2uiCapability({
    required this.schemaDialect,
    required this.a2uiProtocolVersion,
    required this.catalogId,
    required this.fingerprint,
    required this.catalogContentVersion,
    required this.availableLibraries,
    required this.perItemSinceVersion,
  }) : assert(schemaDialect != '', 'schemaDialect must not be empty'),
       assert(
         a2uiProtocolVersion != '',
         'a2uiProtocolVersion must not be empty',
       ),
       assert(catalogId != '', 'catalogId must not be empty'),
       assert(fingerprint != '', 'fingerprint must not be empty'),
       assert(
         catalogContentVersion >= 1,
         'catalogContentVersion must be a positive content version',
       );

  /// The JSON-Schema dialect in the producer document's `$schema` field.
  final String schemaDialect;

  /// The A2UI protocol/schema version in the producer document's
  /// `a2uiProtocolVersion` field.
  final String a2uiProtocolVersion;

  /// The content-derived catalog identity in the producer document's `$id` and
  /// `catalogId` fields.
  final String catalogId;

  /// The `sha256/<digest>` fingerprint suffix carried by [catalogId].
  final String fingerprint;

  /// The built-in content version the generated catalog provides.
  final int catalogContentVersion;

  /// The custom libraries and capability versions the generated catalog
  /// provides, in the canonical namespace order emitted by the generator.
  final List<A2uiAvailableLibrary> availableLibraries;

  /// The content version of each generated catalog item, in canonical name
  /// order emitted by the generator.
  final Map<String, int> perItemSinceVersion;

  /// Alias for callers that refer to the A2UI protocol field as a schema
  /// version.
  String get schemaVersion => a2uiProtocolVersion;

  /// Alias that makes the fingerprint's relationship to the catalog identity
  /// explicit at call sites.
  String get catalogFingerprint => fingerprint;

  /// Converts the available capability axes to the runtime descriptor consumed
  /// by the A2UI pre-render check.
  A2uiInstalledCapability get installedCapability => A2uiInstalledCapability(
    catalogContentVersion: catalogContentVersion,
    availableLibraries: availableLibraries,
  );
}
