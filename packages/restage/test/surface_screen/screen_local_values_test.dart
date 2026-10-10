import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/delivery/delivered_fonts.dart';
import 'package:restage/src/runtime/local_values.dart';
import 'package:restage_core/restage_core.dart' show DeliveredIconFonts;
import 'package:restage_shared/restage_shared.dart'
    show
        CapabilityManifest,
        DeliveredIconFont,
        LibraryRequirement,
        kSurfaceFeatureClientFloor;

import 'surface_screen_test_support.dart';

const String _answerScreen = '''
import restage.core;
import restage.material;

widget OnboardingScreen = Column(children: [
  TextField(onChanged: event "restage.local.set" { key: "answer" }),
  switch data.local.answer {
    "blue": Text(text: "Answer blue"),
    "blue sky": Text(text: "blue sky"),
    "seeded": Text(text: "seeded"),
    default: Text(text: "no answer"),
  },
]);
''';

void main() {
  setUp(resetSurfaceScreenTestState);
  tearDown(DeliveredIconFontLoader.reset);

  Future<void> mountScreen(
    WidgetTester tester, {
    required ResolvedSurfaceScreen Function(ScreenFixture<String>) resolve,
    required List<String> events,
  }) async {
    final fixture = stringScreenFixture(
      blob: rfwSourceBlob(_answerScreen),
      capabilities: CapabilityManifest(
        builtInFloor: kSurfaceFeatureClientFloor,
        requiredLibraries: const <LibraryRequirement>[],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RestageScreen<String>(
            screen: fixture.ref,
            resolver: FixedScreenResolver(resolve(fixture)),
            onEvent: events.add,
            unavailable: SurfaceScreenUnavailablePolicy.fallback(
              builder: (_, error) => Text('fallback:${error.reason.name}'),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets(
      'a value callback writes a screen-local value the screen reads, and the '
      'write never reaches the host callback', (tester) async {
    final events = <String>[];
    await mountScreen(tester, resolve: (f) => f.bundled(), events: events);
    expect(find.text('no answer'), findsOneWidget);

    tester.widget<TextField>(find.byType(TextField)).onChanged!('blue');
    await tester.pump();
    expect(find.text('Answer blue'), findsOneWidget);

    tester.widget<TextField>(find.byType(TextField)).onChanged!('blue sky');
    await tester.pump();
    expect(find.text('blue sky'), findsOneWidget);

    expect(events, isEmpty);
    expect(find.textContaining('fallback:'), findsNothing);
  });

  testWidgets('typing into the field updates data.local', (tester) async {
    final events = <String>[];
    await mountScreen(tester, resolve: (f) => f.bundled(), events: events);

    await tester.enterText(find.byType(TextField), 'blue');
    // A focused field's cursor blinks forever, so pump a fixed time.
    await tester.pump(const Duration(milliseconds: 100));
    final answered = find.text('Answer blue').evaluate().length;
    final fallbacks = find.textContaining('fallback:').evaluate().length;

    // Unmount first so a failing expectation is reported, not swallowed.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(answered, 1);
    expect(fallbacks, 0);
    expect(events, isEmpty);
  });

  testWidgets('a delivered seed shows before the first input', (tester) async {
    await mountScreen(
      tester,
      resolve: (f) => f.bundled(
        sections: const SurfaceSections(
          localSeeds: <String, Map<String, Object>>{
            'OnboardingScreen': <String, Object>{'answer': 'seeded'},
          },
        ),
      ),
      events: <String>[],
    );
    expect(find.text('seeded'), findsOneWidget);
  });

  testWidgets('delivered icon fonts are in scope above the screen',
      (tester) async {
    DeliveredIconFontLoader.loadFont = (family, bytes) async {};
    final font = DeliveredIconFont(
      family: 'MaterialIcons',
      bytes: File(
        '../restage_shared/test/fonts/fixtures/material_icons_subset.otf',
      ).readAsBytesSync(),
    );
    await tester.runAsync(
      () => DeliveredIconFontLoader.loadAll(<DeliveredIconFont>[font]),
    );

    await mountScreen(
      tester,
      resolve: (f) => f.bundled(
        sections: SurfaceSections(iconFonts: <DeliveredIconFont>[font]),
      ),
      events: <String>[],
    );

    final scope =
        tester.widget<DeliveredIconFonts>(find.byType(DeliveredIconFonts));
    expect(scope.fonts.keys, <String>['MaterialIcons']);
    expect(
      scope.fonts['MaterialIcons']!.loadedFamily,
      DeliveredIconFontLoader.familyFor(font.bytes),
    );
  });
}
