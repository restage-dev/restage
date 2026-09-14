import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/formats.dart' hide WidgetLibrary;

/// The one icon the second flow's screen paints. The first flow's vocabulary
/// does not carry it.
const int _petsCodePoint = 0xe4a1;

/// Exactly what the first flow's screen names.
const SurfaceVocabulary _welcomeVocabulary = SurfaceVocabulary(
  widgets: RestageWidgetLibraries.fromVocabulary(
    core: <String, LocalWidgetBuilder>{'Text': buildText},
  ),
);

/// Exactly what the second flow's screen names — a widget and an icon the
/// first flow's vocabulary does not carry.
const SurfaceVocabulary _reminderVocabulary = SurfaceVocabulary(
  widgets: RestageWidgetLibraries.fromVocabulary(
    core: <String, LocalWidgetBuilder>{
      'Column': buildColumn,
      'Text': buildText,
    },
    material: <String, LocalWidgetBuilder>{'Icon': buildIcon},
  ),
  icons: RestageIconTable.fromFamilies(families: <String, Map<int, IconData>>{
    RestageIconTable.materialIconsFamily: <int, IconData>{
      _petsCodePoint: Icons.pets,
    },
  }),
);

final class _Result {
  const _Result({required this.completed});

  final bool completed;

  static _Result decode(Map<String, Object?> result) =>
      _Result(completed: result['completed'] == true);
}

const SurfaceFlowRef<_Result> _welcomeFlow = SurfaceFlowRef<_Result>(
  id: 'welcome_flow',
  version: 1,
  minClient: 3,
  surface: Surface.onboarding,
  decodeResult: _Result.decode,
  vocabulary: _welcomeVocabulary,
);

const SurfaceFlowRef<_Result> _reminderFlow = SurfaceFlowRef<_Result>(
  id: 'reminder_flow',
  version: 1,
  minClient: 3,
  surface: Surface.onboarding,
  decodeResult: _Result.decode,
  vocabulary: _reminderVocabulary,
);

const String _welcomeSource = '''
import restage.core;
widget OnboardingScreen = Text(text: "Welcome screen");
''';

const String _reminderSource = '''
import restage.core;
import restage.material;
widget OnboardingScreen = Column(
  children: [
    Text(text: "Reminder screen"),
    Icon(iconCodepoint: $_petsCodePoint),
  ],
);
''';

Uint8List _blob(String source) =>
    Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));

ResolvedFlow _resolved(SurfaceFlowRef<_Result> flow, String source) {
  final blob = _blob(source);
  return ResolvedFlow(
    document: FlowDocument(
      flow: flow.id,
      version: flow.version,
      schemaVersion: 1,
      minClient: flow.minClient,
      initial: 'first',
      actions: const {},
      legacyTerminalResultPassthrough: true,
      screenArtifacts: {
        'first': ScreenArtifact(
          path: 'first.rfw',
          version: 1,
          schemaVersion: 1,
          minClient: flow.minClient,
          contentHash: FlowContentHash.compute(blob),
        ),
      },
      states: const {
        'first': ScreenFlowState(
          screen: 'first',
          on: {'finish': FlowTransition.goto('done')},
        ),
        'done': EndFlowState(result: {'completed': true}),
      },
    ),
    screenBlobs: {'first': blob},
    cacheHit: false,
  );
}

/// Serves whichever flow is asked for, so one resolver survives the swap.
final class _EitherFlowResolver implements FlowResolver {
  @override
  Future<ResolvedFlow> resolve<R>(SurfaceFlowRef<R> flow) async =>
      flow.id == _welcomeFlow.id
          ? _resolved(_welcomeFlow, _welcomeSource)
          : _resolved(_reminderFlow, _reminderSource);
}

Widget _host(SurfaceFlowRef<_Result> flow) => MaterialApp(
      home: RestageFlowGraph<_Result>(
        flow: flow,
        resolver: _EitherFlowResolver(),
        unavailable: const FlowUnavailablePolicy.hide(),
      ),
    );

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

  testWidgets('a flow swapped in place renders with its own vocabulary',
      (tester) async {
    await tester.pumpWidget(_host(_welcomeFlow));
    await tester.pumpAndSettle();
    expect(find.text('Welcome screen'), findsOneWidget);

    await tester.pumpWidget(_host(_reminderFlow));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Reminder screen'), findsOneWidget);
    expect(find.byIcon(Icons.pets), findsOneWidget);
    expect(find.text('Welcome screen'), findsNothing);
  });
}
