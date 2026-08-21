import 'package:flutter/services.dart' show AssetBundle;
import 'package:meta/meta.dart';
import 'package:restage_shared/restage_shared.dart';

import '../flow/bundled_flow_loader.dart';
import '../flow/flow_descriptors.dart';
import '../flow/flow_experiment_artifact_metadata.dart';
import '../flow/flow_resolver.dart';
import '../measurement/bundled_measurement_publication_binding_read_port.dart';
import '../measurement/measurement_bundled_generated_source_provenance.dart';
import '../runtime/builtin_catalog_capabilities.dart';

@internal
sealed class AssetPaywallFlowPreflightOutcome {
  const AssetPaywallFlowPreflightOutcome();
}

@internal
final class AssetPaywallFlowBaseline extends AssetPaywallFlowPreflightOutcome
    implements FlowResolver, FlowExperimentArtifactMetadataProvider {
  factory AssetPaywallFlowBaseline._({
    required ResolvedFlow root,
    required Map<String, ResolvedFlow> flows,
  }) {
    final baseline = AssetPaywallFlowBaseline._owned(
      root: root,
      flows: Map<String, ResolvedFlow>.unmodifiable(flows),
    );
    for (final flow in flows.values) {
      FlowExperimentArtifactOwnership.attach(
        owner: baseline,
        flow: flow,
        metadata: FlowExperimentArtifactOwnership.verifiedMetadata(
          requiredLibraries: const <LibraryRequirement>[],
        ),
      );
    }
    return baseline;
  }

  const AssetPaywallFlowBaseline._owned({
    required this.root,
    required Map<String, ResolvedFlow> flows,
  }) : _flows = flows;

  final ResolvedFlow root;
  final Map<String, ResolvedFlow> _flows;

  @override
  Future<ResolvedFlow> resolve<R>(OnboardingFlowRef<R> flow) async {
    final resolved = flow.surfaceType == Surface.paywall
        ? _flows[_assetFlowIdentity(flow.id, flow.version)]
        : null;
    if (resolved == null) {
      throw FlowUnavailableError(
        flowId: flow.id,
        flowVersion: flow.version,
        reason: 'not_preflighted',
        message: 'Paywall flow "${flow.id}" version ${flow.version} was not '
            'frozen by this baseline preflight.',
      );
    }
    return resolved;
  }

  @override
  FlowExperimentArtifactMetadata metadataFor(ResolvedFlow flow) =>
      FlowExperimentArtifactOwnership.metadataFor(owner: this, flow: flow);
}

@internal
final class AssetPaywallFlowBaselineAbsent
    extends AssetPaywallFlowPreflightOutcome {
  const AssetPaywallFlowBaselineAbsent();
}

@internal
final class AssetPaywallFlowBaselineRejected
    extends AssetPaywallFlowPreflightOutcome {
  const AssetPaywallFlowBaselineRejected();
}

@internal
Future<AssetPaywallFlowPreflightOutcome> preflightAssetPaywallFlowBaseline({
  required AssetBundle bundle,
  required String assetPathPrefix,
  required String paywallId,
}) async {
  final loader = _AssetPaywallFlowPreflightLoader(
    bundle: bundle,
    assetPathPrefix: assetPathPrefix,
  );
  try {
    final root = await loader.loadRoot(paywallId);
    return AssetPaywallFlowBaseline._(root: root, flows: loader.flows);
  } on _AssetPaywallFlowPreflightError catch (error) {
    return error.missingRoot
        ? const AssetPaywallFlowBaselineAbsent()
        : const AssetPaywallFlowBaselineRejected();
  } on Object {
    return const AssetPaywallFlowBaselineRejected();
  }
}

final class _AssetPaywallFlowPreflightLoader {
  _AssetPaywallFlowPreflightLoader({
    required this.bundle,
    required this.assetPathPrefix,
  });

  final AssetBundle bundle;
  final String assetPathPrefix;
  final Map<String, ResolvedFlow> flows = <String, ResolvedFlow>{};

  Future<ResolvedFlow> loadRoot(String paywallId) {
    return _load(
      flowId: paywallId,
      depth: 0,
      path: const <String>{},
      root: true,
    );
  }

  Future<ResolvedFlow> _load({
    required String flowId,
    required int depth,
    required Set<String> path,
    required bool root,
    int? expectedVersion,
    FlowContentHash? expectedHash,
  }) async {
    if (depth > 4) {
      throw const _AssetPaywallFlowPreflightError('closure_depth');
    }
    if (expectedVersion != null) {
      final expectedIdentity = _assetFlowIdentity(flowId, expectedVersion);
      if (path.contains(expectedIdentity)) {
        throw const _AssetPaywallFlowPreflightError('closure_cycle');
      }
      final existing = flows[expectedIdentity];
      if (existing != null) {
        if (expectedHash != null && existing.contentHash != expectedHash) {
          throw const _AssetPaywallFlowPreflightError('hash_mismatch');
        }
        return existing;
      }
    }
    final artifacts = await loadBundledFlowArtifacts(
      bundle: bundle,
      flowJsonPath: '$assetPathPrefix/$flowId.flow.json',
      screenAssetPathPrefix: kPaywallScreensAssetDir,
      flowId: flowId,
      expectedVersion: expectedVersion,
      supportedMinClient: RestageBuiltInCatalogCapabilities.currentVersion,
      clientDescription: 'supported client',
      buildError: (reason, message, [cause]) => _AssetPaywallFlowPreflightError(
        reason,
        missingRoot: root && reason == 'missing_flow_json',
      ),
    );
    final canonicalHash = FlowContentHash.compute(
      FlowDocumentCodec.encodeCanonicalJson(artifacts.document),
    );
    if (expectedHash != null && canonicalHash != expectedHash) {
      throw const _AssetPaywallFlowPreflightError('hash_mismatch');
    }

    final identity = _assetFlowIdentity(
      artifacts.document.flow,
      artifacts.document.version,
    );
    if (path.contains(identity)) {
      throw const _AssetPaywallFlowPreflightError('closure_cycle');
    }
    final existing = flows[identity];
    if (existing != null) return existing;

    final resolved = attachMeasurementBundledGeneratedArtifactClosureCarrier(
      ResolvedFlow(
        document: artifacts.document,
        screenBlobs: artifacts.screenBlobs,
        contentHash: canonicalHash,
        cacheHit: false,
      ),
      bundledMeasurementGeneratedArtifactClosureForFlowArtifacts(artifacts),
    );
    flows[identity] = resolved;

    final nextPath = <String>{...path, identity};
    for (final state in artifacts.document.states.values) {
      if (state is! SubFlowState) continue;
      await _load(
        flowId: state.flow,
        depth: depth + 1,
        path: nextPath,
        root: false,
        expectedVersion: state.version,
        expectedHash: state.contentHash,
      );
    }
    return resolved;
  }
}

final class _AssetPaywallFlowPreflightError implements Exception {
  const _AssetPaywallFlowPreflightError(
    this.reason, {
    this.missingRoot = false,
  });

  final String reason;
  final bool missingRoot;
}

String _assetFlowIdentity(String flowId, int version) =>
    '${Surface.paywall.wireName}\u0000$flowId\u0000$version';
