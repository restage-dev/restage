import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  const flutterWidgetsImport = "import 'package:flutter/widgets.dart';";

  Future<PropertyType?> infer(
    String dartType, {
    String extras = '',
    String rootPackage = 'restage_codegen',
  }) {
    return inferTypeFromSource(
      '''
      $extras
      class T {
        final $dartType x;
        T(this.x);
      }
    ''',
      fieldName: 'x',
      rootPackage: rootPackage,
    );
  }

  test('the real Flutter Widget maps to PropertyType.widget', () async {
    expect(
      await infer(
        'Widget',
        extras: flutterWidgetsImport,
        rootPackage: 'apps_examples',
      ),
      PropertyType.widget,
    );
  });

  test('a List of real Flutter Widgets maps to widgetList', () async {
    expect(
      await infer(
        'List<Widget>',
        extras: flutterWidgetsImport,
        rootPackage: 'apps_examples',
      ),
      PropertyType.widgetList,
    );
  });

  test('a List of customer Widgets is not classified as widgetList', () async {
    expect(
      await infer('List<Widget>', extras: 'class Widget {}'),
      isNull,
    );
  });

  test('the real Flutter Color maps to PropertyType.color', () async {
    expect(
      await infer(
        'Color',
        extras: flutterWidgetsImport,
        rootPackage: 'apps_examples',
      ),
      PropertyType.color,
    );
  });

  test(
    'a customer class named Color is not classified as the Flutter color type',
    () async {
      expect(await infer('Color', extras: 'class Color {}'), isNull);
    },
  );

  test('the real Flutter edge-insets types map to edgeInsets', () async {
    for (final type in const [
      'EdgeInsets',
      'EdgeInsetsGeometry',
      'EdgeInsetsDirectional',
    ]) {
      expect(
        await infer(
          type,
          extras: flutterWidgetsImport,
          rootPackage: 'apps_examples',
        ),
        PropertyType.edgeInsets,
        reason: '$type should map to edgeInsets',
      );
    }
  });

  test(
    'a customer class named EdgeInsets is not classified as Flutter insets',
    () async {
      expect(
        await infer('EdgeInsets', extras: 'class EdgeInsets {}'),
        isNull,
      );
    },
  );

  test('the real Flutter alignment types map to alignment', () async {
    for (final type in const [
      'Alignment',
      'AlignmentGeometry',
      'AlignmentDirectional',
    ]) {
      expect(
        await infer(
          type,
          extras: flutterWidgetsImport,
          rootPackage: 'apps_examples',
        ),
        PropertyType.alignment,
        reason: '$type should map to alignment',
      );
    }
  });

  test('the real Flutter Offset maps to PropertyType.offset', () async {
    expect(
      await infer(
        'Offset',
        extras: flutterWidgetsImport,
        rootPackage: 'apps_examples',
      ),
      PropertyType.offset,
    );
  });

  test('the real Flutter FontWeight maps to fontWeight', () async {
    expect(
      await infer(
        'FontWeight',
        extras: flutterWidgetsImport,
        rootPackage: 'apps_examples',
      ),
      PropertyType.fontWeight,
    );
  });

  test('Duration -> PropertyType.duration', () async {
    expect(await infer('Duration'), PropertyType.duration);
  });

  test('the real Flutter Curve maps to PropertyType.curve', () async {
    expect(
      await infer(
        'Curve',
        extras: flutterWidgetsImport,
        rootPackage: 'apps_examples',
      ),
      PropertyType.curve,
    );
  });

  test(
    'a customer class named Curve is not classified as the Flutter curve type',
    () async {
      expect(await infer('Curve', extras: 'class Curve {}'), isNull);
    },
  );

  test('bool -> PropertyType.boolean', () async {
    expect(await infer('bool'), PropertyType.boolean);
  });

  test('int -> PropertyType.integer', () async {
    expect(await infer('int'), PropertyType.integer);
  });

  test('double -> PropertyType.real', () async {
    expect(await infer('double'), PropertyType.real);
  });

  test('String -> PropertyType.string', () async {
    expect(await infer('String'), PropertyType.string);
  });

  test('VoidCallback -> PropertyType.event', () async {
    expect(
      await infer(
        'VoidCallback?',
        extras: flutterWidgetsImport,
        rootPackage: 'apps_examples',
      ),
      PropertyType.event,
    );
  });

  test('user-defined enum -> PropertyType.enumValue', () async {
    expect(
      await infer('Mode', extras: 'enum Mode { a, b }'),
      PropertyType.enumValue,
    );
  });

  test('a customer enum named Color still maps to enumValue', () async {
    expect(
      await infer('Color', extras: 'enum Color { red, blue }'),
      PropertyType.enumValue,
    );
  });

  test('nullable real Flutter Color still maps to color', () async {
    expect(
      await infer(
        'Color?',
        extras: flutterWidgetsImport,
        rootPackage: 'apps_examples',
      ),
      PropertyType.color,
    );
  });

  test('user-defined non-enum class -> null (unsupported)', () async {
    expect(
      await infer('CustomType', extras: 'class CustomType {}'),
      isNull,
    );
  });
}
