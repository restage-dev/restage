import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

final class _Reader implements ValueReader {
  @override
  Object? read(List<Object> path, ValueType type) =>
      throw StateError('No captures');
  @override
  int length(List<Object> path) => throw StateError('No captures');
}

Map<String, Object?> _date(DateTime date) => {
      'microsecondsSinceEpoch': date.microsecondsSinceEpoch,
      'isUtc': date.isUtc,
    };
Object? _run(String name, List<Object?> inputs, Object? options) =>
    kTemporalValueOperations[name]!.evaluate(inputs, options);

void main() {
  test(
      'clock reads per occurrence, shares declared local and skips false branch',
      () {
    var reads = 0;
    final operations = {
      ...kTemporalValueOperations,
      'clock.now': ClockNowOperation(
          read: () =>
              DateTime.fromMicrosecondsSinceEpoch(++reads, isUtc: true)),
    };
    Object? evaluate(List<ValueNode> nodes) => ValueEvaluator(
          ValueProgram(nodes: nodes, root: nodes.length - 1),
          captures: _Reader(),
          parameters: {},
          operations: operations,
        ).evaluate();
    const list = ValueType('list', item: dateTimeValueType);
    expect(
        evaluate(const [
          ValueNode('clock.now', dateTimeValueType),
          ValueNode('clock.now', dateTimeValueType),
          ValueNode('list', list, inputs: [0, 1]),
        ]),
        [
          _date(DateTime.fromMicrosecondsSinceEpoch(1, isUtc: true)),
          _date(DateTime.fromMicrosecondsSinceEpoch(2, isUtc: true))
        ]);
    expect(reads, 2);
    final reused = evaluate(const [
      ValueNode('clock.now', dateTimeValueType),
      ValueNode('list', list, inputs: [0, 0]),
      ValueNode('let', list, inputs: [0, 1]),
    ])! as List;
    expect(reads, 3);
    expect(reused[0], reused[1]);
    expect(
        evaluate(const [
          ValueNode('literal', ValueType.boolean, value: false),
          ValueNode('clock.now', dateTimeValueType),
          ValueNode('temporal.datetime.get', ValueType.integer,
              inputs: [1], value: 'microsecondsSinceEpoch'),
          ValueNode('literal', ValueType.integer, value: 0),
          ValueNode('conditional', ValueType.integer, inputs: [0, 2, 3]),
        ]),
        0);
    expect(reads, 3);
  });
  test('clock reads anew for each builder invocation', () {
    var reads = 0;
    final operations = {
      ...kTemporalValueOperations,
      'clock.now': ClockNowOperation(
          read: () => DateTime.fromMicrosecondsSinceEpoch(++reads)),
    };
    const program = BuilderProgram(
      values: ValueProgram(nodes: [
        ValueNode('clock.now', dateTimeValueType),
        ValueNode('temporal.datetime.get', ValueType.integer,
            inputs: [0], value: 'microsecondsSinceEpoch'),
      ], root: 1),
      result: BuilderResult.body(0, values: {'now': 1}),
      bodyCount: 1,
    );
    expect(
        program
            .invoke(captures: _Reader(), parameters: {}, operations: operations)
            .values['now'],
        1);
    expect(
        program
            .invoke(captures: _Reader(), parameters: {}, operations: operations)
            .values['now'],
        2);
    expect(reads, 2);
  });
  test('installed real clock sample lies inside its native call bracket', () {
    final before = DateTime.now();
    final result = ValueEvaluator(
            const ValueProgram(
                nodes: [ValueNode('clock.now', dateTimeValueType)], root: 0),
            captures: _Reader(),
            parameters: {},
            operations: kTemporalValueOperations)
        .evaluate()! as Map;
    final after = DateTime.now();
    expect(
        result['microsecondsSinceEpoch'],
        inInclusiveRange(
            before.microsecondsSinceEpoch, after.microsecondsSinceEpoch));
    expect(result['isUtc'], isFalse);
  });
  test('UTC/local getters and timezone values match native DateTime', () {
    for (final date in [
      DateTime.utc(2024, 2, 29, 17, 23, 41, 123, 456),
      DateTime(2024, 2, 29, 17, 23, 41, 123, 789),
      DateTime.fromMicrosecondsSinceEpoch(-1234567)
    ]) {
      final native = <String, Object>{
        'year': date.year,
        'month': date.month,
        'day': date.day,
        'hour': date.hour,
        'minute': date.minute,
        'second': date.second,
        'millisecond': date.millisecond,
        'microsecond': date.microsecond,
        'weekday': date.weekday,
        'millisecondsSinceEpoch': date.millisecondsSinceEpoch,
        'microsecondsSinceEpoch': date.microsecondsSinceEpoch,
        'isUtc': date.isUtc,
        'timeZoneName': date.timeZoneName,
        'timeZoneOffset': {'microseconds': date.timeZoneOffset.inMicroseconds},
      };
      for (final entry in native.entries) {
        expect(_run('temporal.datetime.get', [_date(date)], entry.key),
            entry.value,
            reason: entry.key);
      }
    }
  });
  test('Duration uses native exact arithmetic and negative truncation', () {
    const duration = Duration(
        days: -2,
        hours: 1,
        minutes: 2,
        seconds: 3,
        milliseconds: 4,
        microseconds: 5);
    final value = _run('temporal.duration.new', [
      -2,
      1,
      2,
      3,
      4,
      5
    ], [
      'days',
      'hours',
      'minutes',
      'seconds',
      'milliseconds',
      'microseconds'
    ]);
    expect(value, {'microseconds': duration.inMicroseconds});
    for (final duration in [
      duration,
      const Duration(microseconds: -1001),
      const Duration(microseconds: 999)
    ]) {
      final native = {
        'inDays': duration.inDays,
        'inHours': duration.inHours,
        'inMinutes': duration.inMinutes,
        'inSeconds': duration.inSeconds,
        'inMilliseconds': duration.inMilliseconds,
        'inMicroseconds': duration.inMicroseconds
      };
      for (final entry in native.entries) {
        expect(
            _run(
                'temporal.duration.get',
                [
                  {'microseconds': duration.inMicroseconds}
                ],
                entry.key),
            entry.value);
      }
    }
  });
  test('DateTime comparison, equality, difference and arithmetic stay native',
      () {
    for (final date in [
      DateTime.utc(2024, 3, 10, 1, 59, 59, 999, 999),
      DateTime(2024, 11, 3, 1, 30)
    ]) {
      final other = date.toUtc().add(const Duration(microseconds: 1001));
      final inputs = [_date(date), _date(other)];
      expect(_run('temporal.datetime.difference', inputs, null),
          {'microseconds': date.difference(other).inMicroseconds});
      expect(_run('temporal.datetime.compareTo', inputs, null),
          date.compareTo(other));
      expect(_run('temporal.datetime.isBefore', inputs, null),
          date.isBefore(other));
      expect(
          _run('temporal.datetime.isAfter', inputs, null), date.isAfter(other));
      expect(
          _run('temporal.datetime.isAtSameMomentAs',
              [_date(date), _date(date.toUtc())], null),
          true);
      expect(
          _run('temporal.datetime.equals', [_date(date), _date(date.toUtc())],
              null),
          date == date.toUtc());
      for (final duration in [
        const Duration(microseconds: -1001),
        const Duration(hours: 25, microseconds: 7)
      ]) {
        final args = [
          _date(date),
          {'microseconds': duration.inMicroseconds}
        ];
        expect(_run('temporal.datetime.add', args, null),
            _date(date.add(duration)));
        expect(_run('temporal.datetime.subtract', args, null),
            _date(date.subtract(duration)));
      }
    }
  });
  test('closed operation contracts reject forged member names and shape', () {
    for (final node in const [
      ValueNode('clock.now', dateTimeValueType, value: 'now'),
      ValueNode('clock.now', ValueType.integer),
      ValueNode('temporal.datetime.get', ValueType.integer, value: 'hashCode'),
      ValueNode('temporal.duration.new', durationValueType,
          value: ['hashCode']),
    ]) {
      expect(() => kTemporalValueOperations[node.op]!.validate(node, []),
          throwsFormatException);
    }
    expect(const ClockNowOperation().capability, 24);
  });
}
