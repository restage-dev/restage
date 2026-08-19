import 'dart:convert';

import 'package:restage_codegen/src/surface_publication/manifest_assembler.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

void main() {
  test('assembles an exact Surface.general standalone manifest', () {
    final result = SurfacePublicationManifestAssembler.assemble([
      _standaloneInput(),
    ]);

    expect(
      result.canonicalJson,
      '{"schemaVersion":1,"publications":[{"artifacts":[{"contentHash":"sha256:039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81","id":"general_notice","path":"assets/restage/generated/general_notice/screen.rfw","role":"screenBlob"},{"contentHash":"sha256:bb3712909c6331779b86e5634d5bb13dff4cc12fd7c7da28a999114498e6d66c","id":"general_notice","path":"assets/restage/generated/general_notice/screen.capability.json","role":"capabilitySidecar"}],"publication":{"capabilities":{"builtInFloor":1,"requiredLibraries":[]},"contractFingerprint":"sha256:5876ace20d49d4af1c24e69867f9de9380688586256e67130f83bf99d0e96a9f","eventContract":{"schemaVersion":1,"events":[]},"eventContractHash":"sha256:de41f956f53085c222576ac5f4c25b26644aa34a3e33830c3b5f04cce6656ab5","payloadContentHash":"sha256:7caa614ebcc1800fb0e2aef7f4066c32f6589f6b62d3732901eb1d7d617f923d","payloadKind":"blob","slug":"general_notice","sourceKind":"screen","surface":"general","contractVersion":7}}]}',
    );
    expect(result.canonicalBytes, utf8.encode(result.canonicalJson));
    expect(
      result.manifest.publications.single.publication.surface,
      Surface.general,
    );
    expect(
      result.manifest.publications.single.publication.sourceKind,
      SurfaceSourceKind.screen,
    );
  });

  test('assembles an exact Surface.general flow closure', () {
    final result = SurfacePublicationManifestAssembler.assemble([
      _flowInput(),
    ]);

    expect(
      result.manifest.publications.single.publication.surface,
      Surface.general,
    );
    expect(
      result.manifest.publications.single.publication.payloadKind,
      SurfacePayloadKind.flow,
    );
    expect(
      result.manifest.publications.single.artifacts
          .map((artifact) => artifact.role),
      [
        SurfacePublicationArtifactRoleV1.flowDocument,
        SurfacePublicationArtifactRoleV1.screenBlob,
        SurfacePublicationArtifactRoleV1.capabilitySidecar,
      ],
    );
    expect(
      result.canonicalJson,
      '{"schemaVersion":1,"publications":[{"artifacts":[{"contentHash":"sha256:87bbf666729f6f67f64740e9a7f124bca35fbf7934cb59792441beb147c4fb1e","path":"assets/restage/generated/general_flow/flow.json","role":"flowDocument"},{"contentHash":"sha256:06df4f7e1394f1c57cc6583fba4d8060a5a66f4f4771c14aeff6b9af8a28c9b3","id":"general_notice","path":"assets/restage/generated/general_flow/general_notice.rfw","role":"screenBlob"},{"contentHash":"sha256:d1cc0a16f2bdb062edaa4d9e88a43aff529c397eb12e78fd7c999bc2f27fdb17","id":"general_notice","path":"assets/restage/generated/general_flow/general_notice.capability.json","role":"capabilitySidecar"}],"publication":{"deliveryMode":"general","payloadContentHash":"sha256:03ab3d717757f3776fdaa0d8d355a17cce248af2570f4944100db0b8a46fbe5c","payloadKind":"flow","slug":"general_flow","sourceKind":"flowGraph","surface":"general"}}]}',
    );
  });

  test('closes paywall blob and navigation-flow publications', () {
    final blobResult = SurfacePublicationManifestAssembler.assemble([
      _paywallBlobInput(),
    ]);
    expect(
      blobResult.manifest.publications.single.publication.sourceKind,
      SurfaceSourceKind.paywall,
    );

    final flowResult = SurfacePublicationManifestAssembler.assemble([
      _paywallFlowInput(),
    ]);
    final publication = flowResult.manifest.publications.single.publication;
    expect(publication.surface, Surface.paywall);
    expect(publication.sourceKind, SurfaceSourceKind.paywall);
    expect(publication.payloadKind, SurfacePayloadKind.flow);
    expect(
      flowResult.manifest.publications.single.artifacts,
      hasLength(3),
    );
  });

  test('allows an embedded paywall artifact in a non-paywall flow', () {
    final result = SurfacePublicationManifestAssembler.assemble([
      _flowInput(
        surface: Surface.onboarding,
        screenId: 'paywall_premium',
        slug: 'first_run',
        flowPath: 'assets/restage/generated/first_run/flow.json',
        blobPath: 'assets/restage/generated/first_run/paywall_premium.rfw',
        sidecarPath:
            'assets/restage/generated/first_run/paywall_premium.capability.json',
        blobBytes: const <int>[4, 5, 6],
      ),
    ]);

    final publication = result.manifest.publications.single.publication;
    expect(publication.surface, Surface.onboarding);
    expect(publication.sourceKind, SurfaceSourceKind.flowGraph);
    expect(publication.payloadKind, SurfacePayloadKind.flow);
  });

  test('rejects duplicate, traversal, orphan, stale, and mutated artifacts',
      () {
    final valid = _standaloneInput();
    final blob = valid.artifacts.first;
    final sidecar = valid.artifacts.last;

    expect(
      () => SurfacePublicationManifestAssembler.assemble([valid, valid]),
      throwsFormatException,
    );
    expect(
      () => SurfacePublicationManifestAssembler.assemble([
        SurfacePublicationAssemblyInput(
          surface: valid.surface,
          slug: valid.slug,
          sourceKind: valid.sourceKind,
          payloadKind: valid.payloadKind,
          screenContractFacts: valid.screenContractFacts,
          artifacts: [blob, blob, sidecar],
        ),
      ]),
      throwsFormatException,
    );
    expect(
      () => SurfacePublicationManifestAssembler.assemble([
        SurfacePublicationAssemblyInput(
          surface: valid.surface,
          slug: valid.slug,
          sourceKind: valid.sourceKind,
          payloadKind: valid.payloadKind,
          screenContractFacts: valid.screenContractFacts,
          artifacts: [
            SurfacePublicationArtifactInput(
              path: '../outside.rfw',
              role: SurfacePublicationArtifactRoleV1.screenBlob,
              id: valid.slug,
              bytes: blob.bytes,
            ),
            sidecar,
          ],
        ),
      ]),
      throwsFormatException,
    );
    expect(
      () => SurfacePublicationManifestAssembler.assemble([
        SurfacePublicationAssemblyInput(
          surface: valid.surface,
          slug: valid.slug,
          sourceKind: valid.sourceKind,
          payloadKind: valid.payloadKind,
          screenContractFacts: valid.screenContractFacts,
          artifacts: [sidecar],
        ),
      ]),
      throwsFormatException,
    );
    expect(
      () => SurfacePublicationManifestAssembler.assemble([
        SurfacePublicationAssemblyInput(
          surface: valid.surface,
          slug: valid.slug,
          sourceKind: valid.sourceKind,
          payloadKind: valid.payloadKind,
          screenContractFacts: valid.screenContractFacts,
          artifacts: [
            blob,
            SurfacePublicationArtifactInput(
              path: sidecar.path,
              role: sidecar.role,
              id: sidecar.id,
              bytes: _sidecarBytes(
                const <int>[9, 9, 9],
                _emptyCapabilities,
              ),
            ),
          ],
        ),
      ]),
      throwsFormatException,
    );

    final flow = _flowInput();
    final flowBlob = flow.artifacts.singleWhere(
      (artifact) =>
          artifact.role == SurfacePublicationArtifactRoleV1.screenBlob,
    );
    expect(
      () => SurfacePublicationManifestAssembler.assemble([
        SurfacePublicationAssemblyInput(
          surface: flow.surface,
          slug: flow.slug,
          sourceKind: flow.sourceKind,
          payloadKind: flow.payloadKind,
          flowFacts: flow.flowFacts,
          artifacts: [
            for (final artifact in flow.artifacts)
              artifact == flowBlob
                  ? SurfacePublicationArtifactInput(
                      path: artifact.path,
                      role: artifact.role,
                      id: artifact.id,
                      bytes: const <int>[1, 1, 1],
                    )
                  : artifact,
          ],
        ),
      ]),
      throwsFormatException,
    );
  });

  test('allows only exact cross-entry artifact reuse', () {
    final standalone = _standaloneInput(
      slug: 'flow_screen',
      blobPath: 'assets/restage/shared/flow_screen.rfw',
      sidecarPath: 'assets/restage/shared/flow_screen.capability.json',
      blobBytes: const <int>[9, 8, 7],
      capabilities: _flowCapabilities,
    );
    final sharedFlow = _flowInput(
      screenId: 'flow_screen',
      slug: 'flow',
      blobPath: standalone.artifacts.first.path,
      sidecarPath: standalone.artifacts.last.path,
    );

    final result = SurfacePublicationManifestAssembler.assemble([
      standalone,
      sharedFlow,
    ]);
    expect(result.manifest.publications, hasLength(2));

    final mutated = _standaloneInput(
      slug: 'flow_screen',
      blobPath: standalone.artifacts.first.path,
      sidecarPath: standalone.artifacts.last.path,
      blobBytes: const <int>[9, 8, 6],
      capabilities: _flowCapabilities,
    );
    expect(
      () => SurfacePublicationManifestAssembler.assemble([
        sharedFlow,
        mutated,
      ]),
      throwsFormatException,
    );
  });

  test('is invariant under input and artifact ordering', () {
    final standalone = _standaloneInput(
      slug: 'order_notice',
      blobPath: 'assets/restage/shared/order_notice.rfw',
      sidecarPath: 'assets/restage/shared/order_notice.capability.json',
      capabilities: _flowCapabilities,
    );
    final flow = _flowInput(
      screenId: 'order_notice',
      slug: 'order_flow',
      blobPath: standalone.artifacts.first.path,
      sidecarPath: standalone.artifacts.last.path,
      blobBytes: const <int>[1, 2, 3],
    );
    final reversedStandalone = SurfacePublicationAssemblyInput(
      surface: standalone.surface,
      slug: standalone.slug,
      sourceKind: standalone.sourceKind,
      payloadKind: standalone.payloadKind,
      screenContractFacts: standalone.screenContractFacts,
      artifacts: standalone.artifacts.reversed,
    );
    final reversedFlow = SurfacePublicationAssemblyInput(
      surface: flow.surface,
      slug: flow.slug,
      sourceKind: flow.sourceKind,
      payloadKind: flow.payloadKind,
      flowFacts: flow.flowFacts,
      artifacts: flow.artifacts.reversed,
    );

    final first = SurfacePublicationManifestAssembler.assemble([
      standalone,
      flow,
    ]);
    final second = SurfacePublicationManifestAssembler.assemble([
      reversedFlow,
      reversedStandalone,
    ]);
    expect(second.canonicalBytes, first.canonicalBytes);
  });

  test(
      'accepts an authored flow-screen floor above its derived sidecar floor '
      'when the flow covers it', () {
    expect(
      () => SurfacePublicationManifestAssembler.assemble([
        _flowInput(
          flowMinClient: 3,
          screenMinClient: 3,
        ),
      ]),
      returnsNormally,
    );

    expect(
      () => SurfacePublicationManifestAssembler.assemble([
        _flowInput(
          screenMinClient: 3,
        ),
      ]),
      throwsFormatException,
    );

    expect(
      () => SurfacePublicationManifestAssembler.assemble([
        _flowInput(
          flowMinClient: 3,
          sidecarCapabilities: CapabilityManifest(
            builtInFloor: 3,
            requiredLibraries: _flowCapabilities.requiredLibraries,
          ),
        ),
      ]),
      throwsFormatException,
    );
  });
}

