// V1 publication and delivery DTOs mirror their frozen wire fields.
// ignore_for_file: public_member_api_docs, prefer_constructors_over_static_methods
// ignore_for_file: prefer_interpolation_to_compose_strings, require_trailing_commas
// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/src/capability/capability_manifest.dart';
import 'package:restage_shared/src/capability/capability_sidecar.dart';
import 'package:restage_shared/src/capability/surface_fit.dart';
import 'package:restage_shared/rfw_formats.dart' as rfw;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:restage_shared/src/flow_document/flow_document.dart';
import 'package:restage_shared/src/flow_document/flow_document_codec.dart';
import 'package:restage_shared/src/generated_output_path_order.dart';
import 'package:restage_shared/src/surface_contract/screen_event_names.dart';
import 'package:restage_shared/src/surface_contract/surface_contract_json.dart';
import 'package:restage_shared/src/surface_contract/surface_screen_contract_fingerprint.dart';
import 'package:restage_shared/src/surface_contract/surface_screen_event_schema.dart';
import 'package:restage_shared/src/surface_contract/surface_screen_host_data_schema.dart';
import 'package:restage_shared/src/surface_delivery/surface_artifact_descriptor.dart';
import 'package:restage_shared/src/surface_document/surface_document.dart';

const int _surfacePublicationSchemaVersion = 1;

enum SurfacePublicationArtifactRole {
  flowDocument('flowDocument'),
  screenBlob('screenBlob'),
  capabilitySidecar('capabilitySidecar'),

  /// A subset icon font; the id is [iconFontArtifactId].
  iconFont('iconFont'),

  /// Initial screen-local values by root widget or flow screen; one per
  /// publication, identified by its slug.
  localSeeds('localSeeds');

  const SurfacePublicationArtifactRole(this.wireName);

  final String wireName;

  /// Whether this artifact is a payload section: delivered data that is not
  /// rendered content and carries no measurement occurrences.
  bool get isPayloadSection => this == iconFont || this == localSeeds;

  static SurfacePublicationArtifactRole fromWireName(String value) {
    for (final role in values) {
      if (role.wireName == value) return role;
    }
    throw FormatException('Unsupported publication artifact role "$value".');
  }
}

@immutable
final class SurfacePublicationArtifact {
  factory SurfacePublicationArtifact({
    required String contentHash,
    required String path,
    required SurfacePublicationArtifactRole role,
    String? id,
  }) {
    SurfaceContractJson.requireSha256(contentHash, 'artifact.contentHash');
    _requirePackageRelativePath(path, 'artifact.path');
    if (role == SurfacePublicationArtifactRole.flowDocument) {
      if (id != null) {
        throw const FormatException(
            'A flow document artifact cannot carry id.');
      }
    } else {
      _requireIdentity(id, 'artifact.id');
    }
    return SurfacePublicationArtifact._(
      contentHash: contentHash,
      path: path,
      role: role,
      id: id,
    );
  }

  const SurfacePublicationArtifact._({
    required this.contentHash,
    required this.path,
    required this.role,
    required this.id,
  });

  final String contentHash;
  final String path;
  final SurfacePublicationArtifactRole role;
  final String? id;

  Map<String, Object?> toJson() => <String, Object?>{
        'contentHash': contentHash,
        if (id != null) 'id': id,
        'path': path,
        'role': role.wireName,
      };

  static SurfacePublicationArtifact fromJson(
    Object? value, {
    required String path,
  }) {
    final json = SurfaceContractJson.requireObject(value, path);
    final role = SurfacePublicationArtifactRole.fromWireName(
      SurfaceContractJson.requiredString(json, 'role', path),
    );
    final expected = <String>{'contentHash', 'path', 'role'};
    if (role != SurfacePublicationArtifactRole.flowDocument) {
      expected.add('id');
    }
    SurfaceContractJson.exactKeys(json, expected, path);
    return SurfacePublicationArtifact(
      contentHash: SurfaceContractJson.requiredString(
        json,
        'contentHash',
        path,
      ),
      id: role == SurfacePublicationArtifactRole.flowDocument
          ? null
          : SurfaceContractJson.requiredString(json, 'id', path),
      path: SurfaceContractJson.requiredString(json, 'path', path),
      role: role,
    );
  }
}

/// Typed source and catalog facts for one final compiled screen blob.
///
/// Publication keys bind these facts to the final blob hash. Hosting is derived
/// from the reachable emitted body; these facts contain no purity assertion.
@immutable
final class SurfaceCompiledScreenContractV1 {
  factory SurfaceCompiledScreenContractV1({
    required SurfaceScreenHostDataSchema context,
    required SurfaceScreenEventSchema events,
    required rfw.RfwCatalogOccurrenceResolutionInput catalogResolution,
    required Catalog catalog,
  }) =>
      SurfaceCompiledScreenContractV1._(
        context: SurfaceScreenHostDataSchema.fromJson(context.toJson()),
        events: SurfaceScreenEventSchemaV1Codec.decode(
            SurfaceScreenEventSchemaV1Codec.encode(events)),
        catalogResolution: rfw.RfwCatalogOccurrenceResolutionInput.fromJson(
            catalogResolution.toJson()),
        catalog: decodeCatalog(encodeCatalog(catalog)),
      );

  const SurfaceCompiledScreenContractV1._({
    required this.context,
    required this.events,
    required this.catalogResolution,
    required this.catalog,
  });

  final SurfaceScreenHostDataSchema context;
  final SurfaceScreenEventSchema events;
  final rfw.RfwCatalogOccurrenceResolutionInput catalogResolution;

  /// Exact selected entries from the compiler's validated catalog.
  final Catalog catalog;

  Map<String, Object?> toJson() => {
        'context': context.toJson(),
        'events': SurfaceScreenEventSchemaV1Codec.encode(events),
        'catalogResolution': catalogResolution.toJson(),
        'catalog': encodeCatalog(catalog),
      };

  factory SurfaceCompiledScreenContractV1.fromJson(Object? value) {
    final json =
        SurfaceContractJson.requireObject(value, r'$.compiledScreenContract');
    SurfaceContractJson.exactKeys(
        json,
        const {
          'context',
          'events',
          'catalogResolution',
          'catalog',
        },
        r'$.compiledScreenContract');
    return SurfaceCompiledScreenContractV1(
      context: SurfaceScreenHostDataSchema.fromJson(json['context']),
      events: SurfaceScreenEventSchemaV1Codec.decode(json['events']),
      catalogResolution: rfw.RfwCatalogOccurrenceResolutionInput.fromJson(
          json['catalogResolution']),
      catalog: decodeCatalog(SurfaceContractJson.requiredString(
          json, 'catalog', r'$.compiledScreenContract')),
    );
  }
}

@immutable
final class SurfacePublication {
  factory SurfacePublication({
    required Surface surface,
    required String slug,
    required SurfaceSourceKind sourceKind,
    required SurfacePayloadKind payloadKind,
    required String payloadContentHash,
    FlowDeliveryMode? deliveryMode,
    int? contractVersion,
    CapabilityManifest? capabilities,
    SurfaceScreenEventSchema? eventContract,
    String? eventContractHash,
    String? contractFingerprint,
    SurfaceScreenHostDataSchema? hostDataContract,
    String? hostDataContractHash,
    String? mountName,
    SurfaceFitRequirementV1? fitRequirement,
    String? fitRequirementHash,
    Map<String, SurfaceCompiledScreenContractV1> compiledScreenContracts =
        const {},
    SurfacePresentationV1? declaredPresentation,
  }) {
    _requireIdentity(slug, 'publication.slug');
    final frozenScreenContracts = <String, SurfaceCompiledScreenContractV1>{};
    for (final hash in compiledScreenContracts.keys.toList()..sort()) {
      SurfaceContractJson.requireSha256(
          hash, 'publication.compiledScreenContracts');
      frozenScreenContracts[hash] = SurfaceCompiledScreenContractV1.fromJson(
          compiledScreenContracts[hash]!.toJson());
    }

    if (mountName != null && !_mountNamePattern.hasMatch(mountName)) {
      throw const FormatException(
        'publication.mountName must be a public Dart class name.',
      );
    }
    SurfaceContractJson.requireSha256(
      payloadContentHash,
      'publication.payloadContentHash',
    );
    if ((fitRequirement == null) != (fitRequirementHash == null)) {
      throw const FormatException(
        'A publication fit requirement requires its hash, and vice versa.',
      );
    }
    if (fitRequirement != null) {
      SurfaceContractJson.requireSha256(
        fitRequirementHash!,
        'publication.fitRequirementHash',
      );
      if (fitRequirementHash != fitRequirement.contentHash) {
        throw const FormatException(
          'Publication fitRequirementHash does not match fitRequirement.',
        );
      }
      final expectedKind = payloadKind == SurfacePayloadKind.blob
          ? SurfaceContentKindV1.single
          : SurfaceContentKindV1.flow;
      if (fitRequirement.hosting.contentKind != expectedKind) {
        throw const FormatException(
          'Publication fit requirement has a different content kind.',
        );
      }
    }

    switch (sourceKind) {
      case SurfaceSourceKind.screen:
        if (payloadKind != SurfacePayloadKind.blob) {
          throw const FormatException(
            'A screen publication must carry a blob payload.',
          );
        }
        if (deliveryMode != null) {
          throw const FormatException(
            'A blob publication cannot carry deliveryMode.',
          );
        }
        if (contractVersion == null || contractVersion < 1) {
          throw const FormatException(
            'A screen publication requires a positive contractVersion.',
          );
        }
        if (capabilities == null ||
            eventContract == null ||
            eventContractHash == null ||
            contractFingerprint == null) {
          throw const FormatException(
            'A screen publication requires its complete contract metadata.',
          );
        }
        SurfaceContractJson.requireSha256(
          eventContractHash,
          'publication.eventContractHash',
        );
        SurfaceContractJson.requireSha256(
          contractFingerprint,
          'publication.contractFingerprint',
        );
        final canonicalCapabilities = _canonicalManifest(capabilities);
        final expectedEventHash = SurfaceScreenEventContractHash.hash(
          eventContract,
        );
        if (eventContractHash != expectedEventHash) {
          throw const FormatException(
            'Screen eventContractHash does not match eventContract.',
          );
        }
        // A screen declaring no host data carries neither field, so its
        // contract encodes exactly as it did before host data existed.
        if ((hostDataContract == null) != (hostDataContractHash == null)) {
          throw const FormatException(
            'A screen host data contract requires its hash, and vice versa.',
          );
        }
        if (hostDataContract != null) {
          if (hostDataContract.isEmpty) {
            throw const FormatException(
              'An empty screen host data contract must be omitted.',
            );
          }
          SurfaceContractJson.requireSha256(
            hostDataContractHash!,
            'publication.hostDataContractHash',
          );
          if (hostDataContractHash !=
              SurfaceScreenHostDataContractHash.hash(hostDataContract)) {
            throw const FormatException(
              'Screen hostDataContractHash does not match hostDataContract.',
            );
          }
        }
        final expectedFingerprint = SurfaceScreenContractFingerprint.hash(
          sourceKind: sourceKind,
          payloadKind: payloadKind,
          capabilities: canonicalCapabilities,
          eventContractHash: eventContractHash,
          hostDataContractHash: hostDataContractHash,
        );
        if (contractFingerprint != expectedFingerprint) {
          throw const FormatException(
            'Screen contractFingerprint does not match the contract tuple.',
          );
        }
      case SurfaceSourceKind.flowGraph:
        if (payloadKind != SurfacePayloadKind.flow || deliveryMode == null) {
          throw const FormatException(
            'A flowGraph publication requires a flow payload and deliveryMode.',
          );
        }
        _requireNoScreenContract(
          contractVersion: contractVersion,
          capabilities: capabilities,
          eventContract: eventContract,
          eventContractHash: eventContractHash,
          contractFingerprint: contractFingerprint,
          hostDataContract: hostDataContract,
          hostDataContractHash: hostDataContractHash,
        );
      case SurfaceSourceKind.paywall:
        if (surface != Surface.paywall) {
          throw const FormatException(
            'A paywall publication must use the paywall surface.',
          );
        }
        if ((payloadKind == SurfacePayloadKind.flow) !=
            (deliveryMode != null)) {
          throw const FormatException(
            'deliveryMode is required exactly for a flow payload.',
          );
        }
        _requireNoScreenContract(
          contractVersion: contractVersion,
          capabilities: capabilities,
          eventContract: eventContract,
          eventContractHash: eventContractHash,
          contractFingerprint: contractFingerprint,
          hostDataContract: hostDataContract,
          hostDataContractHash: hostDataContractHash,
        );
    }

    return SurfacePublication._(
      surface: surface,
      slug: slug,
      sourceKind: sourceKind,
      payloadKind: payloadKind,
      payloadContentHash: payloadContentHash,
      deliveryMode: deliveryMode,
      contractVersion: contractVersion,
      capabilities:
          capabilities == null ? null : _canonicalManifest(capabilities),
      eventContract: eventContract,
      eventContractHash: eventContractHash,
      contractFingerprint: contractFingerprint,
      hostDataContract: hostDataContract,
      hostDataContractHash: hostDataContractHash,
      mountName: mountName,
      fitRequirement: fitRequirement,
      fitRequirementHash: fitRequirementHash,
      compiledScreenContracts: Map.unmodifiable(frozenScreenContracts),
      declaredPresentation: declaredPresentation,
    );
  }

