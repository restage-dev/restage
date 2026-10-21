// Switches whose arms yield no value, and switch-selected inline spans, as
// the translator emits them for Dart conditionals with a `null` arm or an
// interpolated arm.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';
import 'package:rfw/formats.dart';
import 'package:rfw/rfw.dart';

const LibraryName _coreLibrary = LibraryName(<String>['restage', 'core']);
const LibraryName _rootLibrary = LibraryName(<String>['restage', 'paywall']);

Future<void> _pump(
  WidgetTester tester,
  String source, {
  required bool busy,
}) async {
  final runtime = Runtime()
    ..update(_coreLibrary, buildCoreWidgetLibrary())
    ..update(_rootLibrary, parseLibraryFile(source));
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: RemoteWidget(
        runtime: runtime,
        data: DynamicContent(<String, Object>{
          'context': <String, Object>{'busy': busy, 'days': '7'},
        }),
        widget: const FullyQualifiedWidgetName(_rootLibrary, 'Paywall'),
        onEvent: (_, __) {},
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('a callback arm with no value leaves the callback unset',
      (tester) async {
    const source = '''
import restage.core;
widget Paywall = GestureDetector(onTap: switch data.context.busy { true: event "yearly" {} }, child: Text(text: "x"));
''';
    await _pump(tester, source, busy: false);
    expect(tester.widget<GestureDetector>(find.byType(GestureDetector)).onTap,
        isNull);
    await _pump(tester, source, busy: true);
    expect(tester.widget<GestureDetector>(find.byType(GestureDetector)).onTap,
        isNotNull);
  });

  testWidgets('a keyed arm with no value beside a default yields no value',
      (tester) async {
    const source = '''
import restage.core;
widget Paywall = GestureDetector(onTap: switch data.context.days { "7": switch false {}, default: event "go" {} }, child: Text(text: "x"));
''';
    await _pump(tester, source, busy: false);
    expect(tester.widget<GestureDetector>(find.byType(GestureDetector)).onTap,
        isNull);
  });

  testWidgets('a border arm with no value draws no border', (tester) async {
    const source = '''
import restage.core;
widget Paywall = Container(border: switch data.context.busy { false: [{color: 0xFF000000}] });
''';
    BoxDecoration? decoration() {
      final container = tester.widget<Container>(find.byType(Container));
      return container.decoration as BoxDecoration?;
    }

    await _pump(tester, source, busy: true);
    expect(decoration()?.border, isNull);
    await _pump(tester, source, busy: false);
    expect(decoration()?.border, isNotNull);
  });

  testWidgets('a switch selects the inline span of each arm', (tester) async {
    const source = '''
import restage.core;
widget Paywall = TextRich(textSpan: switch data.context.busy { true: { text: "Starting..." }, false: { children: [{ text: "Start " }, { text: data.context.days }, { text: "-day trial" }] } });
''';
    await _pump(tester, source, busy: true);
    expect(find.text('Starting...', findRichText: true), findsOneWidget);
    await _pump(tester, source, busy: false);
    expect(find.text('Start 7-day trial', findRichText: true), findsOneWidget);
  });
}