final _emptyCapabilities = CapabilityManifest(
  builtInFloor: 1,
  requiredLibraries: const <LibraryRequirement>[],
);

final _flowCapabilities = CapabilityManifest(
  builtInFloor: 1,
  requiredLibraries: const <LibraryRequirement>[
    LibraryRequirement(namespace: 'acme.widgets', minVersion: 2),
  ],
);

SurfacePublicationAssemblyInput _standaloneInput({
  String slug = 'general_notice',
  String blobPath = 'assets/restage/generated/general_notice/screen.rfw',
  String sidecarPath =
      'assets/restage/generated/general_notice/screen.capability.json',
  List<int> blobBytes = const <int>[1, 2, 3],
  CapabilityManifest? capabilities,
}) {
  final effectiveCapabilities = capabilities ?? _emptyCapabilities;
  return SurfacePublicationAssemblyInput(
    surface: Surface.general,
    slug: slug,
    sourceKind: SurfaceSourceKind.screen,
    payloadKind: SurfacePayloadKind.blob,
    screenContractFacts: SurfacePublicationScreenContractFacts(
      contractVersion: 7,
      capabilities: effectiveCapabilities,
      eventContract: SurfaceScreenEventSchemaV1(events: const []),
    ),
    artifacts: [
      SurfacePublicationArtifactInput(
        path: blobPath,
        role: SurfacePublicationArtifactRoleV1.screenBlob,
        id: slug,
        bytes: blobBytes,
      ),
      SurfacePublicationArtifactInput(
        path: sidecarPath,
        role: SurfacePublicationArtifactRoleV1.capabilitySidecar,
        id: slug,
        bytes: _sidecarBytes(blobBytes, effectiveCapabilities),
      ),
    ],
  );
}

