// Transform.rotate's alignment: omitted, explicit null and a value each match
// Flutter's own widget.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';
import 'package:rfw/formats.dart';
import 'package:rfw/rfw.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

const _core = LibraryName(['restage', 'core']);
const _surface = LibraryName(['test', 'rotate']);
const _marker = RfwConstructorPresenceProtocol.markerKey;
const _value = RfwConstructorPresenceProtocol.valueKey;
const _version = RfwConstructorPresenceProtocol.version;

void main() {
  final cases = <(String, String, Widget)>[
    ('omitted', '', Transform.rotate(angle: 0.5)),
    (
      'null',
      'alignment: {"$_marker": $_version},',
      Transform.rotate(angle: 0.5, alignment: null),
    ),
    (
      'concrete',
      'alignment: {"$_marker": $_version, "$_value": {x: 1.0, y: -1.0}},',
      Transform.rotate(angle: 0.5, alignment: const Alignment(1, -1)),
    ),
  ];
  for (final (name, wire, native) in cases) {
    testWidgets('$name alignment matches Transform.rotate', (tester) async {
      final runtime = Runtime()
        ..update(_core, buildCoreWidgetLibrary())
        ..update(_surface, parseLibraryFile('''
          import restage.core;
          widget Surface = TransformRotate(angle: 0.5, $wire
            child: SizedBox(width: 30.0, height: 20.0));
        '''));
      addTearDown(runtime.dispose);
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Column(children: [
          SizedBox(width: 30, height: 20, child: native),
          RemoteWidget(
            runtime: runtime,
            data: DynamicContent(),
            widget: const FullyQualifiedWidgetName(_surface, 'Surface'),
          ),
        ]),
      ));
      final transforms = find.byType(Transform);
      final expected = tester.widget<Transform>(transforms.at(0));
      final delivered = tester.widget<Transform>(transforms.at(1));
      expect(delivered.alignment, expected.alignment);
      expect(delivered.transform, expected.transform);
    });
  }
}