  const SurfacePublication._({
    required this.surface,
    required this.slug,
    required this.sourceKind,
    required this.payloadKind,
    required this.payloadContentHash,
    required this.deliveryMode,
    required this.contractVersion,
    required this.capabilities,
    required this.eventContract,
    required this.eventContractHash,
    required this.contractFingerprint,
    required this.hostDataContract,
    required this.hostDataContractHash,
    required this.mountName,
    required this.fitRequirement,
    required this.fitRequirementHash,
    required this.compiledScreenContracts,
    required this.declaredPresentation,
  });

  final Surface surface;
  final String slug;
  final SurfaceSourceKind sourceKind;
  final SurfacePayloadKind payloadKind;
  final String payloadContentHash;
  final FlowDeliveryMode? deliveryMode;
  final int? contractVersion;
  final CapabilityManifest? capabilities;
  final SurfaceScreenEventSchema? eventContract;
  final String? eventContractHash;
  final String? contractFingerprint;

  /// The host-supplied inputs this screen declares, or null when it declares
  /// none.
  final SurfaceScreenHostDataSchema? hostDataContract;

  /// Content hash of [hostDataContract], present exactly with it.
  final String? hostDataContractHash;

  /// The generated widget an app mounts to show this surface, when one was
  /// generated.
  final String? mountName;

  /// Declared replacement requirements; absence cannot qualify a replacement.
  final SurfaceFitRequirementV1? fitRequirement;

  /// Content hash of [fitRequirement], present exactly with it.
  final String? fitRequirementHash;

  /// Typed producer facts bound to each exact final screen blob.
  final Map<String, SurfaceCompiledScreenContractV1> compiledScreenContracts;

  /// Explicit authored presentation constraint; absence means infer from body.
  final SurfacePresentationV1? declaredPresentation;

  Map<String, Object?> toJson() {
    if (sourceKind == SurfaceSourceKind.screen) {
      return <String, Object?>{
        'capabilities': SurfaceContractJson.encodeCapabilityManifest(
          capabilities!,
          path: 'publication.capabilities',
        ),
        'contractFingerprint': contractFingerprint,
        'eventContract': SurfaceScreenEventSchemaV1Codec.encode(
          eventContract!,
        ),
        'eventContractHash': eventContractHash,
        if (hostDataContract != null)
          'hostDataContract': SurfaceScreenHostDataSchemaV1Codec.encode(
            hostDataContract!,
          ),
        if (hostDataContractHash != null)
          'hostDataContractHash': hostDataContractHash,
        if (mountName != null) 'mountName': mountName,
        if (compiledScreenContracts.isNotEmpty)
          'compiledScreenContracts': {
            for (final entry in compiledScreenContracts.entries)
              entry.key: entry.value.toJson(),
          },
        if (declaredPresentation != null)
          'declaredPresentation': declaredPresentation!.name,
        if (fitRequirement != null) 'fitRequirement': fitRequirement!.toJson(),
        if (fitRequirementHash != null)
          'fitRequirementHash': fitRequirementHash,
        'payloadContentHash': payloadContentHash,
        'payloadKind': payloadKind.wireName,
        'slug': slug,
        'sourceKind': sourceKind.wireName,
        'surface': surface.wireName,
        'contractVersion': contractVersion,
      };
    }
    return <String, Object?>{
      if (deliveryMode != null) 'deliveryMode': deliveryMode!.wireName,
      if (mountName != null) 'mountName': mountName,
      if (compiledScreenContracts.isNotEmpty)
        'compiledScreenContracts': {
          for (final entry in compiledScreenContracts.entries)
            entry.key: entry.value.toJson(),
        },
      if (declaredPresentation != null)
        'declaredPresentation': declaredPresentation!.name,
      if (fitRequirement != null) 'fitRequirement': fitRequirement!.toJson(),
      if (fitRequirementHash != null) 'fitRequirementHash': fitRequirementHash,
      'payloadContentHash': payloadContentHash,
      'payloadKind': payloadKind.wireName,
      'slug': slug,
      'sourceKind': sourceKind.wireName,
      'surface': surface.wireName,
    };
  }

  static SurfacePublication fromJson(
    Object? value, {
    required String path,
  }) {
    final json = SurfaceContractJson.requireObject(value, path);
    SurfaceContractJson.allowedKeys(json, _publicationFields, path);
    final sourceKind = SurfaceSourceKind.fromWireName(
      SurfaceContractJson.requiredString(json, 'sourceKind', path),
    );
    final payloadKind = SurfacePayloadKind.fromWireName(
      SurfaceContractJson.requiredString(json, 'payloadKind', path),
    );
    final expected = _publicationRequiredFields(
      sourceKind: sourceKind,
      payloadKind: payloadKind,
    );
    // Host data is optional on a screen: present as a pair, or absent.
    if (sourceKind == SurfaceSourceKind.screen &&
        (json.containsKey('hostDataContract') ||
            json.containsKey('hostDataContractHash'))) {
      expected
        ..add('hostDataContract')
        ..add('hostDataContractHash');
    }
    if (json.containsKey('mountName')) expected.add('mountName');
    if (json.containsKey('compiledScreenContracts'))
      expected.add('compiledScreenContracts');
    if (json.containsKey('declaredPresentation'))
      expected.add('declaredPresentation');
    if (json.containsKey('fitRequirement') ||
        json.containsKey('fitRequirementHash')) {
      expected
        ..add('fitRequirement')
        ..add('fitRequirementHash');
    }
    SurfaceContractJson.exactKeys(json, expected, path);
    return SurfacePublication(
      surface: Surface.fromWireName(
        SurfaceContractJson.requiredString(json, 'surface', path),
      ),
      slug: SurfaceContractJson.requiredString(json, 'slug', path),
      sourceKind: sourceKind,
      payloadKind: payloadKind,
      payloadContentHash: SurfaceContractJson.requiredString(
        json,
        'payloadContentHash',
        path,
      ),
      deliveryMode: json.containsKey('deliveryMode')
          ? FlowDeliveryMode.fromWireName(
              SurfaceContractJson.requiredString(json, 'deliveryMode', path),
            )
          : null,
      contractVersion: json.containsKey('contractVersion')
          ? SurfaceContractJson.requiredPositiveInt(
              json,
              'contractVersion',
              path,
            )
          : null,
      capabilities: json.containsKey('capabilities')
          ? SurfaceContractJson.decodeCapabilityManifest(
              SurfaceContractJson.requiredValue(json, 'capabilities', path),
              path: '$path.capabilities',
            )
          : null,
      eventContract: json.containsKey('eventContract')
          ? SurfaceScreenEventSchemaV1Codec.decode(
              SurfaceContractJson.requiredValue(json, 'eventContract', path),
            )
          : null,
      eventContractHash: json.containsKey('eventContractHash')
          ? SurfaceContractJson.requiredString(json, 'eventContractHash', path)
          : null,
      contractFingerprint: json.containsKey('contractFingerprint')
          ? SurfaceContractJson.requiredString(
              json,
              'contractFingerprint',
              path,
            )
          : null,
      hostDataContract: json.containsKey('hostDataContract')
          ? SurfaceScreenHostDataSchemaV1Codec.decode(
              SurfaceContractJson.requiredValue(json, 'hostDataContract', path),
            )
          : null,
      hostDataContractHash: json.containsKey('hostDataContractHash')
          ? SurfaceContractJson.requiredString(
              json,
              'hostDataContractHash',
              path,
            )
          : null,
      mountName: json.containsKey('mountName')
          ? SurfaceContractJson.requiredString(json, 'mountName', path)
          : null,
      compiledScreenContracts: json.containsKey('compiledScreenContracts')
          ? SurfaceContractJson.requireObject(json['compiledScreenContracts'],
                  '$path.compiledScreenContracts')
              .map((hash, contract) => MapEntry(
                  hash, SurfaceCompiledScreenContractV1.fromJson(contract)))
          : const {},
      declaredPresentation: json.containsKey('declaredPresentation')
          ? SurfacePresentationV1.values.firstWhere(
              (mode) => mode.name == json['declaredPresentation'],
              orElse: () =>
                  throw const FormatException('Unknown declared presentation.'))
          : null,
      fitRequirement: json.containsKey('fitRequirement')
          ? SurfaceFitRequirementV1.fromJson(
              SurfaceContractJson.requiredValue(json, 'fitRequirement', path),
            )
          : null,
      fitRequirementHash: json.containsKey('fitRequirementHash')
          ? SurfaceContractJson.requiredString(json, 'fitRequirementHash', path)
          : null,
    );
  }

  void validatePayload(SurfacePayload payload) {
    if (payload.contentHash != payloadContentHash) {
      throw const FormatException(
        'Publication payloadContentHash does not match assembled payload.',
      );
    }
    switch (payloadKind) {
      case SurfacePayloadKind.blob:
        if (payload is! BlobSurfacePayload) {
          throw const FormatException('Publication requires a blob payload.');
        }
        if (sourceKind == SurfaceSourceKind.screen) {
          final expectedCapabilities = capabilities!;
          final actualCapabilities = CapabilityManifest(
            builtInFloor: payload.minClient,
            requiredLibraries: payload.requiredLibraries,
          );
          if (!SurfaceContractJson.requirementsEqual(
            expectedCapabilities,
            actualCapabilities,
          )) {
            throw const FormatException(
              'Screen publication capabilities do not match blob payload.',
            );
          }
        }
      case SurfacePayloadKind.flow:
        if (payload is! FlowSurfacePayload) {
          throw const FormatException('Publication requires a flow payload.');
        }
        if (payload.flowDocument.flow != slug) {
          throw const FormatException(
            'Flow payload identity does not match publication slug.',
          );
        }
        if (payload.flowDocument.deliveryMode != deliveryMode) {
          throw const FormatException(
            'Flow payload deliveryMode does not match publication.',
          );
        }
    }
  }
}

@immutable
final class SurfacePublicationManifestEntry {
  factory SurfacePublicationManifestEntry({
    required List<SurfacePublicationArtifact> artifacts,
    required SurfacePublication publication,
    List<String> sources = const <String>[],
    String path = 'entry',
  }) {
    if (artifacts.isEmpty) {
      throw const FormatException('A publication entry requires artifacts.');
    }
    final paths = <String>{};
    for (final artifact in artifacts) {
      if (!paths.add(artifact.path)) {
        throw FormatException(
            'Duplicate publication artifact path "${artifact.path}".');
      }
    }
    _validateAuthoringSources(sources, path);
    _validateArtifactShape(artifacts, publication);
    return SurfacePublicationManifestEntry._(
      artifacts: List.unmodifiable(artifacts),
      publication: publication,
      sources: List.unmodifiable(sources),
    );
  }

