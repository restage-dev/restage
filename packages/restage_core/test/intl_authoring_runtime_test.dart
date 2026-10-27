import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' as i;
import 'package:restage_core/src/runtime/intl_value_operations.dart';
import 'package:restage_shared/restage_shared.dart';

import '../../restage_codegen/test/support/intl_format_authoring.dart';

final class _NoFormattingCaptures implements ValueReader {
  @override
  Object? read(List<Object> path, ValueType type) =>
      throw StateError('Unexpected formatting capture');
  @override
  int length(List<Object> path) =>
      throw StateError('Unexpected formatting collection');
}

Object? _formattingResult(Object? Function() compute) {
  try {
    return compute();
  } on Object catch (error) {
    return (error.runtimeType, error.toString());
  }
}

List<ValueProgram> _fixturePrograms(List<String> sources) {
  final fixture = jsonDecode(
          File('test/fixtures/intl_authoring_programs.json').readAsStringSync())
      as Map<String, Object?>;
  final cases = (fixture['cases']! as List).cast<Map<String, Object?>>();
  return [
    for (final source in sources)
      ValueProgram.decode(
          jsonEncode(cases
              .singleWhere((entry) => entry['source'] == source)['program']),
          operations: kIntlValueOperations),
  ];
}

void main() {
  test(
      'authored mixed Intl arguments preserve lexical evaluation and map order',
      () {
    final cases = intlArgumentCases();
    final programs = _fixturePrograms(cases.map((c) => c.$1).toList());
    for (var index = 0; index < cases.length; index++) {
      expect(
          _formattingResult(() => ValueEvaluator(programs[index],
                  captures: _NoFormattingCaptures(),
                  parameters: const {},
                  operations: kNativeIntlValueOperations)
              .evaluate()),
          _formattingResult(cases[index].$2),
          reason: cases[index].$1);
    }
  });

  test(
      'authored epoch constructors bind named-first and positional-first forms',
      () {
    final cases = intlEpochCases();
    final programs = _fixturePrograms([
      for (final (source, _) in cases)
        "i.DateFormat.yMd('en_US').format($source)",
      "i.DateFormat.yMd('en_US').format(DateTime.fromMicrosecondsSinceEpoch(isUtc: i.DateFormat.yMd('unknown_locale').format(DateTime.utc(2024)) == '', 1 ~/ 0))",
    ]);
    for (var index = 0; index < cases.length; index++) {
      final program = programs[index];
      final evaluator = ValueEvaluator(program,
          captures: _NoFormattingCaptures(),
          parameters: const {},
          operations: kNativeIntlValueOperations);
      expect(evaluator.evaluate(),
          i.DateFormat.yMd('en_US').format(cases[index].$2));
      final epoch =
          program.nodes.indexWhere((n) => n.op == 'intl.datetime.new');
      expect(evaluator.evaluate(epoch), {
        'microsecondsSinceEpoch': cases[index].$2.microsecondsSinceEpoch,
        'isUtc': cases[index].$2.isUtc,
      });
    }
    expect(
        _formattingResult(() => ValueEvaluator(programs.last,
                captures: _NoFormattingCaptures(),
                parameters: const {},
                operations: kNativeIntlValueOperations)
            .evaluate()),
        _formattingResult(() => i.DateFormat.yMd('en_US').format(
            DateTime.fromMicrosecondsSinceEpoch(
                isUtc: i.DateFormat.yMd('unknown_locale')
                        .format(DateTime.utc(2024)) ==
                    '',
                1 ~/ 0))));
  });
}
