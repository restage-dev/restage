import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/formats.dart' hide WidgetLibrary;

/// The one icon the sub-flow's screen paints. The parent's screen paints none.
const int _starCodePoint = 0xe838;

/// Exactly what the parent's screen blob names, and nothing else.
const SurfaceVocabulary _parentVocabulary = SurfaceVocabulary(
  widgets: RestageWidgetLibraries.fromVocabulary(
    core: <String, LocalWidgetBuilder>{
      'Column': buildColumn,
      'Text': buildText,
    },
  ),
);

/// Exactly what the sub-flow's screen blob names, and nothing else.
const SurfaceVocabulary _detailsVocabulary = SurfaceVocabulary(
  widgets: RestageWidgetLibraries.fromVocabulary(
    core: <String, LocalWidgetBuilder>{
      'Column': buildColumn,
      'Text': buildText,
    },
    material: <String, LocalWidgetBuilder>{
      'Icon': buildIcon,
    },
  ),
  icons: RestageIconTable.fromFamilies(families: <String, Map<int, IconData>>{
    RestageIconTable.materialIconsFamily: <int, IconData>{
      _starCodePoint: Icons.star,
    },
  }),
);

Map<String, Object?> _passthrough(Map<String, Object?> result) => result;

const SurfaceFlowRef<Map<String, Object?>> _detailsFlow =
    SurfaceFlowRef<Map<String, Object?>>(
  id: 'details_flow',
  version: 1,
  minClient: 3,
  surface: Surface.onboarding,
  decodeResult: _passthrough,
  vocabulary: _detailsVocabulary,
);

const SurfaceFlowRef<Map<String, Object?>> _parentFlow =
    SurfaceFlowRef<Map<String, Object?>>(
  id: 'parent_flow',
  version: 1,
  minClient: 3,
  surface: Surface.onboarding,
  decodeResult: _passthrough,
  vocabulary: _parentVocabulary,
  subFlows: [_detailsFlow],
);

/// The same parent, carrying no reference to the flow it enters.
const SurfaceFlowRef<Map<String, Object?>> _parentFlowCarryingNothing =
    SurfaceFlowRef<Map<String, Object?>>(
  id: 'parent_flow',
  version: 1,
  minClient: 3,
  surface: Surface.onboarding,
  decodeResult: _passthrough,
  vocabulary: _parentVocabulary,
);

Uint8List _welcomeBlob() {
  const source = '''
    import restage.core;
    widget OnboardingScreen = Column(
      children: [
        Text(text: "Welcome"),
      ],
    );
  ''';
  return Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));
}

Uint8List _detailsBlob() {
  const source = '''
    import restage.core;
    import restage.material;
    widget OnboardingScreen = Column(
      children: [
        Text(text: "Details"),
        Icon(iconCodepoint: $_starCodePoint),
      ],
    );
  ''';
  return Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));
}

FlowContentHash _documentHash(FlowDocument document) => FlowContentHash.compute(
      utf8.encode(FlowDocumentCodec.encodePrettyJson(document)),
    );

ResolvedFlow _resolvedDetailsFlow() {
  final blob = _detailsBlob();
  final document = FlowDocument(
    flow: 'details_flow',
    version: 1,
    schemaVersion: 1,
    minClient: 3,
    initial: 'details',
    actions: const {},
    legacyTerminalResultPassthrough: true,
    screenArtifacts: {
      'details': ScreenArtifact(
        path: 'details.rfw',
        version: 1,
        schemaVersion: 1,
        minClient: 3,
        contentHash: FlowContentHash.compute(blob),
      ),
    },
    states: const {
      'details': ScreenFlowState(
        screen: 'details',
        on: {'finish': FlowTransition.goto('done')},
      ),
      'done': EndFlowState(result: <String, Object?>{}),
    },
  );
  return ResolvedFlow(
    document: document,
    screenBlobs: {'details': blob},
    contentHash: _documentHash(document),
    cacheHit: false,
  );
}

ResolvedFlow _resolvedParentFlow(FlowContentHash detailsHash) {
  final blob = _welcomeBlob();
  return ResolvedFlow(
    document: FlowDocument(
      flow: 'parent_flow',
      version: 1,
      schemaVersion: 1,
      minClient: 3,
      initial: 'welcome',
      actions: const {},
      legacyTerminalResultPassthrough: true,
      screenArtifacts: {
        'welcome': ScreenArtifact(
          path: 'welcome.rfw',
          version: 1,
          schemaVersion: 1,
          minClient: 3,
          contentHash: FlowContentHash.compute(blob),
        ),
      },
      states: {
        'welcome': const ScreenFlowState(
          screen: 'welcome',
          on: {'next': FlowTransition.goto('details')},
        ),
        'details': SubFlowState(
          flow: 'details_flow',
          version: 1,
          schemaVersion: 1,
          minClient: 3,
          contentHash: detailsHash,
          input: const {},
          onComplete: const [],
          defaultBranch: const FlowBranchTarget(target: 'done'),
        ),
        'done': const EndFlowState(result: <String, Object?>{}),
      },
    ),
    screenBlobs: {'welcome': blob},
    cacheHit: false,
  );
}

final class _MapFlowResolver implements FlowResolver {
  _MapFlowResolver(this.flows);

  final Map<String, ResolvedFlow> flows;

  @override
  Future<ResolvedFlow> resolve<R>(SurfaceFlowRef<R> flow) async {
    final resolved = flows[flow.id];
    if (resolved == null) {
      throw FlowUnavailableError(
        flowId: flow.id,
        flowVersion: flow.version,
        reason: 'missing_flow_json',
        message: 'Missing flow ${flow.id}.',
      );
    }
    return resolved;
  }
}

Future<void> _drainFlowTasks() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

/// Runs [parent] up to its sub-flow node and returns the controller there.
Future<RestageFlowController<Map<String, Object?>>> _runIntoSubFlow(
  SurfaceFlowRef<Map<String, Object?>> parent,
) async {
  final details = _resolvedDetailsFlow();
  final controller = RestageFlowController<Map<String, Object?>>(
    flow: parent,
    resolver: _MapFlowResolver({
      'parent_flow': _resolvedParentFlow(details.contentHash!),
      'details_flow': details,
    }),
    actions: null,
    onEvent: (_) {},
    onComplete: (_) {},
    onUnavailable: (_) {},
  );
  addTearDown(controller.dispose);
  await controller.load();
  controller.handleEvent('next', const <String, Object?>{});
  await _drainFlowTasks();
  return controller;
}

void main() {
  setUp(() {
    InstalledWidgetLibraries.reset();
    InstalledIconTable.reset();
  });

  tearDown(() {
    InstalledIconTable.reset();
    InstalledWidgetLibraries.install(RestageWidgetLibraries.builtIn());
  });

  test('entering a sub-flow installs what that sub-flow draws', () async {
    final controller = await _runIntoSubFlow(_parentFlow);

    expect(controller.currentScreenId, 'details');
    expect(InstalledWidgetLibraries.current.material.keys, contains('Icon'));
    expect(
      InstalledIconTable.current.lookUp(
        RestageIconTable.materialIconsFamily,
        _starCodePoint,
      ),
      Icons.star,
    );
  });

  test('a parent carrying no sub-flow reference installs nothing for it',
      () async {
    final controller = await _runIntoSubFlow(_parentFlowCarryingNothing);

    expect(controller.currentScreenId, 'details');
    expect(InstalledWidgetLibraries.current.material.isEmpty, isTrue);
    expect(InstalledIconTable.current.isEmpty, isTrue);
  });
}
