import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/formats.dart' hide WidgetLibrary;

/// Drawn by a widget the flow did install, so a miss proves the one absent
/// widget failed rather than that nothing was installed.
const String _installedLabel = 'Welcome';

/// A real catalog widget the narrow vocabulary below deliberately omits.
const String _absentWidget = 'Chip';

/// What a surface drawing only the screen's installed half would carry.
const SurfaceVocabulary _partialVocabulary = SurfaceVocabulary(
  widgets: RestageWidgetLibraries.fromVocabulary(
    core: <String, LocalWidgetBuilder>{
      'Column': buildColumn,
      'Text': buildText,
    },
    material: <String, LocalWidgetBuilder>{'Icon': buildIcon},
  ),
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
  vocabulary: _partialVocabulary,
);

/// A screen the delivery service was entitled to serve, naming one widget more
/// than this app installed.
Uint8List _screenBlob() {
  const source = '''
    import restage.core;
    import restage.material;
    widget OnboardingScreen = Column(
      children: [
        Text(text: "$_installedLabel"),
        Chip(label: Text(text: "Pro")),
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

final class _StaticResolver implements FlowResolver {
  _StaticResolver(this.resolved);

  final ResolvedFlow resolved;

  @override
  Future<ResolvedFlow> resolve<R>(SurfaceFlowRef<R> flow) async => resolved;
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

  testWidgets(
    'a flow screen naming one widget the installed libraries omit renders the '
    'fallback instead of a partial surface',
    (tester) async {
      FlowUnavailableError? unavailable;

      await tester.pumpWidget(
        MaterialApp(
          home: RestageFlowGraph<_WelcomeResult>(
            flow: _welcomeFlow,
            resolver: _StaticResolver(_resolvedFlow()),
            onFlowUnavailable: (error) => unavailable = error,
            unavailable: FlowUnavailablePolicy.fallback(
              builder: (_, __) => const Text('Unavailable'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The failure is contained: nothing escapes to the host.
      expect(tester.takeException(), isNull);

      // The host's fallback is what the user sees, and the flow failed closed.
      expect(find.text('Unavailable'), findsOneWidget);
      expect(unavailable?.reason, 'render_failed');
      expect(unavailable?.message, contains(_absentWidget));

      // The half that resolved is not left painted beside the fallback.
      expect(find.text(_installedLabel), findsNothing);
      expect(find.byType(Chip), findsNothing);
    },
  );
}
