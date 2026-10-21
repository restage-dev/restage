import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';
import 'package:rfw/formats.dart';
import 'package:rfw/rfw.dart';

const LibraryName _coreLibrary = LibraryName(<String>['restage', 'core']);
const LibraryName _rootLibrary = LibraryName(<String>['restage', 'paywall']);

void main() {
  for (final flex in ['Row', 'Column']) {
    testWidgets('$flex aligns on its textBaseline', (tester) async {
      final runtime = Runtime()
        ..update(_coreLibrary, buildCoreWidgetLibrary())
        ..update(
          _rootLibrary,
          parseLibraryFile('''
import restage.core;
widget Paywall = $flex(crossAxisAlignment: "baseline", textBaseline: "alphabetic", children: [Text(text: "a")]);
'''),
        );
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: RemoteWidget(
            runtime: runtime,
            data: DynamicContent(),
            widget: const FullyQualifiedWidgetName(_rootLibrary, 'Paywall'),
            onEvent: (_, __) {},
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      final render = tester.renderObject<RenderFlex>(
        find.byWidgetPredicate((widget) => widget is Flex),
      );
      expect(render.crossAxisAlignment, CrossAxisAlignment.baseline);
      expect(render.textBaseline, TextBaseline.alphabetic);
    });
  }
}
