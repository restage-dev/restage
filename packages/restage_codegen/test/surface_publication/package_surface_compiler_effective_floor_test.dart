import 'dart:convert';
import 'dart:typed_data';

import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/src/onboarding/flow_definition_frontend.dart';
import 'package:restage_codegen/src/restage_source_roster.dart';
import 'package:restage_codegen/src/surface_publication/package_surface_compiler.dart';
import 'package:restage_codegen/src/surface_publication/paywall_artifact_adapter.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  late _Fixture fixture;

  setUpAll(() async {
    fixture = await _loadFixture();
  });

  test(
    'flat flow emits effective sidecar floors for ordinary and paywall screens',
    () {
      final scenario = fixture.scenario(
        ordinarySidecarFloor: 3,
        paywallSidecarFloor: 5,
      );
      for (final flow in fixture.flows) {
        final graph = flow.graph!;
        expect(graph.screens['welcome']!.minClient, 1);
        expect(graph.screens['paywall_premium']!.minClient, 1);
      }
      expect(
        scenario.input.roster.declarations
            .where(
              (source) =>
                  source.kind == RestageRosterSourceKind.screen ||
                  source.kind == RestageRosterSourceKind.paywall,
            )
            .map((source) => source.minClient),
        everyElement(1),
      );

      final result = compilePackageSurfacePublications(scenario.input);

      expect(
        result.issues,
        isEmpty,
        reason: result.issues.map((issue) => issue.message).join('\n'),
      );
      final bundle = result.bundle!;
      final generatedPart =
          bundle.generatedParts['lib/authoring.rsflow.g.dart']!;
      for (final flow in fixture.flows) {
        final document = _flowDocument(bundle, flow.id);
        expect(document.minClient, 5);
        expect(document.screenArtifacts['welcome']!.minClient, 3);
        expect(document.screenArtifacts['paywall_premium']!.minClient, 5);
        expect(
          _generatedReferenceFloor(
            generatedPart,
            '${flow.declaration.name}Ref',
          ),
          document.minClient,
          reason: '${flow.delivery.name} reference and document must agree',
        );
      }
      expect(
        generatedPart,
        contains('SurfaceFlowRef<EffectiveFloorTypedResult>'),
      );
      expect(
        generatedPart,
        contains('SurfaceFlowRef<Map<String, Object?>>'),
      );
    },
  );

  test('flat flow keeps exact bytes when sidecar floors are unchanged', () {
    final scenario = fixture.scenario(
      ordinarySidecarFloor: 1,
      paywallSidecarFloor: 1,
    );
    final result = compilePackageSurfacePublications(scenario.input);

    expect(
      result.issues,
      isEmpty,
      reason: result.issues.map((issue) => issue.message).join('\n'),
    );
    for (final flow in fixture.flows) {
      final expected = flow.graph!.toDocument({
        'welcome': ScreenArtifact(
          path: 'welcome.rfw',
          version: 1,
          schemaVersion: 1,
          minClient: 1,
          contentHash: FlowContentHash.compute(scenario.ordinaryBlob),
        ),
        'paywall_premium': ScreenArtifact(
          path: 'paywall_premium.rfw',
          version: 1,
          schemaVersion: 1,
          minClient: 1,
          contentHash: FlowContentHash.compute(scenario.paywallBlob),
        ),
      });
      expect(
        result.bundle!.outputFiles[_flowDocumentPath(flow.id)],
        orderedEquals(FlowDocumentCodec.encodeCanonicalJson(expected)),
        reason: '${flow.delivery.name} equal-floor bytes must not change',
      );
    }
  });

  test('flat flow still rejects an authored roster floor mismatch', () {
    final scenario = fixture.scenario(
      ordinarySidecarFloor: 3,
      paywallSidecarFloor: 5,
      ordinaryRosterFloor: 2,
    );

    final result = compilePackageSurfacePublications(scenario.input);

    expect(result.bundle, isNull);
    expect(
      result.issues.map((issue) => issue.message).join('\n'),
      contains(
        'reference welcome does not match the rendered source ID, version, '
        'or minimum client',
      ),
    );
  });
}

Future<_Fixture> _loadFixture() async {
  const sourceId = 'apps_examples|lib/authoring.dart';
  late _Fixture fixture;
  final result = await testBuilder(
    _ProbeBuilder((library, assetId) async {
      final inspection = await inspectFlowDefinitions(library, assetId);
      expect(
        inspection.issues,
        isEmpty,
        reason: inspection.issues.map((issue) => issue.message).join('\n'),
      );
      fixture = _Fixture(
        library: library,
        flows: inspection.flows,
        welcome: _class(library, 'Welcome'),
        premium: _class(library, 'Premium'),
      );
    }),
    const {sourceId: _source},
    rootPackage: 'apps_examples',
    readerWriter: await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    ),
  );
  expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
  return fixture;
}

