// Present-but-empty / present-but-all-malformed single-select `items` must
// fail SAFE, never crash the render.
//
// The generated factory reads `items` via `RestageDecoders.selectionOptionList`
// and applies the required-slot throw on `null`. The decoder distinguishes an
// ABSENT slot (→ null, the required-throw is the corruption contract) from a
// PRESENT-but-degenerate list (→ [], so the compiled widget renders its empty
// state — SizedBox.shrink). This drives the REAL generated factory + decoder
// through the rfw runtime to prove a present-empty wire renders nothing rather
// than throwing an ArgumentError that would crash the surface.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart' as core;
import 'package:restage_material/restage_material.dart';
import 'package:rfw/formats.dart' show parseLibraryFile;
import 'package:rfw/rfw.dart' hide Switch, WidgetLibrary;

const LibraryName _coreLibrary = LibraryName(<String>['restage', 'core']);
const LibraryName _materialLibrary =
    LibraryName(<String>['restage', 'material']);
const LibraryName _rootLibrary = LibraryName(<String>['restage', 'paywall']);

Runtime _buildRuntime(String paywallSource) => Runtime()
  ..update(_coreLibrary, core.buildCoreWidgetLibrary())
  ..update(_materialLibrary, buildMaterialWidgetLibrary())
  ..update(_rootLibrary, parseLibraryFile(paywallSource));

Future<void> _pump(WidgetTester tester, String paywallSource) async {
  final runtime = _buildRuntime(paywallSource);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: RemoteWidget(
          runtime: runtime,
          data: DynamicContent(),
          widget: const FullyQualifiedWidgetName(_rootLibrary, 'Paywall'),
          onEvent: (_, __) {},
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('single-select present-but-degenerate items fail safe', () {
    testWidgets(
        'RestageDropdownString with a present-empty items list renders nothing '
        '(no throw)', (tester) async {
      await _pump(tester, '''
import restage.core;
import restage.material;
widget Paywall = RestageDropdownString(items: []);
''');

      expect(tester.takeException(), isNull);
      // The compiled widget fail-safes to SizedBox.shrink; no DropdownButton.
      expect(find.byType(DropdownButton<String>), findsNothing);
      expect(find.byType(RestageDropdown<String>), findsOneWidget);
    });

    testWidgets(
        'RestageRadioGroupString with a present-empty items list renders '
        'nothing (no throw)', (tester) async {
      await _pump(tester, '''
import restage.core;
import restage.material;
widget Paywall = RestageRadioGroupString(items: []);
''');

      expect(tester.takeException(), isNull);
      expect(find.byType(RadioGroup<String>), findsNothing);
      expect(find.byType(RestageRadioGroup<String>), findsOneWidget);
    });

    testWidgets(
        'RestageDropdownString with a present-but-all-malformed items list '
        'renders nothing (no throw)', (tester) async {
      // Every entry is missing its `value` — the decoder drops them all and
      // returns [] (present ⇒ a list), so the factory's required-throw does not
      // fire and the widget renders its empty state.
      await _pump(tester, '''
import restage.core;
import restage.material;
widget Paywall = RestageDropdownString(items: [{label: "no value"}]);
''');

      expect(tester.takeException(), isNull);
      expect(find.byType(DropdownButton<String>), findsNothing);
      expect(find.byType(RestageDropdown<String>), findsOneWidget);
    });
  });
}
