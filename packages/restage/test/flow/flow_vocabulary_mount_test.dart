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

/// Records what was installed at the moment the flow asked for its artifact —
/// the controller's first outward act.
final class _RecordingResolver implements FlowResolver {
  _RecordingResolver(this.resolved);

  final ResolvedFlow resolved;
  RestageWidgetLibraries? librariesAtResolve;
  RestageIconTable? iconsAtResolve;

  @override
  Future<ResolvedFlow> resolve<R>(SurfaceFlowRef<R> flow) async {
    librariesAtResolve = InstalledWidgetLibraries.current;
    iconsAtResolve = InstalledIconTable.current;
    return resolved;
  }
}

/// Answers only when the test says so, so the loading state is observable.
final class _ControlledResolver implements FlowResolver {
  final Completer<ResolvedFlow> _response = Completer<ResolvedFlow>();

  void answer(ResolvedFlow flow) => _response.complete(flow);

  @override
  Future<ResolvedFlow> resolve<R>(SurfaceFlowRef<R> flow) => _response.future;
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

  testWidgets('a flow renders with nothing installed by hand', (tester) async {
    final resolver = _RecordingResolver(_resolvedFlow());
    expect(InstalledWidgetLibraries.current.isEmpty, isTrue);
    expect(InstalledIconTable.current.isEmpty, isTrue);

    await tester.pumpWidget(
      MaterialApp(
        home: RestageFlowGraph<_WelcomeResult>(
          flow: _welcomeFlow,
          resolver: resolver,
          unavailable: const FlowUnavailablePolicy.hide(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Welcome'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('the mount installs before the flow asks for its artifact',
      (tester) async {
    final resolver = _RecordingResolver(_resolvedFlow());

    await tester.pumpWidget(
      MaterialApp(
        home: RestageFlowGraph<_WelcomeResult>(
          flow: _welcomeFlow,
          resolver: resolver,
          unavailable: const FlowUnavailablePolicy.hide(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(resolver.librariesAtResolve?.core.keys, {'Column', 'Text'});
    expect(resolver.librariesAtResolve?.material.keys, {'Icon'});
    expect(
      resolver.iconsAtResolve?.lookUp(
        RestageIconTable.materialIconsFamily,
        _checkCodePoint,
      ),
      Icons.check,
    );
  });

  testWidgets('the vocabulary is installed while the flow is still loading',
      (tester) async {
    final resolver = _ControlledResolver();

    await tester.pumpWidget(
      MaterialApp(
        home: RestageFlowGraph<_WelcomeResult>(
          flow: _welcomeFlow,
          resolver: resolver,
          unavailable: const FlowUnavailablePolicy.hide(),
        ),
      ),
    );

    expect(find.text('Welcome'), findsNothing);
    expect(InstalledWidgetLibraries.current.core.keys, {'Column', 'Text'});
    expect(
      InstalledIconTable.current.lookUp(
        RestageIconTable.materialIconsFamily,
        _checkCodePoint,
      ),
      Icons.check,
    );

    resolver.answer(_resolvedFlow());
    await tester.pumpAndSettle();

    expect(find.text('Welcome'), findsOneWidget);
  });
}
