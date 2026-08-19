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
  late _Fixture fixture;

  setUpAll(() async {
    fixture = await _loadFixture();
  });

  test(
    'flat parent materializes its flat child effective floor and exact hash',
    () {
      final parent = fixture.flow('effective_parent');
      final authoredReference = parent.graph!.childFlows.values.single;
      final authoredState =
          parent.graph!.states.values.whereType<SubFlowState>().single;
      expect(authoredReference.minClient, 1);
      expect(authoredState.minClient, 1);
      expect(
        authoredReference.declarationIdentity,
        fixture.flow('effective_child').declarationIdentity,
      );

      final result = compilePackageSurfacePublications(
        fixture.inputFor(
          parentId: 'effective_parent',
          childSidecarFloor: 3,
        ),
      );

      expect(
        result.issues,
        isEmpty,
        reason: result.issues.map((issue) => issue.message).join('\n'),
      );
      final bundle = result.bundle!;
      final childBytes =
          bundle.outputFiles[_flowDocumentPath('effective_child')]!;
      final childDocument = FlowDocumentCodec.decodeJson(
        utf8.decode(childBytes),
      );
      final parentDocument = _flowDocument(bundle, 'effective_parent');
      final childState =
          parentDocument.states.values.whereType<SubFlowState>().single;
      expect(childDocument.minClient, 3);
      expect(childDocument.screenArtifacts['child_screen']!.minClient, 3);
      expect(childState.minClient, childDocument.minClient);
      expect(childState.contentHash, FlowContentHash.compute(childBytes));
    },
  );

  test('authored SurfaceFlowRef child floor remains an exact pin', () {
    final pinnedParent = fixture.flow('pinned_parent');
    final pinnedReference = pinnedParent.graph!.childFlows.values.single;
    expect(pinnedReference.minClient, 1);
    expect(
      pinnedReference.declarationIdentity,
      isNot(fixture.flow('effective_child').declarationIdentity),
    );

    final result = compilePackageSurfacePublications(
      fixture.inputFor(
        parentId: 'pinned_parent',
        childSidecarFloor: 3,
      ),
    );

    expect(result.bundle, isNull);
    expect(
      result.issues.map((issue) => issue.message).join('\n'),
      contains(
        'Child flow effective_child does not match its declared version or '
        'minimum client',
      ),
    );
  });
}

Future<_Fixture> _loadFixture() async {
  const sourceId = 'apps_examples|lib/subflow_authoring.dart';
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
        flows: {for (final flow in inspection.flows) flow.id: flow},
        entry: _class(library, 'Entry'),
        childScreen: _class(library, 'ChildScreen'),
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
    required this.entry,
    required this.childScreen,
  });

  final LibraryElement library;
  final Map<String, NormalizedFlowSource> flows;
  final ClassElement entry;
  final ClassElement childScreen;

  NormalizedFlowSource flow(String id) => flows[id]!;

  PackageSurfaceCompilationInput inputFor({
    required String parentId,
    required int childSidecarFloor,
  }) {
    final child = flow('effective_child');
    final parent = flow(parentId);
    final entryBlob = Uint8List.fromList(utf8.encode('RFW:entry'));
    final childBlob = Uint8List.fromList(utf8.encode('RFW:child_screen'));
    return PackageSurfaceCompilationInput(
      roster: assembleRestageSourceRoster([
        _screenDeclaration(library, entry, 'entry'),
        _screenDeclaration(library, childScreen, 'child_screen'),
        _flowDeclaration(library, child),
        _flowDeclaration(library, parent),
      ]),
      flows: [child, parent],
      renderedSources: [
        _artifact(entry, id: 'entry', blob: entryBlob, builtInFloor: 1),
        _artifact(
          childScreen,
          id: 'child_screen',
          blob: childBlob,
          builtInFloor: childSidecarFloor,
        ),
      ],
      standaloneScreens: const [],
    );
  }
}