final class _Fixture {
  const _Fixture({
    required this.library,
    required this.flows,
    required this.welcome,
    required this.premium,
  });

  final LibraryElement library;
  final List<NormalizedFlowSource> flows;
  final ClassElement welcome;
  final ClassElement premium;

  _Scenario scenario({
    required int ordinarySidecarFloor,
    required int paywallSidecarFloor,
    int ordinaryRosterFloor = 1,
  }) {
    final ordinaryBlob = Uint8List.fromList(utf8.encode('RFW:welcome'));
    final paywallBlob = Uint8List.fromList(utf8.encode('RFW:premium'));
    final standalonePaywallBlob = Uint8List.fromList(
      utf8.encode('RFW:premium:standalone'),
    );
    final paywallFacts = PaywallArtifactAdapter.fromFiles(
      slug: 'premium',
      standaloneBlobPath: '$_paywallRoot/standalone.rfw',
      standaloneCapabilityPath: '$_paywallRoot/standalone.capability.json',
      adapterBlobPath: '$_paywallRoot/screen.rfw',
      adapterCapabilityPath: '$_paywallRoot/screen.capability.json',
      flowDocumentPath: '$_paywallRoot/flow.json',
      files: {
        '$_paywallRoot/standalone.rfw': standalonePaywallBlob,
        '$_paywallRoot/standalone.capability.json': _sidecarBytes(
          standalonePaywallBlob,
          paywallSidecarFloor,
        ),
        '$_paywallRoot/screen.rfw': paywallBlob,
        '$_paywallRoot/screen.capability.json': _sidecarBytes(
          paywallBlob,
          paywallSidecarFloor,
        ),
      },
    );

    return _Scenario(
      input: PackageSurfaceCompilationInput(
        roster: assembleRestageSourceRoster([
          _screenDeclaration(
            library: library,
            declaration: welcome,
            id: 'welcome',
            minClient: ordinaryRosterFloor,
          ),
          _screenDeclaration(
            library: library,
            declaration: premium,
            id: 'premium',
            surface: Surface.paywall,
            kind: RestageRosterSourceKind.paywall,
          ),
          for (final flow in flows) _flowDeclaration(library, flow),
        ]),
        flows: flows,
        renderedSources: [
          CompiledSurfaceArtifact(
            declaration: welcome,
            blob: ordinaryBlob,
            capabilitySidecar: _sidecarBytes(
              ordinaryBlob,
              ordinarySidecarFloor,
            ),
            flowArtifactPath: 'welcome.rfw',
            rfwText: utf8.encode('remote widget welcome'),
          ),
          CompiledSurfaceArtifact.fromPaywallAdapter(
            declaration: premium,
            facts: paywallFacts,
            flowArtifactPath: 'paywall_premium.rfw',
            rfwText: utf8.encode('remote widget premium'),
          ),
        ],
        standaloneScreens: const [],
      ),
      ordinaryBlob: ordinaryBlob,
      paywallBlob: paywallBlob,
    );
  }
}

final class _Scenario {
  const _Scenario({
    required this.input,
    required this.ordinaryBlob,
    required this.paywallBlob,
  });

  final PackageSurfaceCompilationInput input;
  final Uint8List ordinaryBlob;
  final Uint8List paywallBlob;
}

RestageSourceDeclaration _screenDeclaration({
  required LibraryElement library,
  required ClassElement declaration,
  required String id,
  Surface? surface,
  RestageRosterSourceKind kind = RestageRosterSourceKind.screen,
  int minClient = 1,
}) {
  final surfacePath = surface?.wireName ?? 'neutral';
  final root = kind == RestageRosterSourceKind.paywall
      ? _paywallRoot
      : 'assets/restage/generated/$surfacePath/$id';
  return RestageSourceDeclaration.frozen(
    kind: kind,
    libraryIdentity: library.identifier,
    libraryPath: 'lib/authoring.dart',
    declarationIdentity: _identity(declaration),
    sourcePath: 'lib/authoring.dart',
    explicitId: id,
    span: _span,
    identityClaims: [
      RestageIdentityClaim(
        namespace: 'test/${kind.wireName}/$surfacePath',
        key: id,
      ),
    ],
    outputs: [
      if (kind == RestageRosterSourceKind.screen)
        RestageOutputClaim(
          path: 'lib/authoring.rsscreen.g.dart',
          role: 'screen-descriptor',
          builder: 'test',
          ownershipKey: 'library:${library.identifier}',
        ),
      RestageOutputClaim(
        path: '$root/screen.rfwtxt',
        role: 'screen-text',
        builder: 'test',
        ownershipKey: 'publication:$surfacePath/$id',
      ),
      RestageOutputClaim(
        path: '$root/screen.rfw',
        role: kind == RestageRosterSourceKind.paywall
            ? 'flow-screen-blob'
            : 'screen-blob',
        builder: 'test',
        ownershipKey: 'publication:$surfacePath/$id',
      ),
      RestageOutputClaim(
        path: '$root/screen.capability.json',
        role: kind == RestageRosterSourceKind.paywall
            ? 'flow-screen-capability-sidecar'
            : 'capability-sidecar',
        builder: 'test',
        ownershipKey: 'publication:$surfacePath/$id',
      ),
    ],
    surface: surface,
    minClient: minClient,
    isCanonical: true,
  );
}

