import 'package:intl/intl.dart';
import 'package:restage_shared/restage_shared.dart';

/// Installed native implementations of the shared formatting vocabulary.
const Map<String, ValueOperation> kNativeIntlValueOperations = {
  ...kTemporalValueOperations,
  'intl.date.new': _NativeIntlOperation('intl.date.new'),
  'intl.date.add': _NativeIntlOperation('intl.date.add'),
  'intl.date.digits': _NativeIntlOperation('intl.date.digits'),
  'intl.date.format': _NativeIntlOperation('intl.date.format'),
  'intl.number.new': _NativeIntlOperation('intl.number.new'),
  'intl.number.set': _NativeIntlOperation('intl.number.set'),
  'intl.number.noGrouping': _NativeIntlOperation('intl.number.noGrouping'),
  'intl.number.format': _NativeIntlOperation('intl.number.format'),
  'intl.plural': _NativeIntlOperation('intl.plural'),
  'intl.gender': _NativeIntlOperation('intl.gender'),
  'intl.select': _NativeIntlOperation('intl.select'),
  'intl.datetime.new': _NativeIntlOperation('intl.datetime.new'),
  'intl.datetime.zone': _NativeIntlOperation('intl.datetime.zone'),
};

final class _NativeIntlOperation extends IntlValueOperation {
  const _NativeIntlOperation(super.name);