  const SurfacePublicationManifestEntry._({
    required this.artifacts,
    required this.publication,
    required this.sources,
  });

  final List<SurfacePublicationArtifact> artifacts;
  final SurfacePublication publication;

  /// Package-relative authoring sources this publication was compiled from,
  /// in strictly ascending order.
  ///
  /// This is local build provenance, not wire state: it never reaches the
  /// upload request. It exists so a developer can name a publication by the
  /// file they are looking at and have the manifest, not a source scan,
  /// resolve which publication that is.
  ///
  /// The set is wider than "files that declare this publication". A flow
  /// lists the file declaring it plus the declaring file of every screen in
  /// its closure, so pointing at any screen of a flow resolves the flow that
  /// publishes it, and each declaration contributes both its own file and its
  /// owning library, which differ when a surface is declared in a part.
  ///
  /// Empty when nothing was recorded — in practice, a manifest generated
  /// before this field existed.
  final List<String> sources;

  /// This entry with its artifacts in canonical order.
  ///
  /// Canonicalization lives on the type, beside the validation that asserts
  /// it. A caller that rebuilt the entry field by field to sort one list
  /// would silently drop every field it forgot to transcribe, and an omitted
  /// optional field produces no decode error and no wire-format error — so
  /// nothing downstream would catch it.
  SurfacePublicationManifestEntry canonical() =>
      SurfacePublicationManifestEntry(
        publication: publication,
        sources: sources,
        artifacts: [...artifacts]..sort(_compareArtifactsCanonically),
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'artifacts': <Object?>[
          for (final artifact in artifacts) artifact.toJson(),
        ],
        'publication': publication.toJson(),
        if (sources.isNotEmpty) 'sources': <Object?>[...sources],
      };

  static SurfacePublicationManifestEntry fromJson(
    Object? value, {
    required String path,
  }) {
    final json = SurfaceContractJson.requireObject(value, path);
    SurfaceContractJson.allowedKeys(
        json, const {'artifacts', 'publication', 'sources'}, path);
    final rawArtifacts = SurfaceContractJson.requireList(
      SurfaceContractJson.requiredValue(json, 'artifacts', path),
      '$path.artifacts',
    );
    final rawSources = json.containsKey('sources')
        ? SurfaceContractJson.requireList(json['sources'], '$path.sources')
        : const <Object?>[];
    return SurfacePublicationManifestEntry(
      artifacts: <SurfacePublicationArtifact>[
        for (var index = 0; index < rawArtifacts.length; index += 1)
          SurfacePublicationArtifact.fromJson(
            rawArtifacts[index],
            path: '$path.artifacts[$index]',
          ),
      ],
      publication: SurfacePublication.fromJson(
        SurfaceContractJson.requiredValue(json, 'publication', path),
        path: '$path.publication',
      ),
      sources: <String>[
        for (var index = 0; index < rawSources.length; index += 1)
          _requireSourceString(rawSources[index], '$path.sources[$index]'),
      ],
      path: path,
    );
  }
}

int _compareArtifactsCanonically(
  SurfacePublicationArtifact left,
  SurfacePublicationArtifact right,
) {
  final path = compareGeneratedOutputPaths(left.path, right.path);
  if (path != 0) return path;
  final role = left.role.wireName.compareTo(right.role.wireName);
  if (role != 0) return role;
  return (left.id ?? '').compareTo(right.id ?? '');
}

String _requireSourceString(Object? value, String path) {
  if (value is! String) {
    throw FormatException('Expected "$path" to be a string.');
  }
  return value;
}

/// Sources are validated here, never repaired, in line with every other
/// field on this type. Ordering and uniqueness are the producer's job — the
/// assembler sorts and de-duplicates on the way in — so a constructor that
/// silently reordered its input would hide a producer defect rather than
/// surface it, and would make the canonical bytes depend on which code path
/// built the entry.
void _validateAuthoringSources(List<String> sources, String path) {
  if (sources.isEmpty) return;
  String? previous;
  for (var index = 0; index < sources.length; index += 1) {
    final source = sources[index];
    _requirePackageRelativePath(source, '$path.sources[$index]');
    if (!source.endsWith('.dart')) {
      throw FormatException(
          'Expected "$path.sources[$index]" to be a Dart source path.');
    }
    if (previous != null &&
        compareGeneratedOutputPaths(previous, source) >= 0) {
      throw FormatException(
        'Expected "$path.sources" to be unique and in ascending order.',
      );
    }
    previous = source;
  }
}

/// The artifact id of the icon font for [family], owned by [fontPackage].
String iconFontArtifactId(String family, String? fontPackage) {
  if (family.isEmpty || family.contains('@')) {
    throw FormatException('Icon font family "$family" cannot be an id.');
  }
  return fontPackage == null ? family : '$family@$fontPackage';
}

/// Decodes the icon font artifact [id] holding [bytes].
DeliveredIconFont decodeIconFontArtifact(String id, List<int> bytes) {
  final at = id.indexOf('@');
  return DeliveredIconFont(
    family: at < 0 ? id : id.substring(0, at),
    fontPackage: at < 0 ? null : id.substring(at + 1),
    bytes: Uint8List.fromList(bytes),
  );
}

/// The bytes of a local seeds artifact, `{root: {key: value}}` with a root per
/// widget or screen id, keys sorted at both levels.
Uint8List encodeLocalSeedsArtifact(Map<String, Map<String, Object>> seeds) =>
    Uint8List.fromList(
      utf8.encode(
        jsonEncode(<String, Object>{
          for (final root in seeds.keys.toList()..sort())
            root: <String, Object>{
              for (final key in seeds[root]!.keys.toList()..sort())
                key: seeds[root]![key]!,
            },
        }),
      ),
    );

/// Decodes a local seeds artifact into its values by root or screen id.
Map<String, Map<String, Object>> decodeLocalSeedsArtifact(List<int> bytes) {
  const path = 'localSeeds';
  final json = SurfaceContractJson.requireObject(
    SurfaceContractJson.decode(utf8.decode(bytes), label: path),
    path,
  );
  return <String, Map<String, Object>>{
    for (final MapEntry(key: root, value: raw) in json.entries)
      root: <String, Object>{
        for (final entry
            in SurfaceContractJson.requireObject(raw, '$path.$root').entries)
          entry.key: switch (entry.value) {
            final String value => value,
            final num value => value,
            final bool value => value,
            _ => throw FormatException(
                'Expected "$path.$root.${entry.key}" to be a string, number '
                'or bool.',
              ),
          },
      },
  };
}

@immutable
final class SurfacePublicationArtifactClosure {
  SurfacePublicationArtifactClosure._({
    required this.publication,
    required Map<String, Uint8List> screenBlobs,
    required Map<String, CapabilityManifest> sidecarCapabilities,
    required this.flowDocument,
    required List<DeliveredIconFont> iconFonts,
    required Map<String, Map<String, Object>> localSeeds,
  })  : _screenBlobs = Map.unmodifiable(screenBlobs),
        _sidecarCapabilities = Map.unmodifiable(sidecarCapabilities),
        iconFonts = List.unmodifiable(iconFonts),
        localSeeds = Map.unmodifiable(localSeeds);

  final SurfacePublication publication;
  final Map<String, Uint8List> _screenBlobs;
  final Map<String, CapabilityManifest> _sidecarCapabilities;
  final FlowDocument? flowDocument;

  /// The icon fonts the publication declares.
  final List<DeliveredIconFont> iconFonts;

  /// The local seeds the publication declares, by root or screen id.
  final Map<String, Map<String, Object>> localSeeds;

  List<String> get screenIds => List.unmodifiable(_screenBlobs.keys);

  /// The verified screen blobs, by screen id.
  Map<String, Uint8List> get screenBlobs => _screenBlobs;

  /// The capabilities each screen blob's sidecar declares, by screen id.
  Map<String, CapabilityManifest> get sidecarCapabilities =>
      _sidecarCapabilities;

  /// Reassembles the canonical payload from these already verified raw files.
  SurfacePayload assemblePayload() {
    final capabilities = capabilityManifestUnion(_sidecarCapabilities.values);
    final document = flowDocument;
    final SurfacePayload payload = document == null
        ? BlobSurfacePayload(
            minClient: capabilities.builtInFloor,
            blob: _screenBlobs[publication.slug]!,
            requiredLibraries: capabilities.requiredLibraries,
            iconFonts: iconFonts,
            localSeeds: localSeeds)
        : FlowSurfacePayload(
            flowDocument: document,
            screenBlobs: _screenBlobs,
            requiredLibraries: capabilities.requiredLibraries,
            iconFonts: iconFonts,
            localSeeds: localSeeds);
    validateAssembledPayload(payload.canonicalBytes);
    return payload;
  }

  void validateAssembledPayload(List<int> payloadBytes) {
    final payload = _decodeCanonicalPayload(payloadBytes);
    publication.validatePayload(payload);
    if (!_sameIconFonts(iconFonts, payload.iconFonts) ||
        !_sameLocalSeeds(localSeeds, payload.localSeeds)) {
      throw const FormatException(
        'Assembled payload sections do not match declared artifacts.',
      );
    }
    switch (payload) {
      case BlobSurfacePayload():
        final blob = _screenBlobs[publication.slug];
        final capabilities = _sidecarCapabilities[publication.slug];
        if (blob == null || capabilities == null) {
          throw const FormatException(
              'Missing standalone blob artifact closure.');
        }
        if (!SurfaceContractJson.bytesEqual(blob, payload.blob)) {
          throw const FormatException(
            'Assembled blob payload does not match declared artifact bytes.',
          );
        }
        final actualCapabilities = CapabilityManifest(
          builtInFloor: payload.minClient,
          requiredLibraries: payload.requiredLibraries,
        );
        if (!SurfaceContractJson.requirementsEqual(
          capabilities,
          actualCapabilities,
        )) {
          throw const FormatException(
            'Blob payload capabilities do not match its sidecar.',
          );
        }
      case FlowSurfacePayload():
        final expectedFlowDocument = flowDocument;
        if (expectedFlowDocument == null) {
          throw const FormatException(
              'Missing declared flow document artifact.');
        }
        if (!SurfaceContractJson.bytesEqual(
          FlowDocumentCodec.encodeCanonicalJson(expectedFlowDocument),
          FlowDocumentCodec.encodeCanonicalJson(payload.flowDocument),
        )) {
          throw const FormatException(
            'Assembled flow payload does not match declared flow document.',
          );
        }
        if (payload.screenBlobs.length != _screenBlobs.length) {
          throw const FormatException(
            'Assembled flow payload has a different screen closure.',
          );
        }
        for (final entry in _screenBlobs.entries) {
          final actual = payload.screenBlobs[entry.key];
          if (actual == null ||
              !SurfaceContractJson.bytesEqual(entry.value, actual)) {
            throw FormatException(
              'Assembled flow payload does not match screen artifact "${entry.key}".',
            );
          }
        }
        final sidecarUnion =
            capabilityManifestUnion(_sidecarCapabilities.values);
        final payloadCapabilities = CapabilityManifest(
          builtInFloor: payload.minClient,
          requiredLibraries: payload.requiredLibraries,
        );
        if (payload.minClient < sidecarUnion.builtInFloor ||
            !_sameRequirements(
              sidecarUnion.requiredLibraries,
              payloadCapabilities.requiredLibraries,
            )) {
          throw const FormatException(
            'Flow payload capabilities do not match its sidecar closure.',
          );
        }
    }
  }
}

