import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/formats.dart' hide WidgetLibrary;

/// The one icon the hosted flow's screen paints.
const int _checkCodePoint = 0xe156;

/// Exactly what the screen blob below names, and nothing else.
const SurfaceVocabulary _noticeVocabulary = SurfaceVocabulary(
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
      _checkCodePoint: Icons.check,
    },
  }),
);

Map<String, Object?> _passthrough(Map<String, Object?> result) => result;

final SurfaceFlowRef<Map<String, Object?>> _noticeFlow =
    hostedSurfaceFlowRef<Map<String, Object?>>(
  id: 'notice_flow',
  version: 1,
  surfaceType: Surface.onboarding,
  decodeResult: _passthrough,
  vocabulary: _noticeVocabulary,
);

/// The same hosted flow, for an app that cannot know its content ahead of
/// time and so supplies no vocabulary.
final SurfaceFlowRef<Map<String, Object?>> _noticeFlowWithoutVocabulary =
    hostedSurfaceFlowRef<Map<String, Object?>>(
  id: 'notice_flow',
  version: 1,
  surfaceType: Surface.onboarding,
  decodeResult: _passthrough,
);

Uint8List _screenBlob() {
  const source = '''
    import restage.core;
    import restage.material;
    widget OnboardingScreen = Column(
      children: [
        Text(text: "Notice"),
        Icon(iconCodepoint: $_checkCodePoint),
      ],
    );
  ''';
  return Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));
}

ResolvedFlow _resolvedFlow() {
  final blob = _screenBlob();
  return ResolvedFlow(
    document: FlowDocument(
      flow: 'notice_flow',
      version: 1,
      schemaVersion: 1,
      minClient: 1,
      initial: 'notice',
      actions: const {},
      legacyTerminalResultPassthrough: true,
      screenArtifacts: {
        'notice': ScreenArtifact(
          path: 'notice.rfw',
          version: 1,
          schemaVersion: 1,
          minClient: 1,
          contentHash: FlowContentHash.compute(blob),
        ),
      },
      states: const {
        'notice': ScreenFlowState(
          screen: 'notice',
          on: {'finish': FlowTransition.goto('done')},
        ),
        'done': EndFlowState(result: <String, Object?>{}),
      },
    ),
    screenBlobs: {'notice': blob},
    cacheHit: false,
  );
}

final class _StubResolver implements FlowResolver {
  @override
  Future<ResolvedFlow> resolve<R>(SurfaceFlowRef<R> flow) async =>
      _resolvedFlow();
}

/// Mounts the hosted flow the way an application host does, with nothing
/// installed by hand.
class _HostedFlowHost extends StatefulWidget {
  const _HostedFlowHost({required this.flow});

  final SurfaceFlowRef<Map<String, Object?>> flow;

  @override
  State<_HostedFlowHost> createState() => _HostedFlowHostState();
}

class _HostedFlowHostState extends State<_HostedFlowHost> {
  late final RestageFlowController<Map<String, Object?>> _controller;

  @override
  void initState() {
    super.initState();
    _controller = RestageFlowController<Map<String, Object?>>(
      flow: widget.flow,
      resolver: _StubResolver(),
      actions: null,
      onEvent: (_) {},
      onComplete: (_) {},
      onUnavailable: (_) {},
    );
    unawaited(_controller.load());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      RestageFlowView<Map<String, Object?>>(controller: _controller);
}

void main() {
  setUp(() {
    Restage.debugReset();
    InstalledWidgetLibraries.reset();
    InstalledIconTable.reset();
  });

  tearDown(() {
    InstalledIconTable.reset();
    InstalledWidgetLibraries.install(RestageWidgetLibraries.builtIn());
  });

  testWidgets('a hosted flow given a vocabulary mounts with nothing installed',
      (tester) async {
    expect(InstalledWidgetLibraries.current.isEmpty, isTrue);
    expect(InstalledIconTable.current.isEmpty, isTrue);

    await tester.pumpWidget(
      MaterialApp(home: _HostedFlowHost(flow: _noticeFlow)),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Notice'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(InstalledWidgetLibraries.current.material.keys, contains('Icon'));
    expect(
      InstalledIconTable.current.lookUp(
        RestageIconTable.materialIconsFamily,
        _checkCodePoint,
      ),
      Icons.check,
    );
  });

  testWidgets(
      'ordinary configure mounts a hosted flow with no generated vocabulary',
      (tester) async {
    await tester.runAsync(() async {
      Restage.configure(analyticsEnabled: false);
    });
    await tester.pumpWidget(
      MaterialApp(home: _HostedFlowHost(flow: _noticeFlowWithoutVocabulary)),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Notice'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(InstalledWidgetLibraries.current.cupertino, isNotEmpty);
  });

  test('a hosted flow given no vocabulary installs nothing', () {
    final controller = RestageFlowController<Map<String, Object?>>(
      flow: _noticeFlowWithoutVocabulary,
      resolver: _StubResolver(),
      actions: null,
      onEvent: (_) {},
      onComplete: (_) {},
      onUnavailable: (_) {},
    );
    addTearDown(controller.dispose);

    expect(InstalledWidgetLibraries.current.isEmpty, isTrue);
    expect(InstalledIconTable.current.isEmpty, isTrue);
  });
}
