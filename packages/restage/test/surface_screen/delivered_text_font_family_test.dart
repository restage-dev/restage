import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';

import 'surface_screen_test_support.dart';

const _packaged =
    TextStyle(fontFamily: 'DisplaySerif', package: 'example_fonts');
const _family = 'packages/example_fonts/DisplaySerif';

void main() {
  setUp(resetSurfaceScreenTestState);

  testWidgets('delivered text keeps a packaged font family', (tester) async {
    final fixture = stringScreenFixture(
      blob: rfwSourceBlob('''
import restage.core;

widget OnboardingScreen = Column(children: [
  Text(text: "Theme", fontFamily: data.theme.textTheme.titleLarge.fontFamily),
  Text(text: "Literal", fontFamily: "DisplaySerif", fontPackage: "example_fonts"),
  Text(text: "Inherited"),
]);
'''),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          textTheme:
              const TextTheme(titleLarge: _packaged, bodyMedium: _packaged),
        ),
        home: Scaffold(
          body: RestageScreen<String>(
            screen: fixture.ref,
            resolver: FixedScreenResolver(fixture.bundled()),
            unavailable: SurfaceScreenUnavailablePolicy.fallback(
              builder: (_, error) => Text('fallback:${error.reason.name}'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final text in ['Theme', 'Literal', 'Inherited']) {
      final paragraph = tester.renderObject<RenderParagraph>(find.text(text));
      expect(paragraph.text.style?.fontFamily, _family, reason: text);
    }
  });
}