SurfacePublicationAssemblyInput _paywallBlobInput() {
  const blob = <int>[4, 5, 6];
  return SurfacePublicationAssemblyInput(
    surface: Surface.paywall,
    slug: 'premium',
    sourceKind: SurfaceSourceKind.paywall,
    payloadKind: SurfacePayloadKind.blob,
    artifacts: [
      SurfacePublicationArtifactInput(
        path: 'assets/paywalls/premium.rfw',
        role: SurfacePublicationArtifactRoleV1.screenBlob,
        id: 'premium',
        bytes: blob,
      ),
      SurfacePublicationArtifactInput(
        path: 'assets/paywalls/premium.capability.json',
        role: SurfacePublicationArtifactRoleV1.capabilitySidecar,
        id: 'premium',
        bytes: _sidecarBytes(blob, _emptyCapabilities),
      ),
    ],
  );
}

SurfacePublicationAssemblyInput _paywallFlowInput() => _flowInput(
      surface: Surface.paywall,
      sourceKind: SurfaceSourceKind.paywall,
      slug: 'premium',
      screenId: 'paywall_premium',
      flowPath: 'assets/paywalls/premium.flow.json',
      blobPath: 'assets/paywalls/screens/paywall_premium.rfw',
      sidecarPath: 'assets/paywalls/screens/paywall_premium.capability.json',
      blobBytes: const <int>[4, 5, 6],
    );

