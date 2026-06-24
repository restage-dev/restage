// Blob-level render + drag proof for RestageModalSheet.
//
// Unlike `restage_modal_sheet_test.dart` (which exercises the Flutter
// widget directly), this renders RestageModalSheet THROUGH the catalog:
// a hand-authored declarative document references the widget by name,
// binds `open` to a state flag, and clears the flag from the
// `onSheetDismissed` event — exactly the declarative state machine the
// codegen lowering will emit (trigger → set flag true → sheet observes
// the flag → its internal drag fires onSheetDismissed → set flag false).
// This proves the curation entry, the generated builder, and the
// open/dismiss wiring all work end-to-end over the real rfw runtime.

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

/// A declarative document: a trigger button opens the sheet by setting a
/// state flag; the sheet is bound to that flag and clears it on dismiss.
const String _blobSource = '''
import restage.core;
import restage.material;
widget Paywall { sheetOpen: false } = Stack(
  fit: "expand",
  children: [
    Center(
      child: ElevatedButton(
        onPressed: set state.sheetOpen = true,
        child: Text(text: "Open"),
      ),
    ),
    RestageModalSheet(
      open: state.sheetOpen,
      isDismissible: true,
      enableDrag: true,
      onSheetDismissed: set state.sheetOpen = false,
      child: SizedBox(
        width: 400.0,
        height: 300.0,
        child: Center(child: Text(text: "Sheet body")),
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

void main() {
  group('RestageModalSheet — rendered through the catalog blob', () {
    testWidgets('renders the trigger; the sheet is closed until opened',
        (tester) async {
      await _pumpBlob(tester, _blobSource);
      expect(find.text('Open'), findsOneWidget);
      expect(find.byType(RestageModalSheet), findsOneWidget,
          reason: 'the catalog factory instantiated the widget');
      expect(find.byType(BottomSheet), findsNothing,
          reason: 'closed: no sheet rendered');
      expect(find.text('Sheet body'), findsNothing);
    });

    testWidgets('tapping the trigger sets the flag → the sheet slides up',
        (tester) async {
      await _pumpBlob(tester, _blobSource);
      final screenH = tester.getSize(find.byType(MaterialApp)).height;

      await tester.tap(find.text('Open'));
      await tester.pump(); // state flips, sheet mounts at the bottom edge
      final sheet = find.byType(BottomSheet);
      expect(sheet, findsOneWidget);
      final startTop = tester.getTopLeft(sheet).dy;
      expect(startTop, greaterThan(screenH - 50),
          reason: 'sheet starts near the bottom edge');

      await tester.pumpAndSettle();
      expect(tester.getTopLeft(sheet).dy, lessThan(startTop - 100),
          reason: 'the sheet slid up to rest');
      expect(find.text('Sheet body'), findsOneWidget);
    });

    testWidgets('the open sheet draws a full-surface scrim', (tester) async {
      await _pumpBlob(tester, _blobSource);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final scrim = find.descendant(
        of: find.byType(RestageModalSheet),
        matching: find.byType(ModalBarrier),
      );
      expect(scrim, findsOneWidget);
      expect(tester.getSize(scrim), tester.getSize(find.byType(MaterialApp)),
          reason: 'the scrim covers the whole surface');
    });

    testWidgets('drag-down clears the flag → the sheet closes', (tester) async {
      await _pumpBlob(tester, _blobSource);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final sheet = find.byType(BottomSheet);
      final restTop = tester.getTopLeft(sheet).dy;

      final gesture = await tester.startGesture(tester.getCenter(sheet));
      for (var i = 0; i < 6; i++) {
        await gesture.moveBy(const Offset(0, 45));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(tester.getTopLeft(sheet).dy, greaterThan(restTop),
          reason: 'the sheet follows the finger down during the drag');
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsNothing,
          reason: 'onSheetDismissed cleared the flag → the sheet closed');
      expect(find.text('Open'), findsOneWidget,
          reason: 'the trigger is interactive again');
    });

    testWidgets('scrim-tap clears the flag → the sheet closes', (tester) async {
      await _pumpBlob(tester, _blobSource);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);

      await tester.tapAt(const Offset(10, 10)); // tap the scrim
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing,
          reason: 'a scrim tap dismissed the sheet via onSheetDismissed');
    });
  });
}
