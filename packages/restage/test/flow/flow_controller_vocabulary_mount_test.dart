import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/formats.dart' hide WidgetLibrary;

/// The one icon the flow's screen paints.
const int _checkCodePoint = 0xe156;

/// Exactly what the screen blob below names, and nothing else.
const SurfaceVocabulary _welcomeVocabulary = SurfaceVocabulary(
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

final class _WelcomeResult {
  const _WelcomeResult({required this.completed});

  final bool completed;

  static _WelcomeResult decode(Map<String, Object?> result) =>
      _WelcomeResult(completed: result['completed'] == true);
}

const SurfaceFlowRef<_WelcomeResult> _welcomeFlow =
    SurfaceFlowRef<_WelcomeResult>(
  id: 'welcome_flow',
  version: 1,
  minClient: 3,
  surface: Surface.onboarding,
  decodeResult: _WelcomeResult.decode,
  vocabulary: _welcomeVocabulary,
);

Uint8List _screenBlob() {
  const source = '''
    import restage.core;
    import restage.material;
    widget OnboardingScreen = Column(
      children: [
        Text(text: "Welcome"),
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
      flow: _welcomeFlow.id,
      version: _welcomeFlow.version,
      schemaVersion: 1,
      minClient: _welcomeFlow.minClient,
      initial: 'welcome',
      actions: const {},
      legacyTerminalResultPassthrough: true,
      screenArtifacts: {
        'welcome': ScreenArtifact(
          path: 'welcome.rfw',
          version: 1,
          schemaVersion: 1,
          minClient: _welcomeFlow.minClient,
          contentHash: FlowContentHash.compute(blob),
        ),
      },
      states: const {
        'welcome': ScreenFlowState(
          screen: 'welcome',
          on: {'finish': FlowTransition.goto('done')},
        ),
        'done': EndFlowState(result: {'completed': true}),
      },
    ),
    screenBlobs: {'welcome': blob},
    cacheHit: false,
  );
}

final class _StubResolver implements FlowResolver {
  @override
  Future<ResolvedFlow> resolve<R>(SurfaceFlowRef<R> flow) async =>
      _resolvedFlow();
}

/// Composes the flow primitives the way an application host does: a controller
/// it constructs itself, with a view under it and nothing installed by hand.
class _DirectFlowHost extends StatefulWidget {
  const _DirectFlowHost({required this.onUnavailable});

  final void Function(FlowUnavailableError error) onUnavailable;

  @override
  State<_DirectFlowHost> createState() => _DirectFlowHostState();
}

class _DirectFlowHostState extends State<_DirectFlowHost> {
  late final RestageFlowController<_WelcomeResult> _controller;

  @override
  void initState() {
    super.initState();
    _controller = RestageFlowController<_WelcomeResult>(
      flow: _welcomeFlow,
      resolver: _StubResolver(),
      actions: null,
      onEvent: (_) {},
      onComplete: (_) {},
      onUnavailable: widget.onUnavailable,
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
      RestageFlowView<_WelcomeResult>(controller: _controller);
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

  testWidgets('a host-composed controller renders with nothing installed',
      (tester) async {
    expect(InstalledWidgetLibraries.current.isEmpty, isTrue);
    expect(InstalledIconTable.current.isEmpty, isTrue);
    FlowUnavailableError? unavailable;

    await tester.pumpWidget(
      MaterialApp(
        home: _DirectFlowHost(onUnavailable: (error) => unavailable = error),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(unavailable, isNull);
    expect(find.text('Welcome'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  test('constructing the controller installs the flow vocabulary', () {
    final controller = RestageFlowController<_WelcomeResult>(
      flow: _welcomeFlow,
      resolver: _StubResolver(),
      actions: null,
      onEvent: (_) {},
      onComplete: (_) {},
      onUnavailable: (_) {},
    );
    addTearDown(controller.dispose);

    expect(InstalledWidgetLibraries.current.core.keys, {'Column', 'Text'});
    expect(InstalledWidgetLibraries.current.material.keys, {'Icon'});
    expect(
      InstalledIconTable.current.lookUp(
        RestageIconTable.materialIconsFamily,
        _checkCodePoint,
      ),
      Icons.check,
    );
  });
}
