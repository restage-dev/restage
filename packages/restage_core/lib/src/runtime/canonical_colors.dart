import 'package:flutter/material.dart' show Color, Colors;

/// Installed canonical Material swatches accepted by the color decoder.
const canonicalMaterialColors = <String, Color>{
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

/// Preserves a canonical swatch when projecting a native color.
String canonicalMaterialColorName(Color color) {
  for (final entry in canonicalMaterialColors.entries) {
    if (identical(color, entry.value)) return entry.key;
  }
  return '';
}
