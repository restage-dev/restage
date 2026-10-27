import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';
import 'package:restage_core/src/runtime/intl_value_operations.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/rfw.dart';
import 'package:rfw/formats.dart' as rfw;

import '../../restage_codegen/test/support/temporal_authoring.dart';

final class _Reader implements ValueReader {
  @override
  Object? read(List<Object> path, ValueType type) =>
      throw StateError('No captures');
  @override
  int length(List<Object> path) => throw StateError('No captures');
}

Map<String, Object?> _fixture() =>
    jsonDecode(File('test/fixtures/temporal_authoring_programs.json')
        .readAsStringSync()) as Map<String, Object?>;
ValueProgram _program(String source) {
  final cases = (_fixture()['cases']! as List).cast<Map<String, Object?>>();
  return ValueProgram.decode(
      jsonEncode(cases.singleWhere((c) => c['source'] == source)['program']),
      operations: kNativeIntlValueOperations);
}

Map<String, String> _collectionFixture() =>
    (jsonDecode(File('test/fixtures/temporal_collection_programs.json')
            .readAsStringSync()) as Map)
        .cast<String, String>();

void main() {
  for (final key in [
    'strings',
    'records',
    'aliases',
    'colors',
    'helper',
    'sort',
    'lazy'
  ]) {
    testWidgets(
        'registered native clock collection retains lexical values: $key',
        (tester) async {
      final runtime = Runtime()
        ..update(
            const LibraryName(['restage', 'core']), buildCoreWidgetLibrary())
        ..update(const LibraryName(['test']),
            rfw.parseLibraryFile(_collectionFixture()[key]!));
      addTearDown(runtime.dispose);
      final outerSamples = <int>[];
      for (final width in [100.0, 200.0]) {
        final before = DateTime.now().microsecondsSinceEpoch;
        await tester.pumpWidget(Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
                child: SizedBox(
                    width: width,
                    child: RemoteWidget(
                        runtime: runtime,
                        data: DynamicContent(),
                        widget: const FullyQualifiedWidgetName(
                            LibraryName(['test']), 'Root'))))));
        final after = DateTime.now().microsecondsSinceEpoch;
        expect(tester.takeException(), isNull);
        final labels = tester
            .widgetList<Text>(find.byType(Text))
            .map((widget) => widget.data!)
            .toList();
        if (key == 'sort') {
          expect(labels, ['1,2,3|1']);
        } else if (key == 'colors' || key == 'helper') {
          expect(labels, hasLength(2));
          final components =
              labels.map((label) => label.split(':').last.split('|')).toList();
          expect(components.map((parts) => parts.first).toSet(), hasLength(1));
          final color = double.parse(components.first.first);
          for (final text in tester.widgetList<Text>(find.byType(Text))) {
            expect(text.style!.color.runtimeType, Color);
            expect(text.style!.color!.b, color);
          }
          if (key == 'colors') {
            final containers =
                tester.widgetList<Container>(find.byType(Container));
            expect(containers, hasLength(2));
            for (final container in containers) {
              expect((container.decoration! as BoxDecoration).color,
                  same(material.Colors.blue));
            }
          } else {
            expect(components.map((parts) => parts[1]).toSet(), hasLength(1));
            final sample = int.parse(components.first[1]);
            expect(sample, inInclusiveRange(before, after));
            outerSamples.add(sample);
          }
        } else if (key == 'lazy') {
          expect(labels, hasLength(1));
          final parts = labels.single.split('|');
          expect(parts.take(2), ['3', '0']);
          expect(int.parse(parts[2]),
              inInclusiveRange(before * 2 + 10, after * 2 + 10));
          expect(parts[3].split(','), hasLength(2));
          for (final value in parts[3].split(',')) {
            expect(int.parse(value),
                inInclusiveRange(before * 2 + 20, after * 2 + 20));
          }
        } else {
          final rows = key == 'strings' ? labels.take(3).toList() : labels;
          expect(labels, hasLength(key == 'strings' ? 4 : 2));
          final parsed = rows
              .map((label) =>
                  label.split(':').last.split('|').map(int.parse).toList())
              .toList();
          expect(parsed.map((parts) => parts[0]).toSet(), hasLength(1));
          if (key == 'aliases') {
            for (var index = 0; index < 4; index++) {
              expect(parsed.map((parts) => parts[index]).toSet(), hasLength(1));
              expect(parsed.first[index], inInclusiveRange(before, after));
            }
          }
          for (final parts in parsed) {
            expect(parts[0], inInclusiveRange(before, after));
            expect(parts[1], inInclusiveRange(parts[0], after));
            if (key != 'aliases') expect(parts[1], parts[2]);
          }
          if (key == 'strings') {
            expect(labels.last, 'visited3');
            expect(parsed.map((parts) => parts.last), [1, 2, 3]);
          }
          outerSamples.add(parsed.first[0]);
        }
      }
      if (key != 'lazy' && key != 'colors' && key != 'sort')
        expect(outerSamples[1], greaterThan(outerSamples[0]));
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  test(
      'original temporal source programs match native Dart microsecond semantics',
      () {
    for (final (source, native) in temporalCases()) {
      expect(
          ValueEvaluator(_program(source),
                  captures: _Reader(),
                  parameters: {},
                  operations: kNativeIntlValueOperations)
              .evaluate(),
          native(),
          reason: source);
    }
  });
  test('clock composes with actual native DateFormat and countdown difference',
      () {
    final sample = DateTime.utc(2027, 3, 4, 5, 6, 7, 123, 456);
    var reads = 0;
    final operations = {
      ...kNativeIntlValueOperations,
      'clock.now': ClockNowOperation(read: () {
        reads++;
        return sample;
      })
    };
    expect(
        ValueEvaluator(_program(clockFormatSource),
                captures: _Reader(), parameters: {}, operations: operations)
            .evaluate(),
        formattedClock(sample));
    expect(
        ValueEvaluator(_program(countdownSource),
                captures: _Reader(), parameters: {}, operations: operations)
            .evaluate(),
        '${DateTime.utc(2030).difference(sample).inSeconds}');
    expect(reads, 2);
  });
  test(
      'authored GridView callback takes one new sample per demanded item invocation',
      () {
    final root = rfw
        .parseLibraryFile(
            'import restage.core;widget Root=${_fixture()['grid']};')
        .widgets
        .single
        .root as rfw.ConstructorCall;
    final callback = root.arguments['itemBuilder']! as rfw.ConstructorCall;
    final program = BuilderProgram.decode(
        callback.arguments['program']! as String,
        operations: kNativeIntlValueOperations);
    var reads = 0;
    final operations = {
      ...kNativeIntlValueOperations,
      'clock.now': ClockNowOperation(
          read: () => DateTime.fromMicrosecondsSinceEpoch(++reads))
    };
    expect(reads, 0);
    for (final index in [0, 1, 0]) {
      final result = program.invoke(
          captures: _Reader(),
          parameters: {'arg1': index},
          operations: operations);
      expect(result.values.values, contains('$index:$reads|$reads'));
    }
    expect(reads, 3);
  });

  testWidgets(
      'authored native LayoutBuilder reads a fresh clock each rebuild and reuses its local',
      (tester) async {
    final runtime = Runtime()
      ..update(const LibraryName(['restage', 'core']), buildCoreWidgetLibrary())
      ..update(
          const LibraryName(['test']),
          rfw.parseLibraryFile(
              'import restage.core;widget Root=${_fixture()['builder']};'));
    final samples = <int>[];
    for (final width in [100.0, 200.0]) {
      final before = DateTime.now();
      await tester.pumpWidget(Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
              child: SizedBox(
                  width: width,
                  child: RemoteWidget(
                      runtime: runtime,
                      data: DynamicContent(),
                      widget: const FullyQualifiedWidgetName(
                          LibraryName(['test']), 'Root'))))));
      final after = DateTime.now();
      final text = tester.widget<Text>(find.byType(Text)).data!;
      final parts = text.split('|').map(int.parse).toList();
      expect(parts[0], parts[1]);
      expect(
          parts[0],
          inInclusiveRange(
              before.microsecondsSinceEpoch, after.microsecondsSinceEpoch));
      expect(tester.takeException(), isNull);
      samples.add(parts[0]);
    }
    expect(samples[1], greaterThan(samples[0]));
  });
  testWidgets(
      'authored native GridView itemBuilder reads and reuses one clock per demanded item',
      (tester) async {
    final runtime = Runtime()
      ..update(const LibraryName(['restage', 'core']), buildCoreWidgetLibrary())
      ..update(
          const LibraryName(['test']),
          rfw.parseLibraryFile(
              'import restage.core;widget Root=${_fixture()['grid']};'));
    final before = DateTime.now();
    await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
            child: SizedBox(
                width: 300,
                height: 600,
                child: RemoteWidget(
                    runtime: runtime,
                    data: DynamicContent(),
                    widget: const FullyQualifiedWidgetName(
                        LibraryName(['test']), 'Root'))))));
    final after = DateTime.now();
    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((widget) => widget.data!)
        .toList();
    expect(texts.length, greaterThanOrEqualTo(2));
    for (final text in texts) {
      final parts = text.split(':').last.split('|').map(int.parse).toList();
      expect(parts[0], parts[1]);
      expect(
          parts[0],
          inInclusiveRange(
              before.microsecondsSinceEpoch, after.microsecondsSinceEpoch));
    }
    expect(tester.takeException(), isNull);
  });
}