RestageSourceDeclaration _screenDeclaration(
  LibraryElement library,
  ClassElement declaration,
  String id,
) =>
    RestageSourceDeclaration.frozen(
      kind: RestageRosterSourceKind.screen,
      libraryIdentity: library.identifier,
      libraryPath: 'lib/subflow_authoring.dart',
      declarationIdentity: _identity(declaration),
      sourcePath: 'lib/subflow_authoring.dart',
      explicitId: id,
      span: _span,
      identityClaims: [
        RestageIdentityClaim(namespace: 'test/screen/neutral', key: id),
      ],
      outputs: [
        RestageOutputClaim(
          path: 'lib/subflow_authoring.rsscreen.g.dart',
          role: 'screen-descriptor',
          builder: 'test',
          ownershipKey: 'library:${library.identifier}',
        ),
        RestageOutputClaim(
          path: 'assets/restage/generated/neutral/$id/screen.rfwtxt',
          role: 'screen-text',
          builder: 'test',
          ownershipKey: 'publication:neutral/$id',
        ),
        RestageOutputClaim(
          path: 'assets/restage/generated/neutral/$id/screen.rfw',
          role: 'screen-blob',
          builder: 'test',
          ownershipKey: 'publication:neutral/$id',
        ),
        RestageOutputClaim(
          path: 'assets/restage/generated/neutral/$id/screen.capability.json',
          role: 'capability-sidecar',
          builder: 'test',
          ownershipKey: 'publication:neutral/$id',
        ),
      ],
      isCanonical: true,
    );

RestageSourceDeclaration _flowDeclaration(
  LibraryElement library,
  NormalizedFlowSource flow,
) =>
    RestageSourceDeclaration.frozen(
      kind: RestageRosterSourceKind.flow,
      libraryIdentity: library.identifier,
      libraryPath: 'lib/subflow_authoring.dart',
      declarationIdentity: flow.declarationIdentity,
      sourcePath: 'lib/subflow_authoring.dart',
      explicitId: flow.id,
      span: _span,
      identityClaims: [
        RestageIdentityClaim(namespace: 'test/flow/general', key: flow.id),
      ],
      outputs: [
        const RestageOutputClaim(
          path: 'lib/subflow_authoring.rsflow.g.dart',
          role: 'flow-descriptor',
          builder: 'test',
          ownershipKey: 'library:subflow-authoring',
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
      minClient: flow.minClient,
      isCanonical: true,
    );

CompiledSurfaceArtifact _artifact(
  ClassElement declaration, {
  required String id,
  required Uint8List blob,
  required int builtInFloor,
}) =>
    CompiledSurfaceArtifact(
      declaration: declaration,
      blob: blob,
      capabilitySidecar: _sidecarBytes(blob, builtInFloor),
      flowArtifactPath: '$id.rfw',
      rfwText: utf8.encode('remote widget $id'),
    );

FlowDocument _flowDocument(
  PackageSurfaceCompilationBundle bundle,
  String flowId,
) =>
    FlowDocumentCodec.decodeJson(
      utf8.decode(bundle.outputFiles[_flowDocumentPath(flowId)]!),
    );

String _flowDocumentPath(String flowId) =>
    'assets/restage/generated/general/$flowId/flow.json';

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

const _span = RestageSourceSpan(
  path: 'lib/subflow_authoring.dart',
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
    if (buildStep.inputId.path != 'lib/subflow_authoring.dart') return;
    await onLibrary(await buildStep.inputLibrary, buildStep.inputId);
  }
}

const _source = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'subflow_authoring.rsscreen.g.dart';
part 'subflow_authoring.rsflow.g.dart';

@Screen(id: 'entry', minClient: 1)
final class Entry extends StatelessWidget {
  const Entry({super.key});

  static const next = SurfaceEvent<void>('next');

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

@Screen(id: 'child_screen', minClient: 1)
final class ChildScreen extends StatelessWidget {
  const ChildScreen({super.key});

  static const finish = SurfaceEvent<void>('finish');

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

@FlowGraph(id: 'effective_child', surface: Surface.general, minClient: 1)
const effectiveChild = FlowDefinition(
  start: ChildScreen,
  transitions: [Transition.complete(ChildScreen.finish)],
);

final parentDone = Completion('parent_done');
final childStep = Subflow(
  'child_step',
  flow: effectiveChild,
  onComplete: parentDone,
);

@FlowGraph(id: 'effective_parent', surface: Surface.general, minClient: 1)
final effectiveParent = FlowDefinition(
  start: Entry,
  transitions: [Transition(Entry.next, to: childStep)],
);

Map<String, Object?> decodePinnedChild(Map<String, Object?> result) => result;

const pinnedChildRef = SurfaceFlowRef<Map<String, Object?>>(
  id: 'effective_child',
  version: 1,
  minClient: 1,
  surface: Surface.general,
  decodeResult: decodePinnedChild,
);
final pinnedDone = Completion('pinned_done');
final pinnedStep = Subflow(
  'pinned_step',
  flow: pinnedChildRef,
  onComplete: pinnedDone,
);

@FlowGraph(id: 'pinned_parent', surface: Surface.general, minClient: 1)
final pinnedParent = FlowDefinition(
  start: Entry,
  transitions: [Transition(Entry.next, to: pinnedStep)],
);
''';
