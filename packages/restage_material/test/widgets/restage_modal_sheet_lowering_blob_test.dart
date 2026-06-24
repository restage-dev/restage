// ignore_for_file: depend_on_referenced_packages, implementation_imports

import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:flutter/cupertino.dart' show CupertinoSheetTransition;
import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/rfw_emitter.dart';
import 'package:restage_core/restage_core.dart' as core;
import 'package:restage_material/restage_material.dart';
import 'package:rfw/formats.dart' show parseLibraryFile;
import 'package:rfw/rfw.dart' hide Switch, WidgetLibrary;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart' as schema;

const LibraryName _coreLibrary = LibraryName(<String>['restage', 'core']);
const LibraryName _materialLibrary =
    LibraryName(<String>['restage', 'material']);
const LibraryName _cupertinoLibrary =
    LibraryName(<String>['restage', 'cupertino']);
const LibraryName _rootLibrary = LibraryName(<String>['restage', 'paywall']);

String _productionLoweredBlob() => _loweredBlobFor('''
ElevatedButton(
  onPressed: () => showModalBottomSheet<void>(
    context: context,
    builder: (_) => SizedBox(
      width: 400.0,
      height: 300.0,
      child: Center(child: Text('Sheet body')),
    ),
  ),
  child: Text('Open'),
)
''');

// Bare `showCupertinoSheet` (no library prefix) so the unresolved string parse
// is recognised as the top-level Flutter function via the name-fallback.
String _productionLoweredCupertinoBlob() => _loweredBlobFor('''
ElevatedButton(
  onPressed: () => showCupertinoSheet<void>(
    context: context,
    pageBuilder: (_) => SizedBox(
      width: 400.0,
      height: 300.0,
      child: Center(child: Text('Sheet body')),
    ),
  ),
  child: Text('Open'),
)
''');

String _loweredBlobFor(String triggerExpression) {
  final expression = _parseExpression(triggerExpression);
  final translation = ExpressionTranslator(
    catalog: _loadMergedCatalogForTest(),
    helpers: HelperRegistry(),
  ).translate(expression);
  if (translation.issues.isNotEmpty) {
    throw StateError('Unexpected lowering issues: ${translation.issues}');
  }
  return emitPaywallLibrary(
    translation.dsl,
    rootWidgetState: translation.rootWidgetState,
  );
}

Expression _parseExpression(String expression) {
  final unit = parseString(content: 'Object x() => $expression;').unit;
  final declaration = unit.declarations.whereType<FunctionDeclaration>().single;
  final body = declaration.functionExpression.body as ExpressionFunctionBody;
  return body.expression;
}

schema.Catalog _loadMergedCatalogForTest() {
  final catalogs = [
    _loadCatalog('../restage_core/lib/src/widget_catalog/catalog.json'),
    _loadCatalog('lib/src/widget_catalog/catalog.json'),
    _loadCatalog('../restage_cupertino/lib/src/widget_catalog/catalog.json'),
  ];
  return schema.Catalog(
    schemaVersion: schema.kSupportedSchemaVersion,
    generatedAt: catalogs.first.generatedAt,
    libraries: {
      for (final catalog in catalogs) ...catalog.libraries,
    },
    widgets: [
      for (final catalog in catalogs) ...catalog.widgets,
    ],
    structuredTypes: [
      for (final catalog in catalogs) ...catalog.structuredTypes,
    ],
    unions: [
      for (final catalog in catalogs) ...catalog.unions,
    ],
    designTokens: [
      for (final catalog in catalogs) ...catalog.designTokens,
    ],
    flutterVersion: catalogs.first.flutterVersion,
  );
}

schema.Catalog _loadCatalog(String path) =>
    schema.decodeCatalog(File(path).readAsStringSync());

Runtime _buildRuntime(String source) => Runtime()
  ..update(_coreLibrary, core.buildCoreWidgetLibrary())
  ..update(_materialLibrary, buildMaterialWidgetLibrary())
  ..update(_cupertinoLibrary, LocalWidgetLibrary(const {}))
  ..update(_rootLibrary, parseLibraryFile(source));

Future<void> _pumpProductionLoweredBlob(WidgetTester tester) =>
    _pumpBlob(tester, _productionLoweredBlob());

Future<void> _pumpBlob(WidgetTester tester, String blob) async {
  await tester.pumpWidget(
    MaterialApp(
      // No explicit theme: ThemeData defaults `platform` to
      // `defaultTargetPlatform`, which reads any
      // `debugDefaultTargetPlatformOverride` the caller has set — so
      // `Theme.of(context).platform` reflects the forced platform.
      home: Scaffold(
        body: RemoteWidget(
          runtime: _buildRuntime(blob),
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
  group('RestageModalSheet production lowering blob', () {
    testWidgets('opens from the lowered trigger and closes on drag',
        (tester) async {
      await _pumpProductionLoweredBlob(tester);
      expect(find.text('Open'), findsOneWidget);
      expect(find.byType(RestageModalSheet), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);

      await tester.tap(find.text('Open'));
      await tester.pump();
      final sheet = find.byType(BottomSheet);
      expect(sheet, findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('Sheet body'), findsOneWidget);

      final scrim = find.descendant(
        of: find.byType(RestageModalSheet),
        matching: find.byType(ModalBarrier),
      );
      expect(scrim, findsOneWidget);
      expect(tester.getSize(scrim), tester.getSize(find.byType(MaterialApp)));

      final restTop = tester.getTopLeft(sheet).dy;
      final gesture = await tester.startGesture(tester.getCenter(sheet));
      for (var i = 0; i < 6; i++) {
        await gesture.moveBy(const Offset(0, 45));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(tester.getTopLeft(sheet).dy, greaterThan(restTop));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('Open'), findsOneWidget);
    });

    testWidgets('clears the synthetic flag on scrim tap', (tester) async {
      await _pumpProductionLoweredBlob(tester);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
    });
  });

  // Match-Flutter per function: the lowering pins the sheet library by source
  // function, so the rendered path is fixed regardless of the runtime platform.
  group('RestageModalSheet per-function presentation render-proof', () {
    // Force the ambient platform, then reset it inside the body (before the
    // framework checks the foundation vars at test end).
    Future<void> runOn(
      TargetPlatform platform,
      Future<void> Function() body,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await body();
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }

    testWidgets('showModalBottomSheet renders the Material path even on iOS',
        (tester) async {
      await runOn(TargetPlatform.iOS, () async {
        await _pumpBlob(tester, _productionLoweredBlob());
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(find.text('Sheet body'), findsOneWidget);
        expect(find.byType(BottomSheet), findsOneWidget);
        expect(find.byType(CupertinoSheetTransition), findsNothing,
            reason: 'presentation: material pins Material even under iOS');
      });
    });

    testWidgets('showCupertinoSheet renders the Cupertino path even on Android',
        (tester) async {
      await runOn(TargetPlatform.android, () async {
        await _pumpBlob(tester, _productionLoweredCupertinoBlob());
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(find.text('Sheet body'), findsOneWidget);
        expect(find.byType(CupertinoSheetTransition), findsOneWidget,
            reason:
                'presentation: cupertino pins Cupertino even under Android');
      });
    });
  });
}
