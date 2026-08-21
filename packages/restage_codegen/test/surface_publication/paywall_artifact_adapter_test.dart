import 'dart:convert';

import 'package:restage_codegen/src/surface_publication/paywall_artifact_adapter.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

void main() {
  group('PaywallArtifactAdapter', () {
    test('returns standalone and adapter facts with exact hashes', () {
      final standalone = <int>[1, 2, 3];
      final adapter = <int>[4, 5, 6];
      final files = <String, List<int>>{
        'assets/paywalls/premium.rfw': standalone,
        'assets/paywalls/premium.capability.json': _sidecar(standalone),
        'assets/paywalls/screens/paywall_premium.rfw': adapter,
        'assets/paywalls/screens/paywall_premium.capability.json':
            _sidecar(adapter),
      };

      final facts = PaywallArtifactAdapter.fromFiles(
        slug: 'premium',
        standaloneBlobPath: 'assets/paywalls/premium.rfw',
        standaloneCapabilityPath: 'assets/paywalls/premium.capability.json',
        adapterBlobPath: 'assets/paywalls/screens/paywall_premium.rfw',
        adapterCapabilityPath:
            'assets/paywalls/screens/paywall_premium.capability.json',
        flowDocumentPath: 'assets/paywalls/premium.flow.json',
        files: files,
      );

      expect(facts.surface, Surface.paywall);
      expect(facts.sourceKind, SurfaceSourceKind.paywall);
      expect(facts.standalone, isNotNull);
      expect(facts.hasFlow, isFalse);
      expect(
        facts.standalone!.blob.contentHash,
        CapabilitySidecar.hashBlob(standalone),
      );
      expect(facts.adapter.id, 'paywall_premium');
      expect(
        facts.adapter.sidecar.manifest.builtInFloor,
        kBaselineCatalogVersion,
      );
      expect(
        facts.standaloneArtifacts.map((artifact) => artifact.path),
        [
          'assets/paywalls/premium.rfw',
          'assets/paywalls/premium.capability.json',
        ],
      );
    });

    test('returns a complete navigation flow closure without standalone blob',
        () {
      final adapter = <int>[4, 5, 6];
      final document = _flowDocument(adapter);
      const flowPath = 'assets/paywalls/premium.flow.json';
      final files = <String, List<int>>{
        'assets/paywalls/screens/paywall_premium.rfw': adapter,
        'assets/paywalls/screens/paywall_premium.capability.json':
            _sidecar(adapter),
        flowPath: FlowDocumentCodec.encodeCanonicalJson(document),
      };

      final facts = PaywallArtifactAdapter.fromFiles(
        slug: 'premium',
        standaloneBlobPath: 'assets/paywalls/premium.rfw',
        standaloneCapabilityPath: 'assets/paywalls/premium.capability.json',
        adapterBlobPath: 'assets/paywalls/screens/paywall_premium.rfw',
        adapterCapabilityPath:
            'assets/paywalls/screens/paywall_premium.capability.json',
        flowDocumentPath: flowPath,
        files: files,
      );

      expect(facts.standalone, isNull);
      expect(facts.hasFlow, isTrue);
      expect(facts.navigationFlow!.flow, 'premium');
      expect(
        facts.flowDocument!.artifact.role,
        SurfacePublicationArtifactRole.flowDocument,
      );
      expect(facts.flowScreens.keys, ['paywall_premium']);
      expect(
        facts.flowArtifacts.map((artifact) => artifact.role),
        [
          SurfacePublicationArtifactRole.flowDocument,
          SurfacePublicationArtifactRole.screenBlob,
          SurfacePublicationArtifactRole.capabilitySidecar,
        ],
      );
      expect(facts.filesByPath.keys, containsAll(files.keys));
    });

    test('retains an adapter-only pushed paywall for flow composition', () {
      final adapter = <int>[4, 5, 6];
      final facts = PaywallArtifactAdapter.fromFiles(
        slug: 'published_offer',
        standaloneBlobPath: 'assets/paywalls/published_offer.rfw',
        standaloneCapabilityPath:
            'assets/paywalls/published_offer.capability.json',
        adapterBlobPath: 'assets/paywalls/screens/paywall_published_offer.rfw',
        adapterCapabilityPath:
            'assets/paywalls/screens/paywall_published_offer.capability.json',
        flowDocumentPath: 'assets/paywalls/published_offer.flow.json',
        files: {
          'assets/paywalls/screens/paywall_published_offer.rfw': adapter,
          'assets/paywalls/screens/paywall_published_offer.capability.json':
              _sidecar(adapter),
        },
      );

      expect(facts.standalone, isNull);
      expect(facts.hasFlow, isFalse);
      expect(facts.isEmbeddedOnly, isTrue);
      expect(facts.adapter.id, 'paywall_published_offer');
      expect(facts.filesByPath.keys, hasLength(2));
    });

    test('rejects a partial standalone family', () {
      expect(
        () => PaywallArtifactAdapter.fromFiles(
          slug: 'premium',
          standaloneBlobPath: 'assets/paywalls/premium.rfw',
          standaloneCapabilityPath: 'assets/paywalls/premium.capability.json',
          adapterBlobPath: 'assets/paywalls/screens/paywall_premium.rfw',
          adapterCapabilityPath:
              'assets/paywalls/screens/paywall_premium.capability.json',
          flowDocumentPath: 'assets/paywalls/premium.flow.json',
          files: {
            'assets/paywalls/premium.rfw': [1],
            'assets/paywalls/screens/paywall_premium.rfw': [2],
            'assets/paywalls/screens/paywall_premium.capability.json':
                _sidecar([2]),
          },
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects a stale capability sidecar', () {
      expect(
        () => PaywallArtifactAdapter.fromFiles(
          slug: 'premium',
          standaloneBlobPath: 'assets/paywalls/premium.rfw',
          standaloneCapabilityPath: 'assets/paywalls/premium.capability.json',
          adapterBlobPath: 'assets/paywalls/screens/paywall_premium.rfw',
          adapterCapabilityPath:
              'assets/paywalls/screens/paywall_premium.capability.json',
          flowDocumentPath: 'assets/paywalls/premium.flow.json',
          files: {
            'assets/paywalls/premium.rfw': [1],
            'assets/paywalls/premium.capability.json': _sidecar([9]),
            'assets/paywalls/screens/paywall_premium.rfw': [2],
            'assets/paywalls/screens/paywall_premium.capability.json':
                _sidecar([2]),
          },
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });
}

List<int> _sidecar(List<int> blob) => utf8.encode(
      jsonEncode(
        CapabilitySidecar(
          blobSha256: CapabilitySidecar.hashBlob(blob),
          manifest: CapabilityManifest(
            builtInFloor: kBaselineCatalogVersion,
            requiredLibraries: const [],
          ),
        ).toJson(),
      ),
    );

FlowDocument _flowDocument(List<int> blob) {
  return FlowDocument(
    flow: 'premium',
    version: 1,
    schemaVersion: 1,
    minClient: kBaselineCatalogVersion,
    initial: 'paywall_premium',
    screenArtifacts: {
      'paywall_premium': ScreenArtifact(
        path: 'paywall_premium.rfw',
        version: 1,
        schemaVersion: 1,
        minClient: kBaselineCatalogVersion,
        contentHash: FlowContentHash.compute(blob),
      ),
    },
    states: {
      'paywall_premium': const ScreenFlowState(
        screen: 'paywall_premium',
        on: {'skip': FlowTransition.goto('done')},
      ),
      'done': const EndFlowState(result: {}),
    },
  );
}
