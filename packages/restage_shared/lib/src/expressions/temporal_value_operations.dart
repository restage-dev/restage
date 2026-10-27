import 'value_program.dart';

/// Capability floor for declared clock reads and native temporal operations.
const temporalValueCapability = 24;

/// A DateTime crossing the host boundary retains its exact native identity.
const dateTimeValueType = ValueType('record', fields: {
  'microsecondsSinceEpoch': ValueType.integer,
  'isUtc': ValueType.boolean,
});

/// Exact native Duration value; no millisecond truncation is permitted.
const durationValueType = ValueType('record', fields: {
  'microseconds': ValueType.integer,
});

/// Fixed native getter identities and their result types.
const dateTimeGetters = <String, ValueType>{
  'year': ValueType.integer,
  'month': ValueType.integer,
  'day': ValueType.integer,
  'hour': ValueType.integer,
  'minute': ValueType.integer,
  'second': ValueType.integer,
  'millisecond': ValueType.integer,
  'microsecond': ValueType.integer,
  'weekday': ValueType.integer,
  'millisecondsSinceEpoch': ValueType.integer,
  'microsecondsSinceEpoch': ValueType.integer,
  'isUtc': ValueType.boolean,
  'timeZoneName': ValueType.string,
  'timeZoneOffset': durationValueType,
};

/// Fixed native Duration getter identities.
const durationGetters = <String>{
  'inDays',
  'inHours',
  'inMinutes',
  'inSeconds',
  'inMilliseconds',
  'inMicroseconds',
};

/// Native Duration constructor units, retained in source evaluation order.
const durationArguments = <String>{
  'days',
  'hours',
  'minutes',
  'seconds',
  'milliseconds',
  'microseconds',
};

/// Closed, installed dart:core operations, also usable by compiler validation.
const Map<String, ValueOperation> kTemporalValueOperations = {
  'clock.now': ClockNowOperation(),
  'temporal.datetime.get': TemporalValueOperation('temporal.datetime.get'),
  'temporal.datetime.difference':
      TemporalValueOperation('temporal.datetime.difference'),
  'temporal.datetime.compareTo':
      TemporalValueOperation('temporal.datetime.compareTo'),
  'temporal.datetime.isBefore':
      TemporalValueOperation('temporal.datetime.isBefore'),
  'temporal.datetime.isAfter':
      TemporalValueOperation('temporal.datetime.isAfter'),
  'temporal.datetime.isAtSameMomentAs':
      TemporalValueOperation('temporal.datetime.isAtSameMomentAs'),
  'temporal.datetime.equals':
      TemporalValueOperation('temporal.datetime.equals'),
  'temporal.datetime.add': TemporalValueOperation('temporal.datetime.add'),
  'temporal.datetime.subtract':
      TemporalValueOperation('temporal.datetime.subtract'),
  'temporal.duration.new': TemporalValueOperation('temporal.duration.new'),
  'temporal.duration.get': TemporalValueOperation('temporal.duration.get'),
};

/// One declared read per evaluated expression occurrence and invocation.
///
/// The optional installed read function permits deterministic evaluation tests;
/// no payload can select or supply it.
final class ClockNowOperation implements ValueOperation {
  const ClockNowOperation({this.read});
  final DateTime Function()? read;
  @override
  String get name => 'clock.now';
  @override
  int get capability => temporalValueCapability;
  @override
  void validate(ValueNode node, List<ValueType> inputs) {
    if (node.name != null ||
        node.value != null ||
        inputs.isNotEmpty ||
        !dateTimeValueType.accepts(node.type) ||
        !node.type.accepts(dateTimeValueType)) {
      throw const FormatException('Invalid clock.now operation');
    }
  }

  @override
  Object? evaluate(List<Object?> inputs, Object? options) =>
      _dateRecord((read ?? DateTime.now)());
}

/// Exact closed native temporal vocabulary, with no dynamic member invocation.
final class TemporalValueOperation implements ValueOperation {
  const TemporalValueOperation(this.name);
  @override
  final String name;
  @override
  int get capability => temporalValueCapability;