@immutable
final class SurfacePublicationManifest {
  factory SurfacePublicationManifest({
    required List<SurfacePublicationManifestEntry> publications,
  }) {
    final identities = <String>{};
    final artifactsByPath = <String, SurfacePublicationArtifact>{};
    for (final entry in publications) {
      final identity =
          '${entry.publication.surface.wireName}\u0000${entry.publication.slug}';
      if (!identities.add(identity)) {
        throw FormatException(
          'Duplicate publication identity "${entry.publication.surface.wireName}/${entry.publication.slug}".',
        );
      }
      for (final artifact in entry.artifacts) {
        final existing = artifactsByPath[artifact.path];
        if (existing == null) {
          artifactsByPath[artifact.path] = artifact;
        } else if (existing.contentHash != artifact.contentHash ||
            existing.role != artifact.role ||
            existing.id != artifact.id) {
          throw FormatException(
            'Artifact path "${artifact.path}" has conflicting declarations.',
          );
        }
      }
    }
    // Entry construction rejects duplicate paths within one closure. Paths may
    // repeat across entries only for the same source artifact declaration.
    return SurfacePublicationManifest._(List.unmodifiable(publications));
  }

  const SurfacePublicationManifest._(this.publications);

  static const int schemaVersion = _surfacePublicationSchemaVersion;

  final List<SurfacePublicationManifestEntry> publications;

  Map<String, Object?> toJson() => <String, Object?>{
        'schemaVersion': schemaVersion,
        'publications': <Object?>[
          for (final publication in publications) publication.toJson(),
        ],
      };

  /// This manifest with every entry and the entry list in canonical order.
  SurfacePublicationManifest canonical() => SurfacePublicationManifest(
        publications: [
          for (final entry in publications) entry.canonical(),
        ]..sort((left, right) {
            final surface = left.publication.surface.wireName.compareTo(
              right.publication.surface.wireName,
            );
            if (surface != 0) return surface;
            return left.publication.slug.compareTo(right.publication.slug);
          }),
      );

  List<SurfacePublicationArtifactClosure> validateArtifactClosure(
    Map<String, List<int>> files,
  ) {
    final declaredPaths = <String>{
      for (final entry in publications)
        for (final artifact in entry.artifacts) artifact.path,
    };
    for (final path in files.keys) {
      if (!declaredPaths.contains(path)) {
        throw FormatException('Undeclared artifact path "$path".');
      }
    }
    final closures = <SurfacePublicationArtifactClosure>[];
    for (final entry in publications) {
      final bytesByPath = <String, Uint8List>{};
      for (final artifact in entry.artifacts) {
        final bytes = files[artifact.path];
        if (bytes == null) {
          throw FormatException(
              'Missing declared artifact "${artifact.path}".');
        }
        final frozen = Uint8List.fromList(bytes);
        final actualHash = CapabilitySidecar.hashBlob(frozen);
        if (actualHash != artifact.contentHash) {
          throw FormatException(
            'Artifact hash does not match "${artifact.path}".',
          );
        }
        bytesByPath[artifact.path] = frozen;
      }
      closures.add(_validateEntryBytes(entry, bytesByPath));
    }
    return List.unmodifiable(closures);
  }

  static SurfacePublicationManifest fromJson(Object? value) {
    final json = SurfaceContractJson.requireObject(value, r'$');
    SurfaceContractJson.exactKeys(
      json,
      const {'schemaVersion', 'publications'},
      r'$',
    );
    final schemaVersion = SurfaceContractJson.requiredInt(
      json,
      'schemaVersion',
      r'$',
    );
    if (schemaVersion != SurfacePublicationManifest.schemaVersion) {
      throw FormatException(
        'Unsupported surface publication manifest schemaVersion $schemaVersion.',
      );
    }
    final rawPublications = SurfaceContractJson.requireList(
      SurfaceContractJson.requiredValue(json, 'publications', r'$'),
      r'$.publications',
    );
    return SurfacePublicationManifest(
      publications: <SurfacePublicationManifestEntry>[
        for (var index = 0; index < rawPublications.length; index += 1)
          SurfacePublicationManifestEntry.fromJson(
            rawPublications[index],
            path: r'$.publications[' + index.toString() + ']',
          ),
      ],
    );
  }
}

abstract final class SurfacePublicationManifestV1Codec {
  static SurfacePublicationManifest decode(Object? value) =>
      SurfacePublicationManifest.fromJson(value);

  static SurfacePublicationManifest decodeJson(String source) => decode(
        SurfaceContractJson.decode(
          source,
          label: 'surface publication manifest',
        ),
      );

  static Map<String, Object?> encode(SurfacePublicationManifest manifest) =>
      manifest.toJson();

  static String encodeCanonicalJson(SurfacePublicationManifest manifest) =>
      SurfaceContractJson.encode(encode(manifest));
}

@immutable
final class SurfacePublicationUploadRequest {
  factory SurfacePublicationUploadRequest({
    required SurfacePublication publication,
    required List<int> payload,
    SurfacePublicationManifest? artifactManifest,
    Map<String, List<int>> artifactBytesByPath = const {},
  }) {
    if (artifactBytesByPath.isNotEmpty && artifactManifest == null) {
      throw const FormatException(
          'Declared artifacts require their actual manifest.');
    }
    if (artifactBytesByPath.length > maxArtifactCount) {
      throw const FormatException('Too many declared publication artifacts.');
    }
    var artifactByteLength = 0;
    final bytes = <String, Uint8List>{};
    final declaredPaths = artifactManifest?.publications
            .expand((entry) => entry.artifacts)
            .map((artifact) => artifact.path)
            .toSet() ??
        <String>{};
    if (declaredPaths.length > maxArtifactCount ||
        (artifactManifest?.publications.length ?? 0) > maxArtifactCount) {
      throw const FormatException('Too many declared publication artifacts.');
    }
    for (final entry in artifactBytesByPath.entries) {
      if (!declaredPaths.contains(entry.key)) {
        throw FormatException(
            'Undeclared publication artifact "${entry.key}".');
      }
      artifactByteLength += entry.value.length;
      if (artifactByteLength > maxArtifactBytes) {
        throw const FormatException(
            'Declared publication artifacts exceed the byte limit.');
      }
      bytes[entry.key] = Uint8List.fromList(entry.value);
    }
    if (artifactManifest != null &&
        !artifactManifest.publications.any((entry) => sameCanonicalJson(
            entry.publication.toJson(), publication.toJson()))) {
      throw const FormatException(
          'Artifact manifest omits the exact root publication.');
    }
    final canonicalPayload = _decodeCanonicalPayload(payload);
    publication.validatePayload(canonicalPayload);
    return SurfacePublicationUploadRequest._(
      publication: publication,
      payload: Uint8List.fromList(payload),
      artifactManifest: artifactManifest,
      artifactBytesByPath: Map.unmodifiable(bytes),
    );
  }

  const SurfacePublicationUploadRequest._({
    required this.publication,
    required Uint8List payload,
    required this.artifactManifest,
    required Map<String, Uint8List> artifactBytesByPath,
  })  : _payload = payload,
        _artifactBytesByPath = artifactBytesByPath;

  /// Bounded exact file closure, including reachable descendant publications.
  static const int maxArtifactCount = 1024;
  static const int maxArtifactBytes = 64 * 1024 * 1024;

  static const int schemaVersion = _surfacePublicationSchemaVersion;

  final SurfacePublication publication;
  final Uint8List _payload;

  /// Actual compiler manifest for the selected complete publication closure.
  final SurfacePublicationManifest? artifactManifest;
  final Map<String, Uint8List> _artifactBytesByPath;

  /// Exact deduplicated raw files; bound uploads may supply root files outside
  /// this canonical request through their existing declared-artifact transport.
  Map<String, Uint8List> get artifactBytesByPath => Map.unmodifiable({
        for (final entry in _artifactBytesByPath.entries)
          entry.key: Uint8List.fromList(entry.value),
      });

  Uint8List get payload => Uint8List.fromList(_payload);

  Map<String, Object?> toJson() => <String, Object?>{
        'schemaVersion': schemaVersion,
        'publication': publication.toJson(),
        'payload': SurfaceContractJson.encodeBase64Url(_payload),
        if (artifactManifest != null)
          'artifactManifest': artifactManifest!.toJson(),
        if (_artifactBytesByPath.isNotEmpty)
          'declaredArtifactClosure': [
            for (final path
                in _artifactBytesByPath.keys.toList()
                  ..sort(compareGeneratedOutputPaths))
              {
                'path': path,
                'bytes': SurfaceContractJson.encodeBase64Url(
                    _artifactBytesByPath[path]!)
              },
          ],
      };

  static SurfacePublicationUploadRequest fromJson(Object? value) {
    final json = SurfaceContractJson.requireObject(value, r'$');
    SurfaceContractJson.exactKeys(
      json,
      {
        'schemaVersion',
        'publication',
        'payload',
        if (json.containsKey('artifactManifest')) 'artifactManifest',
        if (json.containsKey('declaredArtifactClosure'))
          'declaredArtifactClosure',
      },
      r'$',
    );
    _requireSchemaVersion(json, 'surface publication upload request');
    return SurfacePublicationUploadRequest(
      artifactManifest: json.containsKey('artifactManifest')
          ? SurfacePublicationManifest.fromJson(json['artifactManifest'])
          : null,
      artifactBytesByPath: _decodeUploadArtifactBytes(json),
      publication: SurfacePublication.fromJson(
        SurfaceContractJson.requiredValue(json, 'publication', r'$'),
        path: r'$.publication',
      ),
      payload: SurfaceContractJson.decodeCanonicalBase64Url(
        SurfaceContractJson.requiredString(json, 'payload', r'$'),
        r'$.payload',
      ),
    );
  }
}

abstract final class SurfacePublicationUploadRequestV1Codec {
  static SurfacePublicationUploadRequest decode(Object? value) =>
      SurfacePublicationUploadRequest.fromJson(value);

  static SurfacePublicationUploadRequest decodeJson(String source) => decode(
        SurfaceContractJson.decode(
          source,
          label: 'surface publication upload request',
        ),
      );

  static Map<String, Object?> encode(
    SurfacePublicationUploadRequest request,
  ) =>
      request.toJson();

  static String encodeCanonicalJson(SurfacePublicationUploadRequest request) =>
      SurfaceContractJson.encode(encode(request));
}

@immutable
final class SurfaceScreenDeliveryRequest {
  factory SurfaceScreenDeliveryRequest({
    required Surface surface,
    required String slug,
    required int contractVersion,
    String? assignmentKey,
    String? meteringKey,
    String? analyticsAnonymousId,
    String? sdkSupportedPolicyRevisions,
    String? assignmentCanonicalBase64,
    String? sdkBuiltInsCanonicalBase64,
    String? sdkInstalledLibraries,
  }) {
    _requireIdentity(slug, 'delivery request.slug');
    if (contractVersion < 1) {
      throw const FormatException(
          'delivery request.contractVersion must be positive.');
    }
    return SurfaceScreenDeliveryRequest._(
      surface: surface,
      slug: slug,
      contractVersion: contractVersion,
      assignmentKey: normalizeAssignmentKey(assignmentKey),
      meteringKey: normalizeMeteringKey(meteringKey),
      analyticsAnonymousId: normalizeAnalyticsAnonymousId(analyticsAnonymousId),
      sdkSupportedPolicyRevisions: sdkSupportedPolicyRevisions,
      assignmentCanonicalBase64: assignmentCanonicalBase64,
      sdkBuiltInsCanonicalBase64: sdkBuiltInsCanonicalBase64,
      sdkInstalledLibraries: sdkInstalledLibraries,
    );
  }

  const SurfaceScreenDeliveryRequest._({
    required this.surface,
    required this.slug,
    required this.contractVersion,
    required this.assignmentKey,
    required this.meteringKey,
    required this.analyticsAnonymousId,
    required this.sdkSupportedPolicyRevisions,
    required this.assignmentCanonicalBase64,
    required this.sdkBuiltInsCanonicalBase64,
    required this.sdkInstalledLibraries,
  });

  static const int schemaVersion = _surfacePublicationSchemaVersion;

  static String? normalizeAssignmentKey(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return value.trim() == value && !value.contains('\u0000') ? value : null;
  }

