import 'dart:io';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';
import 'package:rfw/formats.dart';
import 'package:rfw/rfw.dart';

const _consumer = LibraryName(['test', 'insets']);
const _surface = LibraryName(['test', 'surface']);
const _core = LibraryName(['restage', 'core']);
const _nativeValues = <String, EdgeInsetsGeometry>{
  'PhysicalNegative': EdgeInsets.only(left: -7),
  'LogicalNegative': EdgeInsetsDirectional.only(start: -7),
  'PhysicalOverflow': EdgeInsets.fromLTRB(1.7e308, 1.7e308, 1.7e308, 1.7e308),
  'LogicalOverflow':
      EdgeInsetsDirectional.fromSTEB(1.7e308, 1.7e308, 1.7e308, 1.7e308),
};

Runtime _runtime(RemoteWidgetLibrary library) => Runtime()
  ..update(
      _consumer,
      LocalWidgetLibrary({
        'InsetReadout': (context, source) => InsetReadout(
              insets: RestageDecoders.edgeInsets(source, ['insets'])!,
              label: source.v<String>(['label'])!,
            ),
      }))
  ..update(_surface, library);

class InsetReadout extends StatelessWidget {
  const InsetReadout({required this.insets, required this.label, super.key});
  final EdgeInsetsGeometry insets;
  final String label;

  @override
  Widget build(BuildContext context) {
    final value = insets.resolve(Directionality.of(context));
    return Text(
        '$label:${insets.runtimeType}:${value.left},${value.top},${value.right},${value.bottom}');
  }
}

void main() {
  testWidgets('compiled explicit maps match native generic inset consumers',
      (tester) async {
    final runtime = _runtime(parseLibraryFile(
      File('test/fixtures/explicit_inset_values.rfwtxt').readAsStringSync(),
    ));
    addTearDown(runtime.dispose);
    for (final scenario in _nativeValues.entries) {
      for (final direction in TextDirection.values) {
        await tester.pumpWidget(Directionality(
          textDirection: direction,
          child: Column(children: [
            InsetReadout(insets: scenario.value, label: scenario.key),
            RemoteWidget(
              runtime: runtime,
              data: DynamicContent(),
              widget: FullyQualifiedWidgetName(_surface, scenario.key),
            ),
          ]),
        ));
        final readouts =
            tester.widgetList<InsetReadout>(find.byType(InsetReadout)).toList();
        expect(readouts, hasLength(2));
        expect(readouts.last.insets.runtimeType,
            readouts.first.insets.runtimeType);
        expect(readouts.last.insets, readouts.first.insets);
        final expected = scenario.value.resolve(direction);
        expect(readouts.last.insets.resolve(direction), expected);
        final text =
            '${scenario.key}:${scenario.value.runtimeType}:${expected.left},${expected.top},${expected.right},${expected.bottom}';
        expect(find.text(text), findsNWidgets(2));
        if (scenario.key.endsWith('Overflow')) {
          expect(expected.left.isFinite && expected.right.isFinite, isTrue);
          expect(expected.horizontal.isInfinite && expected.vertical.isInfinite,
              isTrue);
        }
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets('legacy lists retain directional semantics and axis repairs',
      (tester) async {
    final runtime = _runtime(parseLibraryFile('''
import test.insets;
widget Negative = InsetReadout(insets: [-7.0, 2.0, 11.0, 3.0], label: "legacy");
widget Overflow = InsetReadout(insets: [1.7e308, 2.0, 1.7e308, 3.0], label: "legacy");
'''));
    addTearDown(runtime.dispose);
    for (final scenario in <String, EdgeInsetsDirectional>{
      'Negative': const EdgeInsetsDirectional.fromSTEB(0, 2, 11, 3),
      'Overflow': const EdgeInsetsDirectional.fromSTEB(0, 2, 0, 3),
    }.entries) {
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.rtl,
        child: RemoteWidget(
            runtime: runtime,
            data: DynamicContent(),
            widget: FullyQualifiedWidgetName(_surface, scenario.key)),
      ));
      expect(tester.widget<InsetReadout>(find.byType(InsetReadout)).insets,
          scenario.value);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('Padding keeps its destination repair for exact map values',
      (tester) async {
    final runtime = Runtime()
      ..update(_core, buildCoreWidgetLibrary())
      ..update(_surface, parseLibraryFile('''
import restage.core;
widget Surface = Padding(padding: data.insets, child: SizedBox(width: 10.0, height: 10.0));
'''));
    addTearDown(runtime.dispose);
    final data = DynamicContent();
    for (final scenario in _nativeValues.entries) {
      final value = scenario.value;
      final fields = switch (value) {
        EdgeInsets() => {
            'left': value.left,
            'top': value.top,
            'right': value.right,
            'bottom': value.bottom
          },
        EdgeInsetsDirectional() => {
            'start': value.start,
            'top': value.top,
            'end': value.end,
            'bottom': value.bottom
          },
        _ => throw StateError('Expected a concrete inset value.'),
      };
      data.update('insets', fields);
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
            child: RemoteWidget(
                runtime: runtime,
                data: data,
                widget: const FullyQualifiedWidgetName(_surface, 'Surface'))),
      ));
      final padding = find.byType(RestagePadding);
      expect(tester.widget<RestagePadding>(padding).padding, value);
      final render = tester.renderObject<RenderPadding>(padding);
      expect(render.padding.resolve(TextDirection.ltr), EdgeInsets.zero);
      expect(render.size, const Size(10, 10));
      expect(tester.takeException(), isNull);
    }
  });
}