SurfacePublicationAssemblyInput _flowInput({
  Surface surface = Surface.general,
  SurfaceSourceKind sourceKind = SurfaceSourceKind.flowGraph,
  String slug = 'general_flow',
  String screenId = 'general_notice',
  String flowPath = 'assets/restage/generated/general_flow/flow.json',
  String blobPath = 'assets/restage/generated/general_flow/general_notice.rfw',
  String sidecarPath =
      'assets/restage/generated/general_flow/general_notice.capability.json',
  List<int> blobBytes = const <int>[9, 8, 7],
  int flowMinClient = 1,
  int screenMinClient = 1,
  CapabilityManifest? sidecarCapabilities,
}) {
  final effectiveSidecarCapabilities = sidecarCapabilities ?? _flowCapabilities;
  final document = FlowDocument(
    flow: slug,
    version: 1,
    schemaVersion: 1,
    minClient: flowMinClient,
    initial: screenId,
    screenArtifacts: {
      screenId: ScreenArtifact(
        path: '$screenId.rfw',
        version: 1,
        schemaVersion: 1,
        minClient: screenMinClient,
        contentHash: FlowContentHash.compute(blobBytes),
      ),
    },
    states: {
      screenId: ScreenFlowState(
        screen: screenId,
        on: {'finish': const FlowTransition.goto('done')},
      ),
      'done': const EndFlowState(result: {}),
    },
    deliveryMode: FlowDeliveryMode.general,
  );
  final flowBytes = utf8.encode(FlowDocumentCodec.encodePrettyJson(document));
  return SurfacePublicationAssemblyInput(
    surface: surface,
    slug: slug,
    sourceKind: sourceKind,
    payloadKind: SurfacePayloadKind.flow,
    flowFacts: const SurfacePublicationFlowFacts(
      deliveryMode: FlowDeliveryMode.general,
    ),
    artifacts: [
      SurfacePublicationArtifactInput(
        path: flowPath,
        role: SurfacePublicationArtifactRoleV1.flowDocument,
        bytes: flowBytes,
      ),
      SurfacePublicationArtifactInput(
        path: blobPath,
        role: SurfacePublicationArtifactRoleV1.screenBlob,
        id: screenId,
        bytes: blobBytes,
      ),
      SurfacePublicationArtifactInput(
        path: sidecarPath,
        role: SurfacePublicationArtifactRoleV1.capabilitySidecar,
        id: screenId,
        bytes: _sidecarBytes(blobBytes, effectiveSidecarCapabilities),
      ),
    ],
  );
}

List<int> _sidecarBytes(
  List<int> blob,
  CapabilityManifest capabilities,
) =>
    utf8.encode(
      jsonEncode(
        CapabilitySidecar(
          blobSha256: CapabilitySidecar.hashBlob(blob),
          manifest: capabilities,
        ).toJson(),
      ),
    );
