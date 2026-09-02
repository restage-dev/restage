import 'dart:convert';

import 'package:restage_shared/src/capability/capability_manifest.dart';
import 'package:restage_shared/src/surface_contract/surface_contract_json.dart';
import 'package:restage_shared/src/surface_document/surface_document.dart';

/// Canonical V1 fingerprint encoder for one immutable screen contract family.
abstract final class SurfaceScreenContractFingerprint {
  static const String _domain = 'restage.surface-screen-contract';

  /// Produces the exact V1 canonical JSON tuple.
  ///
  /// [hostDataContractHash] is omitted entirely when the screen declares no
  /// host-supplied input, so such a screen encodes exactly as it did before
  /// host data entered the contract.
  static String encodeCanonicalJson({
    required SurfaceSourceKind sourceKind,
    required SurfacePayloadKind payloadKind,
    required CapabilityManifest capabilities,
    required String eventContractHash,
    String? hostDataContractHash,
  }) {
    SurfaceContractJson.requireSha256(eventContractHash, 'eventContractHash');
    if (hostDataContractHash != null) {
      SurfaceContractJson.requireSha256(
        hostDataContractHash,
        'hostDataContractHash',
      );
    }
    return SurfaceContractJson.encode(<String, Object?>{
      'schemaVersion': 1,
      'sourceKind': sourceKind.wireName,
      'payloadKind': payloadKind.wireName,
      'capabilities': SurfaceContractJson.encodeCapabilityManifest(
        capabilities,
        path: 'capabilities',
      ),
      'eventContractHash': eventContractHash,
      if (hostDataContractHash != null)
        'hostDataContractHash': hostDataContractHash,
    });
  }

  /// Produces the V1 SHA-256 preimage.
  static List<int> preimage({
    required SurfaceSourceKind sourceKind,
    required SurfacePayloadKind payloadKind,
    required CapabilityManifest capabilities,
    required String eventContractHash,
    String? hostDataContractHash,
  }) =>
      <int>[
        ...ascii.encode(_domain),
        0,
        ...ascii.encode('v1'),
        0,
        ...utf8.encode(
          encodeCanonicalJson(
            sourceKind: sourceKind,
            payloadKind: payloadKind,
            capabilities: capabilities,
            eventContractHash: eventContractHash,
            hostDataContractHash: hostDataContractHash,
          ),
        ),
      ];

  /// Produces the stable `sha256:<64 lowercase hex>` fingerprint.
  static String hash({
    required SurfaceSourceKind sourceKind,
    required SurfacePayloadKind payloadKind,
    required CapabilityManifest capabilities,
    required String eventContractHash,
    String? hostDataContractHash,
  }) =>
      SurfaceContractJson.hash(
        preimage(
          sourceKind: sourceKind,
          payloadKind: payloadKind,
          capabilities: capabilities,
          eventContractHash: eventContractHash,
          hostDataContractHash: hostDataContractHash,
        ),
      );
}
