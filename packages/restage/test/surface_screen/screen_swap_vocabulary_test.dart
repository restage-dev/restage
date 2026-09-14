import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';

import 'surface_screen_test_support.dart';

/// The one icon the second screen paints. The first screen's vocabulary does
/// not carry it.
const int _petsCodePoint = 0xe4a1;

/// Exactly what the first screen's document names.
const SurfaceVocabulary _noticeVocabulary = SurfaceVocabulary(
  widgets: RestageWidgetLibraries.fromVocabulary(
    core: <String, LocalWidgetBuilder>{'Text': buildText},
  ),
);

/// Exactly what the second screen's document names — a widget and an icon the
/// first screen's vocabulary does not carry.
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

ScreenFixture<String> _noticeFixture() => stringScreenFixture(
      slug: 'notice',
      blob: rfwSourceBlob('''
import restage.core;

widget OnboardingScreen = Text(text: "Notice screen");
'''),
      vocabulary: _noticeVocabulary,
    );

ScreenFixture<String> _reminderFixture() => stringScreenFixture(
      slug: 'reminder',
      blob: rfwSourceBlob('''
import restage.core;
import restage.material;

widget OnboardingScreen = Column(
  children: [
    Text(text: "Reminder screen"),
    Icon(iconCodepoint: $_petsCodePoint),
  ],
);
'''),
      vocabulary: _reminderVocabulary,
    );

Widget _host(ScreenFixture<String> fixture) => MaterialApp(
      home: Scaffold(
        body: RestageScreen<String>(
          screen: fixture.ref,
          resolver: FixedScreenResolver(fixture.bundled()),
          unavailable: SurfaceScreenUnavailablePolicy.fallback(
            builder: (_, error) => Text('fallback:${error.reason.name}'),
          ),
        ),
      ),
    );

void main() {
  // Built once for the whole file, as generated top-level references are: a
  // later read never re-runs the construction that installs a vocabulary.
  final notice = _noticeFixture();
  final reminder = _reminderFixture();

  setUp(() {
    resetSurfaceScreenTestState();
    InstalledWidgetLibraries.reset();
    InstalledIconTable.reset();
  });

  tearDown(() {
    InstalledIconTable.reset();
    InstalledWidgetLibraries.install(RestageWidgetLibraries.builtIn());
  });

  testWidgets('a screen swapped in place renders with its own vocabulary',
      (tester) async {
    await tester.pumpWidget(_host(notice));
    await tester.pumpAndSettle();
    expect(find.text('Notice screen'), findsOneWidget);

    await tester.pumpWidget(_host(reminder));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Reminder screen'), findsOneWidget);
    expect(find.byIcon(Icons.pets), findsOneWidget);
    expect(find.text('Notice screen'), findsNothing);
  });

  testWidgets('mounting the same screen again installs its vocabulary again',
      (tester) async {
    expect(InstalledWidgetLibraries.current.isEmpty, isTrue);
    expect(InstalledIconTable.current.isEmpty, isTrue);

    await tester.pumpWidget(_host(reminder));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Reminder screen'), findsOneWidget);
    expect(find.byIcon(Icons.pets), findsOneWidget);
  });
}