  static String? normalizeMeteringKey(Object? value) {
    if (value is! String || value.length != 36) return null;
    for (var index = 0; index < value.length; index += 1) {
      final unit = value.codeUnitAt(index);
      if (index == 8 || index == 13 || index == 18 || index == 23) {
        if (unit != 0x2D) return null;
        continue;
      }
      final hex = (unit >= 0x30 && unit <= 0x39) ||
          (unit >= 0x41 && unit <= 0x46) ||
          (unit >= 0x61 && unit <= 0x66);
      if (!hex) return null;
    }
    return value;
  }

  static String? normalizeAnalyticsAnonymousId(Object? value) =>
      normalizeMeteringKey(value);

  final Surface surface;
  final String slug;
  final int contractVersion;
  final String? assignmentKey;
  final String? meteringKey;
  final String? analyticsAnonymousId;
  final String? sdkSupportedPolicyRevisions;

  /// The canonical assignment the device already holds, passed through as sent.
  final String? assignmentCanonicalBase64;

  /// The device's canonical audience observations, passed through as sent.
  final String? sdkBuiltInsCanonicalBase64;

  /// The build's installed custom widget libraries, as the base64url report.
  final String? sdkInstalledLibraries;

  Map<String, Object?> toJson() => <String, Object?>{
        'schemaVersion': schemaVersion,
        'surface': surface.wireName,
        'slug': slug,
        'contractVersion': contractVersion,
        if (assignmentKey != null) 'assignmentKey': assignmentKey,
        if (meteringKey != null) 'meteringKey': meteringKey,
        if (analyticsAnonymousId != null)
          'analyticsAnonymousId': analyticsAnonymousId,
        if (sdkSupportedPolicyRevisions != null)
          'sdkSupportedPolicyRevisions': sdkSupportedPolicyRevisions,
        if (assignmentCanonicalBase64 != null)
          'assignmentCanonicalBase64': assignmentCanonicalBase64,
        if (sdkBuiltInsCanonicalBase64 != null)
          'sdkBuiltInsCanonicalBase64': sdkBuiltInsCanonicalBase64,
        if (sdkInstalledLibraries != null)
          'sdkInstalledLibraries': sdkInstalledLibraries,
      };

  static SurfaceScreenDeliveryRequest fromJson(Object? value) {
    final json = SurfaceContractJson.requireObject(value, r'$');
    SurfaceContractJson.allowedKeys(
      json,
      const {
        'schemaVersion',
        'surface',
        'slug',
        'contractVersion',
        'assignmentKey',
        'meteringKey',
        'analyticsAnonymousId',
        'sdkSupportedPolicyRevisions',
        'assignmentCanonicalBase64',
        'sdkBuiltInsCanonicalBase64',
        'sdkInstalledLibraries',
      },
      r'$',
    );
    _requireSchemaVersion(json, 'surface screen delivery request');
    return SurfaceScreenDeliveryRequest(
      surface: Surface.fromWireName(
        SurfaceContractJson.requiredString(json, 'surface', r'$'),
      ),
      slug: SurfaceContractJson.requiredString(json, 'slug', r'$'),
      contractVersion: SurfaceContractJson.requiredPositiveInt(
        json,
        'contractVersion',
        r'$',
      ),
      assignmentKey: normalizeAssignmentKey(json['assignmentKey']),
      meteringKey: normalizeMeteringKey(json['meteringKey']),
      analyticsAnonymousId:
          normalizeAnalyticsAnonymousId(json['analyticsAnonymousId']),
      sdkSupportedPolicyRevisions: _boundedSupportedPolicyRevisions(
        SurfaceContractJson.optionalString(
          json,
          'sdkSupportedPolicyRevisions',
          r'$',
        ),
      ),
      assignmentCanonicalBase64: SurfaceContractJson.optionalString(
        json,
        'assignmentCanonicalBase64',
        r'$',
      ),
      sdkBuiltInsCanonicalBase64: SurfaceContractJson.optionalString(
        json,
        'sdkBuiltInsCanonicalBase64',
        r'$',
      ),
      sdkInstalledLibraries: SurfaceContractJson.optionalString(
        json,
        'sdkInstalledLibraries',
        r'$',
      ),
    );
  }
}

abstract final class SurfaceScreenDeliveryRequestV1Codec {
  static SurfaceScreenDeliveryRequest decode(Object? value) =>
      SurfaceScreenDeliveryRequest.fromJson(value);

  static SurfaceScreenDeliveryRequest decodeJson(String source) => decode(
        SurfaceContractJson.decode(
          source,
          label: 'surface screen delivery request',
        ),
      );

  static Map<String, Object?> encode(SurfaceScreenDeliveryRequest request) =>
      request.toJson();

  static String encodeCanonicalJson(SurfaceScreenDeliveryRequest request) =>
      SurfaceContractJson.encode(encode(request));
}

@immutable

/// A delivered contract fingerprint that does not match the tuple it is
/// checked against — the screen's contract moved relative to this reader.
///
/// A [FormatException] so existing readers keep classifying it as a rejected
/// response; readers that can tell contract drift from a malformed frame catch
/// this first.
final class SurfaceScreenContractFingerprintMismatch extends FormatException {
  /// Creates a fingerprint mismatch with [message].
  const SurfaceScreenContractFingerprintMismatch(super.message);
}

@immutable
final class SurfaceScreenDeliveryResponse {
  factory SurfaceScreenDeliveryResponse({
    required SurfaceDocument document,
    required SurfaceSourceKind sourceKind,
    required SurfacePayloadKind payloadKind,
    required int contractVersion,
    required int publishedRevision,
    required String contractFingerprint,
    required String eventContractHash,
    String? hostDataContractHash,
  }) {
    if (sourceKind != SurfaceSourceKind.screen ||
        payloadKind != SurfacePayloadKind.blob ||
        document.payload is! BlobSurfacePayload) {
      throw const FormatException(
        'A generic screen delivery response requires a screen blob document.',
      );
    }
    _requireIdentity(
      document.surfaceSlug,
      'delivery response.document.surfaceSlug',
    );
    if (contractVersion < 1 || publishedRevision < 1 || document.version < 1) {
      throw const FormatException(
          'Delivery response versions must be positive.');
    }
    if (publishedRevision != document.version) {
      throw const FormatException(
        'publishedRevision must equal document.version.',
      );
    }
    SurfaceContractJson.requireSha256(
      contractFingerprint,
      'delivery response.contractFingerprint',
    );
    SurfaceContractJson.requireSha256(
      eventContractHash,
      'delivery response.eventContractHash',
    );
    if (document.minClient < 1) {
      throw const FormatException(
          'Delivery document minClient must be positive.');
    }
    final capabilities = CapabilityManifest(
      builtInFloor: document.minClient,
      requiredLibraries: document.requiredLibraries,
    );
    if (hostDataContractHash != null) {
      SurfaceContractJson.requireSha256(
        hostDataContractHash,
        'delivery response.hostDataContractHash',
      );
    }
    final expectedFingerprint = SurfaceScreenContractFingerprint.hash(
      sourceKind: sourceKind,
      payloadKind: payloadKind,
      capabilities: capabilities,
      eventContractHash: eventContractHash,
      hostDataContractHash: hostDataContractHash,
    );
    if (contractFingerprint != expectedFingerprint) {
      throw const SurfaceScreenContractFingerprintMismatch(
        'Delivery response contractFingerprint does not match document metadata.',
      );
    }
    return SurfaceScreenDeliveryResponse._(
      document: document,
      sourceKind: sourceKind,
      payloadKind: payloadKind,
      contractVersion: contractVersion,
      publishedRevision: publishedRevision,
      contractFingerprint: contractFingerprint,
      eventContractHash: eventContractHash,
      hostDataContractHash: hostDataContractHash,
    );
  }

  const SurfaceScreenDeliveryResponse._({
    required this.document,
    required this.sourceKind,
    required this.payloadKind,
    required this.contractVersion,
    required this.publishedRevision,
    required this.contractFingerprint,
    required this.eventContractHash,
    required this.hostDataContractHash,
  });

  static const int schemaVersion = _surfacePublicationSchemaVersion;

  final SurfaceDocument document;
  final SurfaceSourceKind sourceKind;
  final SurfacePayloadKind payloadKind;
  final int contractVersion;
  final int publishedRevision;
  final String contractFingerprint;
  final String eventContractHash;

  /// Content hash of the family's host-data contract, absent when the screen
  /// declares no host-supplied input.
  final String? hostDataContractHash;
}

/// What a standalone-screen delivery puts on the wire.
///
/// Everything [SurfaceScreenDeliveryResponse] carries EXCEPT the rendered
/// document, plus where to fetch the bytes that make one. The rendered document
/// is no longer sent inline; it is assembled by the reader from
/// [artifact] and the payload frame that artifact names, and only then handed
/// to [SurfaceScreenDeliveryResponse]'s constructor — which is unchanged, so
/// every correlation this contract has ever enforced (the fingerprint recompute
/// against the assembled document, `publishedRevision == document.version`, the
/// screen/blob shape requirement) is enforced on exactly the same terms and in
/// exactly the same place.
///
/// The payload SHAPE is not a field here: it rides [artifact] with everything
/// else the publication record claims about the bytes, so there is one place a
/// claim about the artifact can be made and one place it is checked.
@immutable
final class SurfaceScreenDeliveryDescriptor {
  /// Creates a standalone-screen delivery descriptor.
  factory SurfaceScreenDeliveryDescriptor({
    required SurfaceArtifactDescriptor artifact,
    required SurfaceSourceKind sourceKind,
    required int contractVersion,
    required int publishedRevision,
    required String contractFingerprint,
    required String eventContractHash,
    String? hostDataContractHash,
  }) {
    if (sourceKind != SurfaceSourceKind.screen) {
      throw const FormatException(
        'A generic screen delivery descriptor requires a screen source.',
      );
    }
    // The shape claim is optional on an artifact descriptor in general — the
    // shape-agnostic serve route legitimately makes none. This wire is not
    // general: it delivers exactly one shape, so an absent claim here is a
    // missing field rather than a deliberate silence.
    if (artifact.payloadKind != SurfacePayloadKind.blob.wireName) {
      throw const FormatException(
        'A generic screen delivery descriptor requires a blob artifact.',
      );
    }
    if (contractVersion < 1 || publishedRevision < 1) {
      throw const FormatException(
        'Delivery descriptor versions must be positive.',
      );
    }
    if (publishedRevision != artifact.version) {
      throw const FormatException(
        'publishedRevision must equal the artifact version.',
      );
    }
    SurfaceContractJson.requireSha256(
      contractFingerprint,
      'delivery descriptor.contractFingerprint',
    );
    SurfaceContractJson.requireSha256(
      eventContractHash,
      'delivery descriptor.eventContractHash',
    );
    if (hostDataContractHash != null) {
      SurfaceContractJson.requireSha256(
        hostDataContractHash,
        'delivery descriptor.hostDataContractHash',
      );
    }
    return SurfaceScreenDeliveryDescriptor._(
      artifact: artifact,
      sourceKind: sourceKind,
      contractVersion: contractVersion,
      publishedRevision: publishedRevision,
      contractFingerprint: contractFingerprint,
      eventContractHash: eventContractHash,
      hostDataContractHash: hostDataContractHash,
    );
  }

  const SurfaceScreenDeliveryDescriptor._({
    required this.artifact,
    required this.sourceKind,
    required this.contractVersion,
    required this.publishedRevision,
    required this.contractFingerprint,
    required this.eventContractHash,
    required this.hostDataContractHash,
  });

  /// The publication schema this descriptor speaks.
  static const int schemaVersion = _surfacePublicationSchemaVersion;

  /// Where the payload frame is, what it must hash to, and what the record
  /// claims about it.
  final SurfaceArtifactDescriptor artifact;

  /// Always [SurfaceSourceKind.screen] on this wire.
  final SurfaceSourceKind sourceKind;

  /// The contract family version this delivery answers.
  final int contractVersion;

  /// The published revision being delivered.
  final int publishedRevision;

  /// Fingerprint of the family's declared contract.
  final String contractFingerprint;

  /// Content hash of the family's event contract.
  final String eventContractHash;

  /// Content hash of the family's host-data contract, absent when the screen
  /// declares no host-supplied input.
  final String? hostDataContractHash;

