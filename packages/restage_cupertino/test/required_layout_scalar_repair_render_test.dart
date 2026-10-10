// End-to-end proof that required Cupertino layout values fail during build
// instead of reaching a render object with invalid geometry.

import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart' as core;
import 'package:restage_cupertino/restage_cupertino.dart';
import 'package:rfw/formats.dart' show parseLibraryFile;
import 'package:rfw/rfw.dart' hide WidgetLibrary;

const LibraryName _coreLibrary = LibraryName(<String>['restage', 'core']);
const LibraryName _cupertinoLibrary =
    LibraryName(<String>['restage', 'cupertino']);
const LibraryName _rootLibrary = LibraryName(<String>['restage', 'paywall']);

Future<void> _pump(
  WidgetTester tester,
  String paywallSource, {
  Map<String, Object?>? data,
}) async {
  final runtime = Runtime()
    ..update(_coreLibrary, core.buildCoreWidgetLibrary())
    ..update(_cupertinoLibrary, buildCupertinoWidgetLibrary())
    ..update(_rootLibrary, parseLibraryFile(paywallSource));
  await tester.pumpWidget(
    CupertinoApp(
      home: SizedBox(
        width: 300.0,
        height: 300.0,
        child: RemoteWidget(
          runtime: runtime,
          data: DynamicContent(data ?? <String, Object?>{}),
          widget: const FullyQualifiedWidgetName(_rootLibrary, 'Paywall'),
          onEvent: (_, __) {},
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('a NaN CupertinoPicker item extent throws during build',
      (tester) async {
    await _pump(
      tester,
      '''
import restage.core;
import restage.cupertino;
widget Paywall = CupertinoPicker(itemExtent: data.nan,
  children: [Text(text: "one"), Text(text: "two")]);
''',
      data: <String, Object?>{'nan': double.nan},
    );

    // Build failures are exposed by the runtime boundary; letting the value
    // reach the wheel's layout math would hide the failure in a broken frame.
    expect(tester.takeException(), isA<ArgumentError>());
    expect(find.byType(CupertinoPicker), findsNothing);
  });

  group('an optional Cupertino item extent falls back to its default', () {
    testWidgets('a NaN date picker item extent lays out at the default extent',
        (tester) async {
      await _pump(
        tester,
        '''
import restage.core;
import restage.cupertino;
widget Paywall = CupertinoDatePicker(itemExtent: data.nan);
''',
        data: <String, Object?>{'nan': double.nan},
      );

      // An unrepaired value divides into the wheel's scroll arithmetic during
      // layout, where the resulting throw is swallowed and leaves a broken
      // frame. Treating it as unauthored restores the widget's own extent.
      expect(tester.takeException(), isNull);
      final viewport = tester.renderObject<RenderListWheelViewport>(
        find.byType(ListWheelViewport).first,
      );
      expect(viewport.itemExtent, 32.0);
      expect(viewport.itemExtent.isFinite, isTrue);
    });

    testWidgets('a NaN timer picker item extent lays out at the default extent',
        (tester) async {
      await _pump(
        tester,
        '''
import restage.core;
import restage.cupertino;
widget Paywall = CupertinoTimerPicker(itemExtent: data.nan);
''',
        data: <String, Object?>{'nan': double.nan},
      );

      expect(tester.takeException(), isNull);
      final viewport = tester.renderObject<RenderListWheelViewport>(
        find.byType(ListWheelViewport).first,
      );
      expect(viewport.itemExtent, 32.0);
      expect(viewport.itemExtent.isFinite, isTrue);
    });

    testWidgets('a legal item extent is honoured exactly', (tester) async {
      await _pump(
        tester,
        '''
import restage.core;
import restage.cupertino;
widget Paywall = CupertinoDatePicker(itemExtent: 48.0);
''',
      );

      expect(tester.takeException(), isNull);
      final viewport = tester.renderObject<RenderListWheelViewport>(
        find.byType(ListWheelViewport).first,
      );
      expect(viewport.itemExtent, 48.0);
    });
  });

  group('an optional Cupertino wheel ratio is repaired', () {
    testWidgets('a NaN squeeze lays out at the default ratio', (tester) async {
      await _pump(
        tester,
        '''
import restage.core;
import restage.cupertino;
widget Paywall = CupertinoPicker(itemExtent: 32.0, squeeze: data.nan,
  children: [Text(text: "one"), Text(text: "two")]);
''',
        data: <String, Object?>{'nan': double.nan},
      );

      // The squeeze scales the visible height, and that height is divided by
      // the item extent during layout, where rounding a non-finite quotient
      // throws.
      expect(tester.takeException(), isNull);
      expect(find.byType(CupertinoPicker), findsOneWidget);
    });

    testWidgets('a legal squeeze is honoured', (tester) async {
      await _pump(
        tester,
        '''
import restage.core;
import restage.cupertino;
widget Paywall = CupertinoPicker(itemExtent: 32.0, squeeze: 1.2,
  children: [Text(text: "one"), Text(text: "two")]);
''',
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(CupertinoPicker), findsOneWidget);
    });
  });
}
