import 'dart:convert';
import 'dart:typed_data';

import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/src/onboarding/flow_definition_frontend.dart';
import 'package:restage_codegen/src/restage_source_roster.dart';
import 'package:restage_codegen/src/surface_publication/package_surface_compiler.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  test(
    'publishes a flat parent whose subflow targets an advanced class flow',
    () async {
      const sourceId = 'apps_examples|lib/authoring.dart';
      late PackageSurfaceCompilationInput input;
      final result = await testBuilder(
        _ProbeBuilder((library, assetId) async {
          final inspection = await inspectFlowDefinitions(library, assetId);
          expect(
            inspection.issues,
            isEmpty,
            reason: inspection.issues.map((issue) => issue.message).join('\n'),
          );
          input = _inputFor(library, inspection.flows);
        }),
        const {sourceId: _source},
        rootPackage: 'apps_examples',
        readerWriter: await readerWriterWithFilesystemSources(
          rootPackage: 'apps_examples',
        ),
      );

      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
      final compilation = compilePackageSurfacePublications(input);
      expect(
        compilation.issues,
        isEmpty,
        reason: compilation.issues.map((issue) => issue.message).join('\n'),
      );
      final bundle = compilation.bundle;
      expect(bundle, isNotNull);

      final childBytes = input.precompiledFlows.single.flowDocumentBytes;
      final outputFiles = bundle!.outputFiles;
      expect(
        outputFiles[
            'assets/restage/generated/general/advanced_child/flow.json'],
        orderedEquals(childBytes),
        reason:
            'the class-flow publication retains its exact precompiled bytes',
      );

      final parentBytes =
          outputFiles['assets/restage/generated/general/parent/flow.json'];
      expect(parentBytes, isNotNull);
      final parentDocument =
          FlowDocumentCodec.decodeJson(utf8.decode(parentBytes!));
      final childState = parentDocument.states.values.whereType<SubFlowState>();
      expect(childState, hasLength(1));
      expect(childState.single.flow, 'advanced_child');
      expect(childState.single.version, 2);
      expect(childState.single.minClient, 3);
      expect(
        childState.single.contentHash,
        FlowContentHash.compute(childBytes),
      );
      expect(
        bundle.manifest.publications
            .map((entry) => entry.publication.slug)
            .toList(),
        orderedEquals(['advanced_child', 'parent']),
      );
    },
  );
}

PackageSurfaceCompilationInput _inputFor(
  LibraryElement library,
  List<NormalizedFlowSource> flows,
) {
  final child = flows.singleWhere((flow) => flow.id == 'advanced_child');
  final welcome = library.classes.singleWhere(
    (declaration) => declaration.name == 'Welcome',
  );
  final parentDeclaration = library.topLevelVariables.singleWhere(
    (declaration) => declaration.name == 'parent',
  );
  final childDeclaration = library.classes.singleWhere(
    (declaration) => declaration.name == 'AdvancedChild',
  );
  final welcomeBlob = Uint8List.fromList(utf8.encode('RFW:welcome'));
  const childDocument = FlowDocument(
    flow: 'advanced_child',
    version: 2,
    schemaVersion: 1,
    minClient: 3,
    initial: 'done',
    screenArtifacts: {},
    states: {'done': EndFlowState(result: {})},
  );
  final childBytes = Uint8List.fromList(
    utf8.encode(FlowDocumentCodec.encodePrettyJson(childDocument)),
  );

  return PackageSurfaceCompilationInput(
    roster: assembleRestageSourceRoster([
      _screenDeclaration(library, welcome),
      _flowDeclaration(
        library: library,
        declaration: parentDeclaration,
        id: 'parent',
      ),
      _flowDeclaration(
        library: library,
        declaration: childDeclaration,
        id: 'advanced_child',
        version: 2,
        minClient: 3,
      ),
    ]),
    flows: flows,
    renderedSources: [
      CompiledSurfaceArtifact(
        declaration: welcome,
        blob: welcomeBlob,
        capabilitySidecar: _sidecarBytes(welcomeBlob),
        flowArtifactPath: 'welcome.rfw',
        rfwText: utf8.encode('remote widget welcome'),
      ),
    ],
    standaloneScreens: const [],
    precompiledFlows: [
      CompiledFlowArtifact(
        declaration: child.declaration,
        flowDocumentBytes: childBytes,
        generatedPart: 'part of authoring.dart;\n\n'
            'const advancedChildGenerated = true;',
      ),
    ],
  );
}