  /// The descriptor as wire JSON.
  Map<String, Object?> toJson() => <String, Object?>{
        'schemaVersion': schemaVersion,
        'artifact': artifact.toJson(),
        'sourceKind': sourceKind.wireName,
        'contractVersion': contractVersion,
        'publishedRevision': publishedRevision,
        'contractFingerprint': contractFingerprint,
        'eventContractHash': eventContractHash,
        if (hostDataContractHash != null)
          'hostDataContractHash': hostDataContractHash,
      };

  /// Decodes a descriptor strictly.
  static SurfaceScreenDeliveryDescriptor fromJson(Object? value) {
    final json = SurfaceContractJson.requireObject(value, r'$');
    SurfaceContractJson.allowedKeys(
      json,
      const {
        'schemaVersion',
        'artifact',
        'sourceKind',
        'contractVersion',
        'publishedRevision',
        'contractFingerprint',
        'eventContractHash',
        'hostDataContractHash',
      },
      r'$',
    );
    _requireSchemaVersion(json, 'surface screen delivery descriptor');
    return SurfaceScreenDeliveryDescriptor(
      artifact: SurfaceArtifactDescriptorV1Codec.decode(
        SurfaceContractJson.requiredValue(json, 'artifact', r'$'),
      ),
      sourceKind: SurfaceSourceKind.fromWireName(
        SurfaceContractJson.requiredString(json, 'sourceKind', r'$'),
      ),
      contractVersion: SurfaceContractJson.requiredPositiveInt(
        json,
        'contractVersion',
        r'$',
      ),
      publishedRevision: SurfaceContractJson.requiredPositiveInt(
        json,
        'publishedRevision',
        r'$',
      ),
      contractFingerprint: SurfaceContractJson.requiredString(
        json,
        'contractFingerprint',
        r'$',
      ),
      eventContractHash: SurfaceContractJson.requiredString(
        json,
        'eventContractHash',
        r'$',
      ),
      hostDataContractHash: json.containsKey('hostDataContractHash')
          ? SurfaceContractJson.requiredString(
              json,
              'hostDataContractHash',
              r'$',
            )
          : null,
    );
  }

  /// Completes this descriptor into a delivery response with [document].
  ///
  /// The one place the two halves are joined. It deliberately routes through
  /// [SurfaceScreenDeliveryResponse]'s own constructor rather than
  /// reconstructing the checks: the fingerprint recompute has to run against
  /// the document that was actually assembled from fetched bytes, or it proves
  /// nothing about them.
  ///
  /// [readerHostDataContractHash] is the reader's own compiled-in host-data
  /// contract hash, used only while no serve route carries one. The wire wins
  /// whenever it supplies the value, so a delivery that does carry it is
  /// checked entirely against served metadata.
  SurfaceScreenDeliveryResponse completeWith(
    SurfaceDocument document, {
    String? readerHostDataContractHash,
  }) =>
      SurfaceScreenDeliveryResponse(
        document: document,
        sourceKind: sourceKind,
        payloadKind: SurfacePayloadKind.fromWireName(artifact.payloadKind!),
        contractVersion: contractVersion,
        publishedRevision: publishedRevision,
        contractFingerprint: contractFingerprint,
        eventContractHash: eventContractHash,
        hostDataContractHash:
            hostDataContractHash ?? readerHostDataContractHash,
      );
}

/// Strict codec for [SurfaceScreenDeliveryDescriptor].
abstract final class SurfaceScreenDeliveryDescriptorV1Codec {
  /// Decodes a descriptor from a decoded JSON value.
  static SurfaceScreenDeliveryDescriptor decode(Object? value) =>
      SurfaceScreenDeliveryDescriptor.fromJson(value);

  /// Decodes a descriptor from a JSON document.
  static SurfaceScreenDeliveryDescriptor decodeJson(String source) => decode(
        SurfaceContractJson.decode(
          source,
          label: 'surface screen delivery descriptor',
        ),
      );

  /// Encodes a descriptor to wire JSON.
  static Map<String, Object?> encode(
    SurfaceScreenDeliveryDescriptor descriptor,
  ) =>
      descriptor.toJson();

  /// Encodes a descriptor to a canonical JSON document.
  static String encodeCanonicalJson(
    SurfaceScreenDeliveryDescriptor descriptor,
  ) =>
      SurfaceContractJson.encode(encode(descriptor));
}

/// Inert selection metadata accompanying a surface delivery.
@immutable
final class SurfaceRoutingSelectionProvenanceV1 {
  /// Creates bounded selection metadata.
  SurfaceRoutingSelectionProvenanceV1({
    this.selectedRouteId,
    this.audienceRevisionRef,
    this.routingRevisionOrdinal,
    this.rolloutAllocationId,
    this.rolloutBranch,
    this.defaultSelectionReason,
  }) {
    _selectionString(selectedRouteId, 'selectedRouteId');
    _selectionString(audienceRevisionRef, 'audienceRevisionRef');
    _selectionOrdinal(routingRevisionOrdinal, 'routingRevisionOrdinal');
    _selectionString(rolloutAllocationId, 'rolloutAllocationId');
    _selectionString(rolloutBranch, 'rolloutBranch');
    _selectionString(defaultSelectionReason, 'defaultSelectionReason');
  }

  /// Decodes selection metadata, refusing unknown or invalid members.
  factory SurfaceRoutingSelectionProvenanceV1.fromJson(Object? value) {
    final json = SurfaceContractJson.requireObject(value, 'selection');
    SurfaceContractJson.allowedKeys(
        json,
        const {
          'selectedRouteId',
          'audienceRevisionRef',
          'routingRevisionOrdinal',
          'rolloutAllocationId',
          'rolloutBranch',
          'defaultSelectionReason',
        },
        'selection');
    return SurfaceRoutingSelectionProvenanceV1(
      selectedRouteId:
          _selectionString(json['selectedRouteId'], 'selectedRouteId'),
      audienceRevisionRef:
          _selectionString(json['audienceRevisionRef'], 'audienceRevisionRef'),
      routingRevisionOrdinal: _selectionOrdinal(
          json['routingRevisionOrdinal'], 'routingRevisionOrdinal'),
      rolloutAllocationId:
          _selectionString(json['rolloutAllocationId'], 'rolloutAllocationId'),
      rolloutBranch: _selectionString(json['rolloutBranch'], 'rolloutBranch'),
      defaultSelectionReason: _selectionString(
          json['defaultSelectionReason'], 'defaultSelectionReason'),
    );
  }

  /// Treats malformed optional delivery metadata as absent.
  static SurfaceRoutingSelectionProvenanceV1? normalize(Object? value) {
    if (value == null) return null;
    try {
      return SurfaceRoutingSelectionProvenanceV1.fromJson(value);
    } on FormatException {
      return null;
    }
  }

  /// The selected route identifier.
  final String? selectedRouteId;

  /// The audience revision reference.
  final String? audienceRevisionRef;

  /// The non-negative routing revision ordinal.
  final int? routingRevisionOrdinal;

  /// The rollout allocation identifier.
  final String? rolloutAllocationId;

  /// The rollout branch.
  final String? rolloutBranch;

  /// The bounded reason for a default selection.
  final String? defaultSelectionReason;

  Map<String, Object?> toJson() => {
        if (selectedRouteId != null) 'selectedRouteId': selectedRouteId,
        if (audienceRevisionRef != null)
          'audienceRevisionRef': audienceRevisionRef,
        if (routingRevisionOrdinal != null)
          'routingRevisionOrdinal': routingRevisionOrdinal,
        if (rolloutAllocationId != null)
          'rolloutAllocationId': rolloutAllocationId,
        if (rolloutBranch != null) 'rolloutBranch': rolloutBranch,
        if (defaultSelectionReason != null)
          'defaultSelectionReason': defaultSelectionReason,
      };

  @override
  bool operator ==(Object other) =>
      other is SurfaceRoutingSelectionProvenanceV1 &&
      selectedRouteId == other.selectedRouteId &&
      audienceRevisionRef == other.audienceRevisionRef &&
      routingRevisionOrdinal == other.routingRevisionOrdinal &&
      rolloutAllocationId == other.rolloutAllocationId &&
      rolloutBranch == other.rolloutBranch &&
      defaultSelectionReason == other.defaultSelectionReason;

  @override
  int get hashCode => Object.hash(
        selectedRouteId,
        audienceRevisionRef,
        routingRevisionOrdinal,
        rolloutAllocationId,
        rolloutBranch,
        defaultSelectionReason,
      );
}

String? _selectionString(Object? value, String key) {
  if (value == null) return null;
  if (value is! String || value.length > 256) {
    throw FormatException(
        'Expected "$key" to be a string of at most 256 characters.');
  }
  SurfaceContractJson.requireUnicodeScalars(value, key);
  return value;
}

int? _selectionOrdinal(Object? value, String key) {
  if (value == null) return null;
  if (value is! int || value < 0) {
    throw FormatException('Expected "$key" to be a non-negative integer.');
  }
  return value;
}

/// The sole experiment assignment a delivery response may carry.
///
/// Inert data the host echoes back on matching measurement events. It observes
/// nothing about the app and the reader never interprets it.
@immutable
final class CanonicalSurfaceExperimentAssignmentV1 {
  /// Creates a canonical assignment from already-validated identities.
  CanonicalSurfaceExperimentAssignmentV1({
    required this.experimentId,
    required this.experimentRevisionId,
    required this.experimentEpochId,
    required this.armId,
    required this.outcomeLinkCarrier,
  }) {
    _requireOutcomeLinkCarrier(
      outcomeLinkCarrier,
      'assignment.outcomeLinkCarrier',
    );
  }

  /// Decodes a canonical assignment, refusing every noncanonical key.
  factory CanonicalSurfaceExperimentAssignmentV1.fromJson(Object? value) {
    final json = SurfaceContractJson.requireObject(value, 'assignment');
    SurfaceContractJson.exactKeys(json, _assignmentFields, 'assignment');
    _requireSchemaVersion(json, 'assignment');
    return CanonicalSurfaceExperimentAssignmentV1(
      experimentId: _identity(
        json,
        'experimentId',
        ExperimentPublicIdV1.new,
      ),
      experimentRevisionId: _identity(
        json,
        'experimentRevisionId',
        ExperimentPublicRevisionIdV1.new,
      ),
      experimentEpochId: _identity(
        json,
        'experimentEpochId',
        ExperimentPublicEpochIdV1.new,
      ),
      armId: _identity(json, 'armId', ExperimentPublicArmIdV1.new),
      outcomeLinkCarrier: SurfaceContractJson.requiredString(
        json,
        'outcomeLinkCarrier',
        'assignment',
      ),
    );
  }

  static const int schemaVersion = _surfacePublicationSchemaVersion;

  /// Longest accepted opaque carrier.
  static const int maxOutcomeLinkCarrierLength = 4096;

  final ExperimentPublicIdV1 experimentId;
  final ExperimentPublicRevisionIdV1 experimentRevisionId;
  final ExperimentPublicEpochIdV1 experimentEpochId;
  final ExperimentPublicArmIdV1 armId;

  /// Opaque capability the host echoes back; it exposes no readable identity.
  final String outcomeLinkCarrier;

  Map<String, Object?> toJson() => <String, Object?>{
        'schemaVersion': schemaVersion,
        'experimentId': experimentId.value,
        'experimentRevisionId': experimentRevisionId.value,
        'experimentEpochId': experimentEpochId.value,
        'armId': armId.value,
        'outcomeLinkCarrier': outcomeLinkCarrier,
      };

  @override
  bool operator ==(Object other) =>
      other is CanonicalSurfaceExperimentAssignmentV1 &&
      other.experimentId == experimentId &&
      other.experimentRevisionId == experimentRevisionId &&
      other.experimentEpochId == experimentEpochId &&
      other.armId == armId &&
      other.outcomeLinkCarrier == outcomeLinkCarrier;

  @override
  int get hashCode => Object.hash(
        experimentId,
        experimentRevisionId,
        experimentEpochId,
        armId,
        outcomeLinkCarrier,
      );
}