  @override
  Object? evaluate(List<Object?> inputs, Object? options) {
    final o = options as Map<String, Object?>? ?? const {};
    Map<String, Object?> arguments(int offset) => {
          for (var i = 0; i < (o['arguments'] as List).length; i++)
            (o['arguments'] as List)[i] as String: inputs[i + offset],
        };
    Map<String, Object?> formattingArguments(int offset) {
      final values = arguments(offset);
      if (values['meaning'] != null) {
        throw const FormatException(
            'Intl translation lookup requires an installed native binding');
      }
      return values;
    }

    Map<String, Object?> record(int i) => inputs[i]! as Map<String, Object?>;
    switch (name) {
      case 'intl.date.new':
        final a = arguments(0);
        final format =
            DateFormat(a['pattern'] as String?, a['locale'] as String?);
        return <String, Object?>{
          'pattern': a['pattern'],
          'locale': format.locale,
          'nativeDigits': null,
          'steps': <Object?>[],
        };
      case 'intl.date.add':
        final recipe = record(0);
        _dateFormatter(recipe)
            .addPattern(inputs[1] as String?, inputs[2]! as String);
        return <String, Object?>{
          ...recipe,
          'steps': <Object?>[
            ...recipe['steps']! as List,
            {'pattern': inputs[1], 'separator': inputs[2]},
          ],
        };
      case 'intl.date.digits':
        final recipe = record(0);
        _dateFormatter(recipe).useNativeDigits = inputs[1]! as bool;
        return <String, Object?>{...recipe, 'nativeDigits': inputs[1]};
      case 'intl.date.format':
        return _dateFormatter(record(0)).format(_dateTime(record(1)));
      case 'intl.number.new':
        final a = arguments(0);
        final recipe = <String, Object?>{
          'constructor': o['constructor'],
          'locale': a['locale'],
          'pattern': a['pattern'],
          'name': a['name'],
          'symbol': a['symbol'],
          'decimalDigits': a['decimalDigits'],
          'customPattern': a['customPattern'],
          'explicitSign': a['explicitSign'] ?? false,
          'steps': <Object?>[],
        };
        final format = _numberFormatter(recipe);
        return <String, Object?>{...recipe, 'locale': format.locale};
      case 'intl.number.set':
        final recipe = record(0);
        final setter = o['setter']! as String;
        final value = inputs[1];
        final step = <String, Object?>{
          'name': setter,
          'integer': value is int ? value : null,
          'boolean': value is bool ? value : null,
          'string': value is String ? value : null,
        };
        _numberSetter(_numberFormatter(recipe), step);
        return <String, Object?>{
          ...recipe,
          'steps': <Object?>[...recipe['steps']! as List, step],
        };
      case 'intl.number.noGrouping':
        final recipe = record(0);
        _numberFormatter(recipe).turnOffGrouping();
        return <String, Object?>{
          ...recipe,
          'steps': <Object?>[
            ...recipe['steps']! as List,
            <String, Object?>{
              'name': 'turnOffGrouping',
              'integer': null,
              'boolean': null,
              'string': null
            },
          ],
        };
      case 'intl.number.format':
        return _numberFormatter(record(0)).format(inputs[1]);
      case 'intl.plural':
        final a = formattingArguments(1);
        return Intl.plural(
          inputs[0]! as num,
          zero: a['zero'] as String?,
          one: a['one'] as String?,
          two: a['two'] as String?,
          few: a['few'] as String?,
          many: a['many'] as String?,
          other: a['other']! as String,
          locale: a['locale'] as String?,
          precision: a['precision'] as int?,
          meaning: a['meaning'] as String?,
        );
      case 'intl.gender':
        final a = formattingArguments(1);
        return Intl.gender(
          inputs[0]! as String,
          female: a['female'] as String?,
          male: a['male'] as String?,
          other: a['other']! as String,
          locale: a['locale'] as String?,
          meaning: a['meaning'] as String?,
        );
      case 'intl.select':
        final keys = o['keys']! as List;
        final a = formattingArguments(1 + keys.length);
        return Intl.select(
            o['choiceEnum'] == null
                ? inputs[0]!
                : _SelectEnum(o['choiceEnum']! as String, inputs[0]! as String),
            {
              for (var i = 0; i < keys.length; i++)
                _selectKey(keys[i]!): inputs[i + 1]! as String,
            },
            locale: a['locale'] as String?,
            meaning: a['meaning'] as String?);
      case 'intl.datetime.new':
        final DateTime date;
        switch (o['constructor']) {
          case '':
          case 'utc':
            final a = <int>[...inputs.cast<int>()];
            const defaults = [0, 1, 1, 0, 0, 0, 0, 0];
            for (var i = a.length; i < 8; i++) a.add(defaults[i]);
            date = o['constructor'] == 'utc'
                ? DateTime.utc(a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7])
                : DateTime(a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7]);
          case 'parse':
            date = DateTime.parse(inputs[0]! as String);
          case 'fromMillisecondsSinceEpoch':
            date = DateTime.fromMillisecondsSinceEpoch(inputs[0]! as int,
                isUtc: arguments(1)['isUtc'] as bool? ?? false);
          case 'fromMicrosecondsSinceEpoch':
            date = DateTime.fromMicrosecondsSinceEpoch(inputs[0]! as int,
                isUtc: arguments(1)['isUtc'] as bool? ?? false);
          default:
            throw const FormatException('Unknown DateTime constructor');
        }
        return _dateRecord(date);
      case 'intl.datetime.zone':
        final date = _dateTime(record(0));
        return _dateRecord(o['utc']! as bool ? date.toUtc() : date.toLocal());
      default:
        throw FormatException('Unknown native intl operation $name');
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
DateFormat _dateFormatter(Map<String, Object?> recipe) {
  final format =
      DateFormat(recipe['pattern'] as String?, recipe['locale'] as String?);
  if (recipe['nativeDigits'] case final bool native)
    format.useNativeDigits = native;
  for (final raw in recipe['steps']! as List) {
    final step = raw! as Map<String, Object?>;
    format.addPattern(step['pattern'] as String?, step['separator']! as String);
  }
  return format;
}

NumberFormat _numberFormatter(Map<String, Object?> recipe) {
  final locale = recipe['locale'] as String?;
  final name = recipe['name'] as String?;
  final digits = recipe['decimalDigits'] as int?;
  final format = switch (recipe['constructor']) {
    '' => NumberFormat(recipe['pattern'] as String?, locale),
    'decimalPattern' => NumberFormat.decimalPattern(locale),
    'decimalPatternDigits' =>
      NumberFormat.decimalPatternDigits(locale: locale, decimalDigits: digits),
    'percentPattern' => NumberFormat.percentPattern(locale),
    'decimalPercentPattern' =>
      NumberFormat.decimalPercentPattern(locale: locale, decimalDigits: digits),
    'scientificPattern' => NumberFormat.scientificPattern(locale),
    'currencyPattern' => NumberFormat.currencyPattern(locale, name),
    'currency' => NumberFormat.currency(
        locale: locale,
        name: name,
        symbol: recipe['symbol'] as String?,
        decimalDigits: digits,
        customPattern: recipe['customPattern'] as String?),
    'simpleCurrency' => NumberFormat.simpleCurrency(
        locale: locale, name: name, decimalDigits: digits),
    'compact' => NumberFormat.compact(
        locale: locale, explicitSign: recipe['explicitSign']! as bool),
    'compactLong' => NumberFormat.compactLong(
        locale: locale, explicitSign: recipe['explicitSign']! as bool),
    'compactCurrency' => NumberFormat.compactCurrency(
        locale: locale,
        name: name,
        symbol: recipe['symbol'] as String?,
        decimalDigits: digits),
    'compactSimpleCurrency' => NumberFormat.compactSimpleCurrency(
        locale: locale, name: name, decimalDigits: digits),
    _ => throw const FormatException('Unknown NumberFormat constructor'),
  };
  for (final raw in recipe['steps']! as List) {
    _numberSetter(format, raw! as Map<String, Object?>);
  }
  return format;
}

void _numberSetter(NumberFormat format, Map<String, Object?> step) {
  final integer = step['integer'] as int?;
  final boolean = step['boolean'] as bool?;
  switch (step['name']) {
    case 'maximumIntegerDigits':
      format.maximumIntegerDigits = integer!;
    case 'minimumIntegerDigits':
      format.minimumIntegerDigits = integer!;
    case 'maximumFractionDigits':
      format.maximumFractionDigits = integer!;
    case 'minimumFractionDigits':
      format.minimumFractionDigits = integer!;
    case 'minimumExponentDigits':
      format.minimumExponentDigits = integer!;
    case 'maximumSignificantDigits':
      format.maximumSignificantDigits = integer;
    case 'minimumSignificantDigits':
      format.minimumSignificantDigits = integer;
    case 'significantDigits':
      format.significantDigits = integer;
    case 'significantDigitsInUse':
      format.significantDigitsInUse = boolean!;
    case 'minimumSignificantDigitsStrict':
      format.minimumSignificantDigitsStrict = boolean!;
    case 'currencyName':
      format.currencyName = step['string'] as String?;
    case 'turnOffGrouping':
      format.turnOffGrouping();
    default:
      throw const FormatException('Unknown NumberFormat configuration');
  }
}

Object _selectKey(Object key) => key is Map<String, Object?>
    ? _SelectEnum(key['enum']! as String, key['name']! as String)
    : key;

final class _SelectEnum {
  const _SelectEnum(this.identity, this.name);
  final String identity;
  final String name;
  @override
  bool operator ==(Object other) =>
      other is _SelectEnum && other.identity == identity && other.name == name;
  @override
  int get hashCode => Object.hash(identity, name);
  @override
  String toString() => '${identity.split('#').last}.$name';
}
