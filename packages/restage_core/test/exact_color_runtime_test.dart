import 'dart:ui' show ColorSpace;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';
import 'package:rfw/rfw.dart';
import 'package:restage_shared/restage_shared.dart'
    show canonicalMaterialColorNames;

void main() {
  test('every canonical Material swatch retains native identity and shades',
      () {
    const expected = <String, ColorSwatch<int>>{
      'red': Colors.red,
      'redAccent': Colors.redAccent,
      'pink': Colors.pink,
      'pinkAccent': Colors.pinkAccent,
      'purple': Colors.purple,
      'purpleAccent': Colors.purpleAccent,
      'deepPurple': Colors.deepPurple,
      'deepPurpleAccent': Colors.deepPurpleAccent,
      'indigo': Colors.indigo,
      'indigoAccent': Colors.indigoAccent,
      'blue': Colors.blue,
      'blueAccent': Colors.blueAccent,
      'lightBlue': Colors.lightBlue,
      'lightBlueAccent': Colors.lightBlueAccent,
      'cyan': Colors.cyan,
      'cyanAccent': Colors.cyanAccent,
      'teal': Colors.teal,
      'tealAccent': Colors.tealAccent,
      'green': Colors.green,
      'greenAccent': Colors.greenAccent,
      'lightGreen': Colors.lightGreen,
      'lightGreenAccent': Colors.lightGreenAccent,
      'lime': Colors.lime,
      'limeAccent': Colors.limeAccent,
      'yellow': Colors.yellow,
      'yellowAccent': Colors.yellowAccent,
      'amber': Colors.amber,
      'amberAccent': Colors.amberAccent,
      'orange': Colors.orange,
      'orangeAccent': Colors.orangeAccent,
      'deepOrange': Colors.deepOrange,
      'deepOrangeAccent': Colors.deepOrangeAccent,
      'brown': Colors.brown,
      'grey': Colors.grey,
      'blueGrey': Colors.blueGrey,
    };
    expect(expected.keys.toSet(), canonicalMaterialColorNames);
    for (final entry in expected.entries) {
      final color = entry.value;
      final actual = RestageDecoders.color(
          _ColorSource({
            'material': entry.key,
            'a': color.a,
            'r': color.r,
            'g': color.g,
            'b': color.b,
            'colorSpace': color.colorSpace.name,
          }),
          const [])!;
      expect(actual.runtimeType, color.runtimeType, reason: entry.key);
      expect(actual, same(color), reason: entry.key);
      expect(actual == color && color == actual, isTrue, reason: entry.key);
      expect(actual.hashCode, color.hashCode, reason: entry.key);
      for (final shade in [
        50,
        100,
        200,
        300,
        400,
        500,
        600,
        700,
        800,
        900,
        777
      ]) {
        expect((actual as ColorSwatch<int>)[shade], same(color[shade]),
            reason: '${entry.key}[$shade]');
      }
    }
  });

  test('unknown canonical colors refuse instead of falling back to channels',
      () {
    for (final token in ['custom', 123, false]) {
      expect(
          () => RestageDecoders.color(
              _ColorSource({
                'material': token,
                'a': 1.0,
                'r': 0.0,
                'g': 0.0,
                'b': 0.0,
                'colorSpace': 'sRGB',
              }),
              const []),
          throwsFormatException);
    }
  });

  test('base colors retain exact channels and color space', () {
    const expected = Color.from(
        alpha: .75,
        red: 1e-7,
        green: .4,
        blue: .8,
        colorSpace: ColorSpace.displayP3);
    final actual = RestageDecoders.color(
        const _ColorSource({
          'material': '',
          'a': .75,
          'r': 1e-7,
          'g': .4,
          'b': .8,
          'colorSpace': 'displayP3',
        }),
        const []);
    expect(actual.runtimeType, expected.runtimeType);
    expect(actual, expected);
  });
}

final class _ColorSource implements DataSource {
  const _ColorSource(this.color);
  final Map<String, Object?> color;

  @override
  bool isMap(List<Object> path) => path.isEmpty;

  @override
  T? v<T extends Object>(List<Object> path) {
    final value = path.length == 1 ? color[path.single] : null;
    return value is T ? value : null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