abstract final class CanonicalSurfaceExperimentAssignmentV1Codec {
  static CanonicalSurfaceExperimentAssignmentV1 decode(Object? value) =>
      CanonicalSurfaceExperimentAssignmentV1.fromJson(value);

  static CanonicalSurfaceExperimentAssignmentV1 decodeJson(String source) =>
      decode(SurfaceContractJson.decode(source, label: 'surface assignment'));

  static Map<String, Object?> encode(
    CanonicalSurfaceExperimentAssignmentV1 assignment,
  ) =>
      assignment.toJson();

  static String encodeCanonicalJson(
    CanonicalSurfaceExperimentAssignmentV1 assignment,
  ) =>
      SurfaceContractJson.encode(encode(assignment));
}

const Set<String> _assignmentFields = <String>{
  'armId',
  'experimentEpochId',
  'experimentId',
  'experimentRevisionId',
  'outcomeLinkCarrier',
  'schemaVersion',
};

/// Builds one identity member, mapping its rejection to a wire format error.
T _identity<T>(
  Map<String, Object?> json,
  String key,
  T Function(String value) build,
) {
  final value = SurfaceContractJson.requiredString(json, key, 'assignment');
  try {
    return build(value);
  } on ArgumentError catch (error) {
    throw FormatException(
        'Field "assignment.$key" is invalid: ${error.message}');
  }
}

void _requireOutcomeLinkCarrier(String value, String path) {
  if (value.isEmpty) {
    throw FormatException('Expected "$path" to be nonempty.');
  }
  if (value.length >
      CanonicalSurfaceExperimentAssignmentV1.maxOutcomeLinkCarrierLength) {
    throw FormatException('Expected "$path" to be at most '
        '${CanonicalSurfaceExperimentAssignmentV1.maxOutcomeLinkCarrierLength} '
        'characters.');
  }
  SurfaceContractJson.decodeCanonicalBase64Url(value, path);
}

const Set<String> _publicationFields = <String>{
  'capabilities',
  'contractFingerprint',
  'contractVersion',
  'deliveryMode',
  'eventContract',
  'eventContractHash',
  'fitRequirement',
  'fitRequirementHash',
  'compiledScreenContracts',
  'declaredPresentation',
  'hostDataContract',
  'hostDataContractHash',
  'mountName',
  'payloadContentHash',
  'payloadKind',
  'slug',
  'sourceKind',
  'surface',
};

final RegExp _mountNamePattern = RegExp(r'^[A-Z][A-Za-z0-9_$]{0,254}$');

Set<String> _publicationRequiredFields({
  required SurfaceSourceKind sourceKind,
  required SurfacePayloadKind payloadKind,
}) {
  final fields = <String>{
    'payloadContentHash',
    'payloadKind',
    'slug',
    'sourceKind',
    'surface',
  };
  if (sourceKind == SurfaceSourceKind.screen) {
    return <String>{
      ...fields,
      'capabilities',
      'contractFingerprint',
      'contractVersion',
      'eventContract',
      'eventContractHash',
    };
  }
  if (payloadKind == SurfacePayloadKind.flow) fields.add('deliveryMode');
  return fields;
}

void _requireNoScreenContract({
  required int? contractVersion,
  required CapabilityManifest? capabilities,
  required SurfaceScreenEventSchema? eventContract,
  required String? eventContractHash,
  required String? contractFingerprint,
  required SurfaceScreenHostDataSchema? hostDataContract,
  required String? hostDataContractHash,
}) {
  if (contractVersion != null ||
      capabilities != null ||
      eventContract != null ||
      eventContractHash != null ||
      contractFingerprint != null ||
      hostDataContract != null ||
      hostDataContractHash != null) {
    throw const FormatException(
      'Only a screen publication may carry generic screen contract metadata.',
    );
  }
}

void _validateArtifactShape(
  List<SurfacePublicationArtifact> artifacts,
  SurfacePublication publication,
) {
  final flowDocuments = <SurfacePublicationArtifact>[];
  final blobs = <String, SurfacePublicationArtifact>{};
  final sidecars = <String, SurfacePublicationArtifact>{};
  final fontIds = <String>{};
  final seedIds = <String>{};
  for (final artifact in artifacts) {
    switch (artifact.role) {
      case SurfacePublicationArtifactRole.flowDocument:
        flowDocuments.add(artifact);
      case SurfacePublicationArtifactRole.screenBlob:
        final id = artifact.id!;
        if (blobs.containsKey(id)) {
          throw FormatException('Duplicate screen blob artifact id "$id".');
        }
        blobs[id] = artifact;
      case SurfacePublicationArtifactRole.capabilitySidecar:
        final id = artifact.id!;
        if (sidecars.containsKey(id)) {
          throw FormatException('Duplicate capability sidecar id "$id".');
        }
        sidecars[id] = artifact;
      case SurfacePublicationArtifactRole.iconFont:
        final id = artifact.id!;
        if (!fontIds.add(id)) {
          throw FormatException('Duplicate icon font artifact id "$id".');
        }
      case SurfacePublicationArtifactRole.localSeeds:
        if (artifact.id != publication.slug || !seedIds.add(artifact.id!)) {
          throw const FormatException(
            'A publication declares at most one local seeds artifact, '
            'identified by its slug.',
          );
        }
    }
  }
  if (flowDocuments.length > 1 ||
      (publication.payloadKind == SurfacePayloadKind.flow &&
          flowDocuments.length != 1) ||
      (publication.payloadKind == SurfacePayloadKind.blob &&
          flowDocuments.isNotEmpty)) {
    throw const FormatException(
      'Artifact closure must carry exactly one flow document for a flow payload.',
    );
  }
  if (blobs.length != sidecars.length ||
      !blobs.keys.toSet().containsAll(sidecars.keys)) {
    throw const FormatException(
      'Every screen blob requires exactly one same-id capability sidecar.',
    );
  }
  if (publication.payloadKind == SurfacePayloadKind.blob &&
      (blobs.length != 1 || !blobs.containsKey(publication.slug))) {
    throw const FormatException(
      'A blob publication requires one slug-id screen blob and sidecar.',
    );
  }
}

SurfacePublicationArtifactClosure _validateEntryBytes(
  SurfacePublicationManifestEntry entry,
  Map<String, Uint8List> bytesByPath,
) {
  final artifactsByRole =
      <SurfacePublicationArtifactRole, List<SurfacePublicationArtifact>>{};
  for (final artifact in entry.artifacts) {
    (artifactsByRole[artifact.role] ??= <SurfacePublicationArtifact>[])
        .add(artifact);
  }
  final blobs = <String, Uint8List>{};
  final sidecars = <String, CapabilityManifest>{};
  for (final artifact
      in artifactsByRole[SurfacePublicationArtifactRole.screenBlob] ??
          const <SurfacePublicationArtifact>[]) {
    blobs[artifact.id!] = bytesByPath[artifact.path]!;
  }
  for (final artifact
      in artifactsByRole[SurfacePublicationArtifactRole.capabilitySidecar] ??
          const <SurfacePublicationArtifact>[]) {
    final manifest = _decodeStrictSidecar(
      bytesByPath[artifact.path]!,
      path: artifact.path,
    );
    final blob = blobs[artifact.id!];
    if (blob == null ||
        manifest.blobSha256 != CapabilitySidecar.hashBlob(blob)) {
      throw FormatException(
        'Capability sidecar "${artifact.path}" does not match its blob.',
      );
    }
    sidecars[artifact.id!] = manifest.manifest;
  }
  FlowDocument? flowDocument;
  final flowArtifacts =
      artifactsByRole[SurfacePublicationArtifactRole.flowDocument];
  if (flowArtifacts != null) {
    final artifact = flowArtifacts.single;
    try {
      flowDocument = FlowDocumentCodec.decodeJson(
        utf8.decode(bytesByPath[artifact.path]!),
      );
    } on Object catch (error) {
      throw FormatException(
          'Invalid flow document artifact "${artifact.path}": $error');
    }
    if (flowDocument.flow != entry.publication.slug ||
        flowDocument.deliveryMode != entry.publication.deliveryMode) {
      throw const FormatException(
        'Flow document does not match its publication identity or deliveryMode.',
      );
    }
    final expectedIds = flowDocument.screenArtifacts.keys.toSet();
    if (expectedIds.length != blobs.length ||
        !expectedIds.containsAll(blobs.keys)) {
      throw const FormatException(
        'Flow artifact closure does not match the flow screen artifacts.',
      );
    }
    for (final id in expectedIds) {
      // FlowDocument paths address assembled-payload entries, while manifest
      // paths address package-local source artifacts. The unique id and exact
      // content hash form the cross-namespace closure binding.
      final expectedHash = flowDocument.screenArtifacts[id]!.contentHash.value;
      if (CapabilitySidecar.hashBlob(blobs[id]!) != expectedHash) {
        throw FormatException(
            'Flow screen artifact "$id" has a hash mismatch.');
      }
    }
  }
  if (entry.publication.sourceKind == SurfaceSourceKind.screen) {
    final sidecar = sidecars[entry.publication.slug];
    if (sidecar == null ||
        !SurfaceContractJson.requirementsEqual(
          sidecar,
          entry.publication.capabilities!,
        )) {
      throw const FormatException(
        'Screen publication capabilities do not match its sidecar.',
      );
    }
  }
  return SurfacePublicationArtifactClosure._(
    publication: entry.publication,
    screenBlobs: <String, Uint8List>{
      for (final entry in blobs.entries)
        entry.key: Uint8List.fromList(entry.value),
    },
    sidecarCapabilities: sidecars,
    flowDocument: flowDocument,
    iconFonts: <DeliveredIconFont>[
      for (final artifact
          in artifactsByRole[SurfacePublicationArtifactRole.iconFont] ??
              const <SurfacePublicationArtifact>[])
        decodeIconFontArtifact(artifact.id!, bytesByPath[artifact.path]!),
    ],
    localSeeds: switch (
        artifactsByRole[SurfacePublicationArtifactRole.localSeeds]) {
      [final artifact] => decodeLocalSeedsArtifact(bytesByPath[artifact.path]!),
      _ => const <String, Map<String, Object>>{},
    },
  );
}

bool _sameIconFonts(
  List<DeliveredIconFont> declared,
  List<DeliveredIconFont> assembled,
) =>
    declared.length == assembled.length &&
    declared.toSet().containsAll(assembled);

bool _sameLocalSeeds(
  Map<String, Map<String, Object>> declared,
  Map<String, Map<String, Object>> assembled,
) {
  if (declared.length != assembled.length) return false;
  for (final MapEntry(key: id, value: values) in declared.entries) {
    final other = assembled[id];
    if (other == null || other.length != values.length) return false;
    for (final MapEntry(:key, :value) in values.entries) {
      if (other[key] != value) return false;
    }
  }
  return true;
}

CapabilitySidecar _decodeStrictSidecar(Uint8List bytes,
    {required String path}) {
  final value = SurfaceContractJson.decode(
    utf8.decode(bytes),
    label: 'capability sidecar "$path"',
  );
  final json = SurfaceContractJson.requireObject(value, path);
  SurfaceContractJson.exactKeys(json, const {'blobSha256', 'manifest'}, path);
  final blobSha256 = SurfaceContractJson.requireSha256(
    SurfaceContractJson.requiredString(json, 'blobSha256', path),
    '$path.blobSha256',
  );
  return CapabilitySidecar(
    blobSha256: blobSha256,
    manifest: SurfaceContractJson.decodeCapabilityManifest(
      SurfaceContractJson.requiredValue(json, 'manifest', path),
      path: '$path.manifest',
    ),
  );
}

SurfacePayload _decodeCanonicalPayload(List<int> payloadBytes) {
  final payload = SurfacePayload.decode(payloadBytes);
  if (!SurfaceContractJson.bytesEqual(payload.canonicalBytes, payloadBytes)) {
    throw const FormatException(
        'Payload bytes are not a canonical payload frame.');
  }
  return payload;
}

