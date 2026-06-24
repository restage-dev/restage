import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  // Stub class declarations matching Flutter's display names — keeps the
  // codegen package free of a Flutter dependency while still verifying
  // the type-inference mappings.
  const flutterStubs = '''
    class Widget {}
    class Color {}
    class EdgeInsetsGeometry {}
    class EdgeInsets extends EdgeInsetsGeometry {}
    class EdgeInsetsDirectional extends EdgeInsetsGeometry {}
    class AlignmentGeometry {}
    class Alignment extends AlignmentGeometry {}
    class AlignmentDirectional extends AlignmentGeometry {}
    class Curve {}
    class FontWeight {}
    typedef VoidCallback = void Function();
  ''';

  Future<PropertyType?> infer(String dartType, {String extras = ''}) {
    return inferTypeFromSource(
      '''
      $extras
      class T {
        final $dartType x;
        T(this.x);
      }
    ''',
      fieldName: 'x',
    );
  }

  test('Widget -> PropertyType.widget', () async {
    expect(await infer('Widget', extras: flutterStubs), PropertyType.widget);
  });

  test('List<Widget> -> PropertyType.widgetList', () async {
    expect(
      await infer('List<Widget>', extras: flutterStubs),
      PropertyType.widgetList,
    );
  });

  test('Color -> PropertyType.color', () async {
    expect(await infer('Color', extras: flutterStubs), PropertyType.color);
  });

  test(
      'EdgeInsets / EdgeInsetsGeometry / EdgeInsetsDirectional -> '
      'PropertyType.edgeInsets', () async {
    for (final t in const [
      'EdgeInsets',
      'EdgeInsetsGeometry',
      'EdgeInsetsDirectional',
    ]) {
      expect(
        await infer(t, extras: flutterStubs),
        PropertyType.edgeInsets,
        reason: '$t should map to edgeInsets',
      );
    }
  });

  test(
      'Alignment / AlignmentGeometry / AlignmentDirectional -> '
      'PropertyType.alignment', () async {
    for (final t in const [
      'Alignment',
      'AlignmentGeometry',
      'AlignmentDirectional',
    ]) {
      expect(
        await infer(t, extras: flutterStubs),
        PropertyType.alignment,
        reason: '$t should map to alignment',
      );
    }
  });

  test('FontWeight -> PropertyType.fontWeight', () async {
    expect(
      await infer('FontWeight', extras: flutterStubs),
      PropertyType.fontWeight,
    );
  });

  test('Duration -> PropertyType.duration', () async {
    // `Duration` is a `dart:core` type — no stub class needed in the
    // input source. `inferPropertyType` matches by display name after
    // nullability strip.
    expect(await infer('Duration'), PropertyType.duration);
  });

  test('Curve -> PropertyType.curve', () async {
    expect(await infer('Curve', extras: flutterStubs), PropertyType.curve);
  });

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
      await infer('VoidCallback?', extras: flutterStubs),
      PropertyType.event,
    );
  });

  test('user-defined enum -> PropertyType.enumValue', () async {
    expect(
      await infer('Mode', extras: 'enum Mode { a, b }'),
      PropertyType.enumValue,
    );
  });

  test('nullable Color -> PropertyType.color (nullability stripped)', () async {
    expect(await infer('Color?', extras: flutterStubs), PropertyType.color);
  });

  test('user-defined non-enum class -> null (unsupported)', () async {
    expect(
      await infer('CustomType', extras: 'class CustomType {}'),
      isNull,
    );
  });
}
