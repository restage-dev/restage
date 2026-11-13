import 'package:a2ui_core/a2ui_core.dart';
import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:json_schema_builder/json_schema_builder.dart';

import 'generated/encoded_property_catalog.g.dart' as encoded;
import 'generated/encoded_property_fixture.dart' as fixture;

void main() {
  for (final source in [
    7,
    const {'@path': '/value'},
    const {'@call': 'currentValue'},
  ]) {
    testWidgets('encoded constructor inputs render and write $source', (
      tester,
    ) async {
      final value = signal<Object?>(7);
      final catalog = CatalogImplementation(
        id: 'restage:encoded-property-runtime',
        protocolVersion: A2uiProtocolVersion.v1_0,
        components: encoded.buildRestageCatalogItems(),
        definitions: encoded.buildRestageCatalogDefinitions(),
        functions: [_EncodedValueFunction(value)],
      );
      final processor = MessageProcessor<ComponentImplementation>(
        catalogs: [catalog],
        defaultVersion: A2uiProtocolVersion.v1_0,
        validationConfig: ValidationConfig.strict,
      );
      addTearDown(processor.dispose);
      const dollarKey = 'props_encoded_002400760061006c00750065';
      const collisionKey =
          'props_encoded_0065006e0063006f006400650064005f'
          '0030003000320034003000300037003600300030003600310030003000360063'
          '00300030003700350030003000360035';
      Map<String, Object?> component(Object? input) => {
        'id': 'root',
        'component': 'EncodedPropertyProbe',
        dollarKey: input,
        collisionKey: 'collision value',
        'props_value': 'ordinary value',
        'props_details': {r'$value': 'business value'},
      };
      processor.processMessages({
        'version': '1.0',
        'createSurface': {
          'surfaceId': 's',
          'catalogId': catalog.id,
          'dataModel': {'value': 7},
          'components': [component(source)],
        },
      });
      final surface = processor.model.getSurface('s')!;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: A2uiSurface(surface: surface)),
        ),
      );
      final widget = tester.widget<fixture.EncodedPropertyProbe>(
        find.byType(fixture.EncodedPropertyProbe),
      );
      expect(widget.$value, 7);
      expect(widget.encoded_002400760061006c00750065, 'collision value');
      expect(widget.value, 'ordinary value');
      expect(widget.details.$value, 'business value');
      for (final text in [
        'dollar:7',
        'collision:collision value',
        'ordinary:ordinary value',
        'nested:business value',
      ]) {
        expect(find.text(text), findsOneWidget);
      }
      await tester.tap(find.byKey(const ValueKey('encoded-write')));
      await tester.pump();
      expect(find.text('dollar:41'), findsOneWidget);
      if (source is Map && source.containsKey('@path')) {
        expect(surface.dataModel.get('/value'), 41);
        surface.dataModel.set('/value', 12);
        await tester.pump();
        expect(find.text('dollar:12'), findsOneWidget);
      } else {
        expect(surface.dataModel.get('/restage_root/$dollarKey'), 41);
        value.value = 12;
        processor.processMessages({
          'version': '1.0',
          'updateComponents': {
            'surfaceId': 's',
            'components': [component(source is Map ? source : 13)],
          },
        });
        await tester.pump();
        expect(find.text('dollar:41'), findsOneWidget);
      }
      expect(find.text('collision:collision value'), findsOneWidget);
      expect(find.text('ordinary:ordinary value'), findsOneWidget);
      expect(find.text('nested:business value'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}

final class _EncodedValueFunction extends FunctionImplementation {
  _EncodedValueFunction(this.value)
    : super(name: 'currentValue', argumentSchema: S.object());

  final Signal<Object?> value;

  @override
  Object? execute(
    Map<String, dynamic> args,
    DataContext context, [
    CancellationSignal? cancellationSignal,
  ]) => value;
}