CapabilityManifest _canonicalManifest(CapabilityManifest source) {
  final encoded = SurfaceContractJson.encodeCapabilityManifest(
    source,
    path: 'capabilities',
  );
  return SurfaceContractJson.decodeCapabilityManifest(
    encoded,
    path: 'capabilities',
  );
}

/// The least capability manifest that satisfies every one of [manifests].
CapabilityManifest capabilityManifestUnion(
    Iterable<CapabilityManifest> manifests) {
  var builtInFloor = 1;
  final versions = <String, int>{};
  for (final manifest in manifests) {
    if (manifest.builtInFloor > builtInFloor) {
      builtInFloor = manifest.builtInFloor;
    }
    for (final requirement in manifest.requiredLibraries) {
      final existing = versions[requirement.namespace];
      if (existing == null || requirement.minVersion > existing) {
        versions[requirement.namespace] = requirement.minVersion;
      }
    }
  }
  final requirements = SurfaceContractJson.canonicalRequirements(
    <LibraryRequirement>[
      for (final entry in versions.entries)
        LibraryRequirement(namespace: entry.key, minVersion: entry.value),
    ],
    path: 'sidecar requirements',
  );
  return CapabilityManifest(
    builtInFloor: builtInFloor,
    requiredLibraries: requirements,
  );
}

bool _sameRequirements(
  List<LibraryRequirement> left,
  List<LibraryRequirement> right,
) {
  final leftCanonical = SurfaceContractJson.canonicalRequirements(
    left,
    path: 'left requirements',
  );
  final rightCanonical = SurfaceContractJson.canonicalRequirements(
    right,
    path: 'right requirements',
  );
  if (leftCanonical.length != rightCanonical.length) return false;
  for (var index = 0; index < leftCanonical.length; index += 1) {
    if (leftCanonical[index] != rightCanonical[index]) return false;
  }
  return true;
}

// Enforces the shared supported policy revisions carrier bound.
String? _boundedSupportedPolicyRevisions(String? value) {
  if (value == null) return null;
  if (value.length > sdkSupportedPolicyRevisionsMaximumCarrierCharacters) {
    throw FormatException(
      r'Expected "$.sdkSupportedPolicyRevisions" to be at most '
      '$sdkSupportedPolicyRevisionsMaximumCarrierCharacters characters.',
    );
  }
  return value;
}

void _requirePackageRelativePath(String value, String path) {
  _requireIdentity(value, path);
  if (!isPackageRelativePath(value)) {
    throw FormatException(
        'Expected "$path" to be a package-relative path with canonical '
        'segments.');
  }
}

void _requireIdentity(String? value, String path) {
  if (value == null ||
      value.isEmpty ||
      value.trim() != value ||
      value.contains('\u0000')) {
    throw FormatException(
        'Expected "$path" to be nonempty, trimmed, and NUL-free.');
  }
  SurfaceContractJson.requireUnicodeScalars(value, path);
}

void _requireSchemaVersion(Map<String, Object?> json, String label) {
  final version = SurfaceContractJson.requiredInt(json, 'schemaVersion', r'$');
  if (version != _surfacePublicationSchemaVersion) {
    throw FormatException('Unsupported $label schemaVersion $version.');
  }
}

/// Whether [first] and [second] encode to the same canonical JSON.
bool sameCanonicalJson(Object? first, Object? second) =>
    SurfaceContractJson.bytesEqual(
        CanonicalJsonCodec.encode(first), CanonicalJsonCodec.encode(second));

Map<String, List<int>> _decodeUploadArtifactBytes(Map<String, Object?> json) {
  if (!json.containsKey('declaredArtifactClosure')) return const {};
  final raw = SurfaceContractJson.requireList(
      json['declaredArtifactClosure'], r'$.declaredArtifactClosure');
  if (raw.length > SurfacePublicationUploadRequest.maxArtifactCount) {
    throw const FormatException('Too many declared publication artifacts.');
  }
  final bytes = <String, List<int>>{};
  var byteLength = 0;
  for (final value in raw) {
    final item =
        SurfaceContractJson.requireObject(value, r'$.declaredArtifactClosure');
    SurfaceContractJson.exactKeys(
        item, const {'path', 'bytes'}, r'$.declaredArtifactClosure');
    final path = SurfaceContractJson.requiredString(
        item, 'path', r'$.declaredArtifactClosure');
    if (bytes.containsKey(path))
      throw const FormatException('Duplicate declared artifact path.');
    final encoded = SurfaceContractJson.requiredString(
        item, 'bytes', r'$.declaredArtifactClosure');
    if (encoded.length >
        SurfacePublicationUploadRequest.maxArtifactBytes * 4 ~/ 3 + 4) {
      throw const FormatException('Declared artifact exceeds the byte limit.');
    }
    final decoded = SurfaceContractJson.decodeCanonicalBase64Url(
        encoded, r'$.declaredArtifactClosure.bytes');
    byteLength += decoded.length;
    if (byteLength > SurfacePublicationUploadRequest.maxArtifactBytes) {
      throw const FormatException('Declared artifacts exceed the byte limit.');
    }
    bytes[path] = decoded;
  }
  return bytes;
}

/// What a [SurfaceScreenContractGap] names.
enum SurfaceScreenContractGapKind {
  /// An emitted event.
  event,

  /// One argument of an emitted event.
  argument,

  /// A `data.context` read.
  context,
}

/// One event, event argument or context read that a screen uses and its
/// contract does not declare.
@immutable
final class SurfaceScreenContractGap
    implements Comparable<SurfaceScreenContractGap> {
  /// An event the contract does not declare.
  const SurfaceScreenContractGap.event(String this.event)
      : kind = SurfaceScreenContractGapKind.event,
        argument = null,
        contextPath = null;

  /// An argument of [event] the contract does not declare with that value.
  const SurfaceScreenContractGap.argument(
    String this.event,
    String this.argument,
  )   : kind = SurfaceScreenContractGapKind.argument,
        contextPath = null;

  /// A context read; [contextPath] is the dotted path below `context`.
  const SurfaceScreenContractGap.context(String this.contextPath)
      : kind = SurfaceScreenContractGapKind.context,
        event = null,
        argument = null;

  /// What this gap names.
  final SurfaceScreenContractGapKind kind;

  /// The event, for an event or argument gap.
  final String? event;

  /// The argument name, for an argument gap.
  final String? argument;

  /// The dotted path below `context`, for a context gap.
  final String? contextPath;

  @override
  int compareTo(SurfaceScreenContractGap other) {
    if (kind != other.kind) return kind.index.compareTo(other.kind.index);
    final byName = SurfaceContractJson.compareUtf8(
      event ?? contextPath!,
      other.event ?? other.contextPath!,
    );
    if (byName != 0) return byName;
    return SurfaceContractJson.compareUtf8(
      argument ?? '',
      other.argument ?? '',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SurfaceScreenContractGap &&
      other.kind == kind &&
      other.event == event &&
      other.argument == argument &&
      other.contextPath == contextPath;

  @override
  int get hashCode => Object.hash(kind, event, argument, contextPath);

  @override
  String toString() => switch (kind) {
        SurfaceScreenContractGapKind.event => 'event "$event"',
        SurfaceScreenContractGapKind.argument =>
          'argument "$argument" of event "$event"',
        SurfaceScreenContractGapKind.context => 'context read "$contextPath"',
      };
}

/// One event a flow screen emits that the state showing it does not handle.
@immutable
final class FlowScreenEventGap implements Comparable<FlowScreenEventGap> {
  const FlowScreenEventGap({
    required this.state,
    required this.screen,
    required this.event,
  });

  /// The state showing the screen.
  final String state;

  /// The screen identifier.
  final String screen;

  /// The emitted event name.
  final String event;

  @override
  int compareTo(FlowScreenEventGap other) {
    final byScreen = SurfaceContractJson.compareUtf8(screen, other.screen);
    if (byScreen != 0) return byScreen;
    final byState = SurfaceContractJson.compareUtf8(state, other.state);
    if (byState != 0) return byState;
    return SurfaceContractJson.compareUtf8(event, other.event);
  }

  @override
  bool operator ==(Object other) =>
      other is FlowScreenEventGap &&
      other.state == state &&
      other.screen == screen &&
      other.event == event;

  @override
  int get hashCode => Object.hash(state, screen, event);

  @override
  String toString() => 'event "$event" on screen "$screen" in state "$state"';
}

/// Every event a screen of [payload] emits that the state showing it does not
/// handle, sorted and each listed once.
///
/// A state handles its `on` events; any screen may also emit a declared
/// custom event, `back` and the events outside the screen contract. An event
/// the same screen of [base] already emits is not listed.
List<FlowScreenEventGap> flowScreenEventGaps(
  FlowSurfacePayload payload, {
  SurfacePayload? base,
}) {
  final document = payload.flowDocument;
  final handledEverywhere = {
    ...document.outbound.customEvents.keys,
    _flowBackEventName,
    ...kScreenEventNamesOutsideContract,
  };
  final baseBlobs = base is FlowSurfacePayload
      ? base.screenBlobs
      : const <String, Uint8List>{};
  Set<String> emitted(Uint8List? blob) => blob == null
      ? const <String>{}
      : _emittedEventNames(rfw.decodeLibraryBlob(blob));
  final emittedByScreen = <String, Set<String>>{};
  final existingByScreen = <String, Set<String>>{};
  final gaps = <FlowScreenEventGap>[];
  for (final MapEntry(key: state, value: definition)
      in document.states.entries) {
    if (definition is! ScreenFlowState) continue;
    final screen = definition.screen;
    final existing = existingByScreen[screen] ??= emitted(baseBlobs[screen]);
    for (final event in emittedByScreen[screen] ??=
        emitted(payload.screenBlobs[screen])) {
      if (handledEverywhere.contains(event) ||
          definition.on.containsKey(event) ||
          existing.contains(event)) {
        continue;
      }
      gaps.add(FlowScreenEventGap(state: state, screen: screen, event: event));
    }
  }
  return gaps..sort();
}

/// The refusal of flow [flow] whose screens emit the unhandled [gaps].
String flowScreenEventGapsMessage(
  String flow,
  List<FlowScreenEventGap> gaps,
) {
  final events = <(String, String), List<String>>{};
  for (final gap in [...gaps]..sort()) {
    (events[(gap.screen, gap.state)] ??= []).add('"${gap.event}"');
  }
  final message = StringBuffer(
    'The flow "$flow" does not handle every event its screens emit:\n',
  );
  for (final MapEntry(key: (screen, state), value: names) in events.entries) {
    message.writeln(
      '- the screen "$screen" in the state "$state" emits '
      '${_joinedWithAnd(names)}',
    );
  }
  message.write(
    'Add a transition for each event in that state, or declare it as a '
    'custom event if the app handles it.',
  );
  return message.toString();
}

String _joinedWithAnd(List<String> items) => items.length == 1
    ? items.single
    : '${items.sublist(0, items.length - 1).join(', ')} and ${items.last}';

const String _flowBackEventName = 'back';

/// The names of every event any declaration of [library] emits.
Set<String> _emittedEventNames(rfw.RemoteWidgetLibrary library) {
  final names = <String>{};
  void visit(Object? value) {
    switch (value) {
      case rfw.EventHandler(:final eventName, :final eventArguments):
        names.add(eventName);
        eventArguments.values.forEach(visit);
      case rfw.ConstructorCall(:final arguments):
        arguments.values.forEach(visit);
      case rfw.SetStateHandler(value: final assigned):
        visit(assigned);
      case rfw.WidgetBuilderDeclaration(:final widget):
        visit(widget);
      case rfw.Loop(:final input, :final output):
        visit(input);
        visit(output);
      case rfw.Switch(:final input, :final outputs):
        visit(input);
        outputs.values.forEach(visit);
      case final Map<Object?, Object?> map:
        map.values.forEach(visit);
      case final List<Object?> list:
        list.forEach(visit);
    }
  }

  for (final declaration in library.widgets) {
    visit(declaration.initialState);
    visit(declaration.root);
  }
  return names;
}
