import 'dart:convert';
import 'dart:io';

import '../shared_resolvers.dart';
import 'collection_authoring.dart';

const temporalCollectionSources = <String, String>{
  'strings': r'''
import 'package:flutter/widgets.dart';
Widget rowLabel(String label, DateTime outer, int visited) {
  final itemNow = DateTime.now();
  return Text('$label:${outer.microsecondsSinceEpoch}|${itemNow.microsecondsSinceEpoch}|${itemNow.microsecondsSinceEpoch}|$visited');
}
Widget x() => LayoutBuilder(builder: (context, constraints) {
  final outer = DateTime.now();
  var visited = 0;
  final rows = ['one', 'two', 'three'].where((row) { visited++; return true; });
  return Column(children: [
    if (false) Text('${DateTime.now().microsecondsSinceEpoch}'),
    for (final row in rows) rowLabel(row, outer, visited),
    Text('visited$visited'),
  ]);
});
''',
  'records': r'''
import 'package:flutter/widgets.dart';
Widget rowLabel(DateTime row, DateTime outer) {
  final itemNow = DateTime.now();
  return Text('${row.year}:${outer.microsecondsSinceEpoch}|${itemNow.microsecondsSinceEpoch}|${itemNow.microsecondsSinceEpoch}');
}
Widget x() => LayoutBuilder(builder: (context, constraints) {
  final outer = DateTime.now();
  final rows = [DateTime.utc(2024), DateTime.utc(2025)].where((row) => true);
  return Column(children: [for (final row in rows) rowLabel(row, outer)]);
});
''',
  'aliases': r'''
import 'package:flutter/widgets.dart';
Widget x() => LayoutBuilder(builder: (context, constraints) {
  final sampled = DateTime.now();
  final alias = sampled;
  final micros = DateTime.now().microsecondsSinceEpoch;
  final primitiveAlias = micros;
  final samples = [DateTime.now()];
  final sampleAlias = samples;
  final duration = Duration(microseconds: DateTime.now().microsecondsSinceEpoch);
  final durationAlias = duration;
  return Column(children: [
    for (final row in ['one', 'two'].where((row) => true))
      Text('$row:${alias.microsecondsSinceEpoch}|$primitiveAlias|${sampleAlias.first.microsecondsSinceEpoch}|${durationAlias.inMicroseconds}'),
  ]);
});
''',
  'colors': r'''
import 'package:flutter/material.dart';
Widget x() => LayoutBuilder(builder: (context, constraints) {
  final color = Color(DateTime.now().microsecond);
  final alias = color;
  final material = Colors.blue;
  final materialAlias = material;
  return Column(children: [
    for (final row in ['one', 'two'].where((row) => true))
      Container(color: materialAlias, child: Text('$row:${alias.b}', style: TextStyle(color: alias))),
  ]);
});
''',
  'helper': r'''
import 'package:flutter/widgets.dart';
Widget sampleRows(Color color, DateTime stamp) {
  final alias = color;
  final now = stamp;
  return LayoutBuilder(builder: (context, constraints) => Column(children: [
    for (final row in ['one', 'two'].where((row) => true))
      Text('$row:${alias.b}|${now.microsecondsSinceEpoch}', style: TextStyle(color: alias)),
  ]));
}
Widget x() => LayoutBuilder(builder: (context, constraints) => sampleRows(Color(DateTime.now().microsecond), DateTime.now()));
''',
  'sort': r'''
import 'package:flutter/widgets.dart';
Widget x() => LayoutBuilder(builder: (context, constraints) {
  final sorted = [3, 1, 2];
  final alias = sorted;
  final result = [0].map((item) { alias.sort(); return sorted.first; }).toList();
  return Text('${sorted.join(",")}|${result.single}');
});
''',
  'lazy': r'''
import 'package:flutter/widgets.dart';
Widget x() => LayoutBuilder(builder: (context, constraints) {
  final outer = DateTime.now();
  var offset = 0;
  final items = [1, 2, 3].map((item) => outer.microsecondsSinceEpoch + DateTime.now().microsecondsSinceEpoch + offset);
  final length = items.length;
  final ignored = false ? DateTime.now().microsecondsSinceEpoch : 0;
  offset = 10;
  final first = items.take(1).toList();
  offset = 20;
  final second = items.take(2).toList();
  return Text('$length|$ignored|${first.join(",")}|${second.join(",")}');
});
''',
};

Future<String> compileTemporalCollectionFixture() async {
  final cases = <String, String>{};
  for (final entry in temporalCollectionSources.entries) {
    final (source, _) =
        await compileCollectionAuthoring(authoredSource: entry.value);
    cases[entry.key] = source;
  }
  return '${const JsonEncoder.withIndent('  ').convert(cases)}\n';
}

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1)
    throw ArgumentError('Expected temporal collection fixture output path');
  try {
    File(arguments.single)
        .writeAsStringSync(await compileTemporalCollectionFixture());
  } finally {
    sharedResolvers.reset();
  }
}