RestageSourceDeclaration _flowDeclaration(
  LibraryElement library,
  NormalizedFlowSource flow,
) =>
    RestageSourceDeclaration.frozen(
      kind: RestageRosterSourceKind.flow,
      libraryIdentity: library.identifier,
      libraryPath: 'lib/authoring.dart',
      declarationIdentity: flow.declarationIdentity,
      sourcePath: 'lib/authoring.dart',
      explicitId: flow.id,
      span: _span,
      identityClaims: [
        RestageIdentityClaim(
          namespace: 'test/flow/general',
          key: flow.id,
        ),
      ],
      outputs: [
        const RestageOutputClaim(
          path: 'lib/authoring.rsflow.g.dart',
          role: 'flow-descriptor',
          builder: 'test',
          ownershipKey: 'library:authoring',
        ),
        RestageOutputClaim(
          path: _flowDocumentPath(flow.id),
          role: 'flow-document',
          builder: 'test',
          ownershipKey: 'publication:general/${flow.id}',
        ),
      ],
      surface: Surface.general,
      delivery: flow.delivery,
      isCanonical: true,
    );

FlowDocument _flowDocument(
  PackageSurfaceCompilationBundle bundle,
  String flowId,
) =>
    FlowDocumentCodec.decodeJson(
      utf8.decode(bundle.outputFiles[_flowDocumentPath(flowId)]!),
    );

int _generatedReferenceFloor(String generatedPart, String referenceName) {
  final match = RegExp(
    'const ${RegExp.escape(referenceName)} = [\\s\\S]*?'
    'minClient: ([0-9]+),',
  ).firstMatch(generatedPart);
  if (match == null) {
    throw StateError('Generated reference $referenceName was not found.');
  }
  return int.parse(match.group(1)!);
}

ClassElement _class(LibraryElement library, String name) =>
    library.classes.singleWhere((declaration) => declaration.name == name);

String _identity(Element element) =>
    '${element.library!.identifier}#${element.name ?? '<unnamed>'}';

List<int> _sidecarBytes(List<int> blob, int builtInFloor) => utf8.encode(
      jsonEncode(
        CapabilitySidecar(
          blobSha256: CapabilitySidecar.hashBlob(blob),
          manifest: CapabilityManifest(
            builtInFloor: builtInFloor,
            requiredLibraries: const [],
          ),
        ).toJson(),
      ),
    );

const _paywallRoot = 'assets/restage/generated/paywall/premium';
String _flowDocumentPath(String flowId) =>
    'assets/restage/generated/general/$flowId/flow.json';

const _span = RestageSourceSpan(
  path: 'lib/authoring.dart',
  startLine: 1,
  startColumn: 1,
  endLine: 1,
  endColumn: 1,
);

final class _ProbeBuilder implements Builder {
  const _ProbeBuilder(this.onLibrary);

  final Future<void> Function(LibraryElement library, AssetId assetId)
      onLibrary;

  @override
  Map<String, List<String>> get buildExtensions => const {
        '.dart': ['.aggregate_probe'],
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    if (buildStep.inputId.path != 'lib/authoring.dart') return;
    await onLibrary(await buildStep.inputLibrary, buildStep.inputId);
  }
}

const _source = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'authoring.rsscreen.g.dart';
part 'authoring.rsflow.g.dart';

@Screen(id: 'welcome', minClient: 1)
final class Welcome extends StatelessWidget {
  const Welcome({super.key});

  static const continueFlow = SurfaceEvent<void>('continue');

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

@Paywall(id: 'premium')
final class Premium extends StatelessWidget {
  const Premium({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

@FlowGraph(id: 'effective_floor_typed', surface: Surface.general, minClient: 1)
const effectiveFloorTyped = FlowDefinition(
  start: Welcome,
  transitions: [
    Transition(Welcome.continueFlow, to: Premium),
    Transition.complete(PaywallEvents.purchase, from: Premium),
  ],
);

@FlowGraph(
  id: 'effective_floor_general',
  surface: Surface.general,
  minClient: 1,
  delivery: FlowDeliveryMode.general,
)
const effectiveFloorGeneral = FlowDefinition(
  start: Welcome,
  transitions: [
    Transition(Welcome.continueFlow, to: Premium),
    Transition.complete(PaywallEvents.purchase, from: Premium),
  ],
);
''';