RestageSourceDeclaration _screenDeclaration(
  LibraryElement library,
  ClassElement declaration,
) =>
    RestageSourceDeclaration.frozen(
      kind: RestageRosterSourceKind.screen,
      libraryIdentity: library.identifier,
      libraryPath: 'lib/authoring.dart',
      declarationIdentity: _identity(declaration),
      sourcePath: 'lib/authoring.dart',
      explicitId: 'welcome',
      span: _span,
      identityClaims: const [
        RestageIdentityClaim(namespace: 'test/screen/neutral', key: 'welcome'),
      ],
      outputs: const [
        RestageOutputClaim(
          path: 'lib/authoring.rsscreen.g.dart',
          role: 'screen-descriptor',
          builder: 'test',
          ownershipKey: 'library:authoring',
        ),
        RestageOutputClaim(
          path: 'assets/restage/generated/neutral/welcome/screen.rfwtxt',
          role: 'screen-text',
          builder: 'test',
          ownershipKey: 'publication:neutral/welcome',
        ),
        RestageOutputClaim(
          path: 'assets/restage/generated/neutral/welcome/screen.rfw',
          role: 'screen-blob',
          builder: 'test',
          ownershipKey: 'publication:neutral/welcome',
        ),
        RestageOutputClaim(
          path:
              'assets/restage/generated/neutral/welcome/screen.capability.json',
          role: 'capability-sidecar',
          builder: 'test',
          ownershipKey: 'publication:neutral/welcome',
        ),
      ],
      isCanonical: true,
    );

RestageSourceDeclaration _flowDeclaration({
  required LibraryElement library,
  required Element declaration,
  required String id,
  int version = 1,
  int minClient = 1,
}) =>
    RestageSourceDeclaration.frozen(
      kind: RestageRosterSourceKind.flow,
      libraryIdentity: library.identifier,
      libraryPath: 'lib/authoring.dart',
      declarationIdentity: _identity(declaration),
      sourcePath: 'lib/authoring.dart',
      explicitId: id,
      span: _span,
      identityClaims: [
        RestageIdentityClaim(namespace: 'test/flow/general', key: id),
      ],
      outputs: [
        const RestageOutputClaim(
          path: 'lib/authoring.rsflow.g.dart',
          role: 'flow-descriptor',
          builder: 'test',
          ownershipKey: 'library:authoring',
        ),
        RestageOutputClaim(
          path: 'assets/restage/generated/general/$id/flow.json',
          role: 'flow-document',
          builder: 'test',
          ownershipKey: 'publication:general/$id',
        ),
      ],
      surface: Surface.general,
      version: version,
      minClient: minClient,
      delivery: FlowDeliveryMode.typed,
      isCanonical: true,
    );

String _identity(Element element) =>
    '${element.library!.identifier}#${element.name ?? '<unnamed>'}';

List<int> _sidecarBytes(List<int> blob) => utf8.encode(
      jsonEncode(
        CapabilitySidecar(
          blobSha256: CapabilitySidecar.hashBlob(blob),
          manifest: CapabilityManifest(
            builtInFloor: 1,
            requiredLibraries: const [],
          ),
        ).toJson(),
      ),
    );

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

part 'restage.generated/authoring.restage.g.dart';

@Screen(id: 'welcome')
final class Welcome extends StatelessWidget {
  const Welcome({super.key});

  static const continueFlow = SurfaceEvent<void>('continue');

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

@FlowGraph(
  id: 'advanced_child',
  surface: Surface.general,
  version: 2,
  minClient: 3,
)
final class AdvancedChild extends RestageFlow {
  const AdvancedChild();

  @override
  FlowDef buildFlow() => throw UnimplementedError();
}

final done = Completion('done');
final childStep = Subflow(
  'child',
  flow: AdvancedChild,
  onComplete: done,
);

@FlowGraph(id: 'parent', surface: Surface.general)
final parent = FlowDefinition(
  start: Welcome,
  transitions: [
    Transition(Welcome.continueFlow, to: childStep),
  ],
);
''';