  @override
  void validate(ValueNode node, List<ValueType> inputs) {
    Never invalid() => throw FormatException('Invalid $name operation');
    if (node.name != null) invalid();
    bool exact(ValueType a, ValueType b) => a.accepts(b) && b.accepts(a);
    bool signature(ValueType result, List<ValueType> parameters) =>
        exact(node.type, result) &&
        parameters.length == inputs.length &&
        List.generate(inputs.length, (i) => parameters[i].accepts(inputs[i]))
            .every((accepted) => accepted);
    switch (name) {
      case 'temporal.datetime.get':
      case 'temporal.duration.get':
        final getter = node.value;
        final date = name == 'temporal.datetime.get';
        final type = date
            ? dateTimeGetters[getter]
            : durationGetters.contains(getter)
                ? ValueType.integer
                : null;
        if (type == null ||
            !signature(type, [date ? dateTimeValueType : durationValueType]))
          invalid();
      case 'temporal.duration.new':
        final names = node.value;
        if (names is! List ||
            names.length != inputs.length ||
            names.any((name) => !durationArguments.contains(name)) ||
            names.toSet().length != names.length ||
            !signature(
                durationValueType, [for (final _ in inputs) ValueType.integer]))
          invalid();
      case 'temporal.datetime.difference':
      case 'temporal.datetime.compareTo':
      case 'temporal.datetime.isBefore':
      case 'temporal.datetime.isAfter':
      case 'temporal.datetime.isAtSameMomentAs':
      case 'temporal.datetime.equals':
        final type = name == 'temporal.datetime.difference'
            ? durationValueType
            : name == 'temporal.datetime.compareTo'
                ? ValueType.integer
                : ValueType.boolean;
        if (node.value != null ||
            !signature(type, [dateTimeValueType, dateTimeValueType])) invalid();
      case 'temporal.datetime.add':
      case 'temporal.datetime.subtract':
        if (node.value != null ||
            !signature(
                dateTimeValueType, [dateTimeValueType, durationValueType]))
          invalid();
      default:
        invalid();
    }
  }

  @override
  Object? evaluate(List<Object?> inputs, Object? options) {
    Map<String, Object?> record(int i) => inputs[i]! as Map<String, Object?>;
    DateTime date(int i) => _dateTime(record(i));
    Duration duration(int i) =>
        Duration(microseconds: record(i)['microseconds']! as int);
    switch (name) {
      case 'temporal.datetime.get':
        final value = date(0);
        return switch (options) {
          'year' => value.year,
          'month' => value.month,
          'day' => value.day,
          'hour' => value.hour,
          'minute' => value.minute,
          'second' => value.second,
          'millisecond' => value.millisecond,
          'microsecond' => value.microsecond,
          'weekday' => value.weekday,
          'millisecondsSinceEpoch' => value.millisecondsSinceEpoch,
          'microsecondsSinceEpoch' => value.microsecondsSinceEpoch,
          'isUtc' => value.isUtc,
          'timeZoneName' => value.timeZoneName,
          'timeZoneOffset' => _durationRecord(value.timeZoneOffset),
          _ => throw const FormatException('Unknown DateTime getter'),
        };
      case 'temporal.duration.get':
        final value = duration(0);
        return switch (options) {
          'inDays' => value.inDays,
          'inHours' => value.inHours,
          'inMinutes' => value.inMinutes,
          'inSeconds' => value.inSeconds,
          'inMilliseconds' => value.inMilliseconds,
          'inMicroseconds' => value.inMicroseconds,
          _ => throw const FormatException('Unknown Duration getter'),
        };
      case 'temporal.duration.new':
        final names = options! as List;
        final args = {
          for (var i = 0; i < names.length; i++) names[i]: inputs[i]! as int
        };
        return _durationRecord(Duration(
          days: args['days'] ?? 0,
          hours: args['hours'] ?? 0,
          minutes: args['minutes'] ?? 0,
          seconds: args['seconds'] ?? 0,
          milliseconds: args['milliseconds'] ?? 0,
          microseconds: args['microseconds'] ?? 0,
        ));
      case 'temporal.datetime.difference':
        return _durationRecord(date(0).difference(date(1)));
      case 'temporal.datetime.compareTo':
        return date(0).compareTo(date(1));
      case 'temporal.datetime.isBefore':
        return date(0).isBefore(date(1));
      case 'temporal.datetime.isAfter':
        return date(0).isAfter(date(1));
      case 'temporal.datetime.isAtSameMomentAs':
        return date(0).isAtSameMomentAs(date(1));
      case 'temporal.datetime.equals':
        return date(0) == date(1);
      case 'temporal.datetime.add':
        return _dateRecord(date(0).add(duration(1)));
      case 'temporal.datetime.subtract':
        return _dateRecord(date(0).subtract(duration(1)));
      default:
        throw FormatException('Unknown native temporal operation $name');
    }
  }
}

Map<String, Object?> _dateRecord(DateTime date) => {
      'microsecondsSinceEpoch': date.microsecondsSinceEpoch,
      'isUtc': date.isUtc,
    };
DateTime _dateTime(Map<String, Object?> date) =>
    DateTime.fromMicrosecondsSinceEpoch(
      date['microsecondsSinceEpoch']! as int,
      isUtc: date['isUtc']! as bool,
    );
Map<String, Object?> _durationRecord(Duration duration) =>
    {'microseconds': duration.inMicroseconds};
