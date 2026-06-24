// Blob-level render + expand proof for RestageDraggableSheet.
//
// Unlike `restage_draggable_sheet_test.dart` (which exercises the Flutter
// widget directly), this renders RestageDraggableSheet THROUGH the catalog:
// a hand-authored declarative document references the widget by name and
// binds `expanded` to a state flag a trigger sets true — exactly the
// declarative state machine the codegen lowering will emit (a "see plans"
// tap → set flag true → the sheet observes the flag → it animates to the
// expanded detent). This proves the curation entry, the generated builder,
// and the expand wiring all work end-to-end over the real rfw runtime.

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

/// A declarative document: a trigger button expands the sheet by setting a
/// state flag; the sheet is bound to that flag. The sheet is persistent —
/// it has no dismiss, so there is no flag-clearing event.
const String _blobSource = '''
import restage.core;
import restage.material;
widget Paywall { expanded: false } = Stack(
  fit: "expand",
  children: [
    Center(
      child: ElevatedButton(
        onPressed: set state.expanded = true,
        child: Text(text: "See plans"),
      ),
    ),
    RestageDraggableSheet(
      expanded: state.expanded,
      initialChildSize: 0.3,
      minChildSize: 0.2,
      maxChildSize: 0.9,
      child: SizedBox(
        width: 400.0,
        height: 800.0,
        child: Center(child: Text(text: "Plans")),
      ),
    ),
  ],
);
''';

Runtime _buildRuntime(String source) => Runtime()
  ..update(_coreLibrary, core.buildCoreWidgetLibrary())
  ..update(_materialLibrary, buildMaterialWidgetLibrary())
  ..update(_rootLibrary, parseLibraryFile(source));

Future<void> _pumpBlob(WidgetTester tester, String source) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: RemoteWidget(
          runtime: _buildRuntime(source),
          data: DynamicContent(),
          widget: const FullyQualifiedWidgetName(_rootLibrary, 'Paywall'),
          onEvent: (_, __) {},
        ),
      ),
    ),
  );
  await tester.pump();
}

double _sheetSize(WidgetTester tester) => tester
    .widget<FractionallySizedBox>(find.byType(FractionallySizedBox))
    .heightFactor!;

void main() {
  group('RestageDraggableSheet — rendered through the catalog blob', () {
    testWidgets('the catalog instantiates the sheet at the peek size',
        (tester) async {
      await _pumpBlob(tester, _blobSource);

      expect(find.text('See plans'), findsOneWidget);
      expect(
        find.byType(RestageDraggableSheet),
        findsOneWidget,
        reason: 'the catalog factory instantiated the widget',
      );
      expect(find.byType(DraggableScrollableSheet), findsOneWidget);
      expect(
        _sheetSize(tester),
        closeTo(0.3, 0.001),
        reason: 'rests at the inert initialChildSize from the blob',
      );
    });

    testWidgets('tapping the trigger sets the flag → the sheet expands',
        (tester) async {
      await _pumpBlob(tester, _blobSource);
      expect(_sheetSize(tester), closeTo(0.3, 0.001));

      await tester.tap(find.text('See plans'));
      await tester
          .pumpAndSettle(); // state flips true → animateTo(maxChildSize)

      expect(
        _sheetSize(tester),
        closeTo(0.9, 0.001),
        reason: 'the declarative expanded flag drove the sheet to its max '
            'detent — the state machine the lowering will emit',
      );
    });

    testWidgets('is non-closeable — a hard down-drag clamps at the floor',
        (tester) async {
      await _pumpBlob(tester, _blobSource);

      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, 2000),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      expect(
        find.byType(RestageDraggableSheet),
        findsOneWidget,
        reason: 'persistent: the sheet never dismisses',
      );
      expect(
        _sheetSize(tester),
        closeTo(0.2, 0.02),
        reason: 'clamps at minChildSize, never below',
      );
    });
  });
}
