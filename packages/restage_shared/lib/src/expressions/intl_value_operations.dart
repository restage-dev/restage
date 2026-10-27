import 'temporal_value_operations.dart';
import 'value_program.dart';

export 'temporal_value_operations.dart' show dateTimeValueType;

/// Catalog floor for native internationalization value operations.
const intlValueCapability = 23;

const _nullableString = ValueType('String', nullable: true);
const _nullableInt = ValueType('int', nullable: true);
const _nullableBool = ValueType('bool', nullable: true);
const _dateStep = ValueType('record', fields: {
  'pattern': _nullableString,
  'separator': ValueType.string,
});
const dateFormatterValueType = ValueType('record', fields: {
  'pattern': _nullableString,
  'locale': ValueType.string,
  'nativeDigits': _nullableBool,
  'steps': ValueType('list', item: _dateStep),
});
const _numberStep = ValueType('record', fields: {
  'name': ValueType.string,
  'integer': _nullableInt,
  'boolean': _nullableBool,
  'string': _nullableString,
});
const numberFormatterValueType = ValueType('record', fields: {
  'constructor': ValueType.string,
  'locale': ValueType.string,
  'pattern': _nullableString,
  'name': _nullableString,
  'symbol': _nullableString,
  'decimalDigits': _nullableInt,
  'customPattern': _nullableString,
  'explicitSign': ValueType.boolean,
  'steps': ValueType('list', item: _numberStep),
});

/// Native DateFormat skeleton constructors and matching add methods.
const dateFormatSkeletons = {
  'd',
  'E',
  'EEEE',
  'LLL',
  'LLLL',
  'M',
  'Md',
  'MEd',
  'MMM',
  'MMMd',
  'MMMEd',
  'MMMM',
  'MMMMd',
  'MMMMEEEEd',
  'QQQ',
  'QQQQ',
  'y',
  'yM',
  'yMd',
  'yMEd',
  'yMMM',
  'yMMMd',
  'yMMMEd',
  'yMMMM',
  'yMMMMd',
  'yMMMMEEEEd',
  'yQQQ',
  'yQQQQ',
  'H',
  'Hm',
  'Hms',
  'j',
  'jm',
  'jms',
  'jmv',
  'jmz',
  'jv',
  'jz',
  'm',
  'ms',
  's',
};

/// Constructor argument names are native identities, in source evaluation order.
const numberFormatArguments = <String, Map<String, ValueType>>{
  '': {'pattern': _nullableString, 'locale': _nullableString},
  'decimalPattern': {'locale': _nullableString},
  'decimalPatternDigits': {
    'locale': _nullableString,
    'decimalDigits': _nullableInt
  },
  'percentPattern': {'locale': _nullableString},
  'decimalPercentPattern': {
    'locale': _nullableString,
    'decimalDigits': _nullableInt
  },
  'scientificPattern': {'locale': _nullableString},
  'currencyPattern': {'locale': _nullableString, 'name': _nullableString},
  'currency': {
    'locale': _nullableString,
    'name': _nullableString,
    'symbol': _nullableString,
    'decimalDigits': _nullableInt,
    'customPattern': _nullableString,
  },
  'simpleCurrency': {
    'locale': _nullableString,
    'name': _nullableString,
    'decimalDigits': _nullableInt,
  },
  'compact': {'locale': _nullableString, 'explicitSign': ValueType.boolean},
  'compactLong': {'locale': _nullableString, 'explicitSign': ValueType.boolean},
  'compactCurrency': {
    'locale': _nullableString,
    'name': _nullableString,
    'symbol': _nullableString,
    'decimalDigits': _nullableInt,
  },
  'compactSimpleCurrency': {
    'locale': _nullableString,
    'name': _nullableString,
    'decimalDigits': _nullableInt,
  },
};
const numberFormatSetters = <String, ValueType>{
  'maximumIntegerDigits': ValueType.integer,
  'minimumIntegerDigits': ValueType.integer,
  'maximumFractionDigits': ValueType.integer,
  'minimumFractionDigits': ValueType.integer,
  'minimumExponentDigits': ValueType.integer,
  'maximumSignificantDigits': _nullableInt,
  'minimumSignificantDigits': _nullableInt,
  'significantDigits': _nullableInt,
  'significantDigitsInUse': ValueType.boolean,
  'minimumSignificantDigitsStrict': ValueType.boolean,
  'currencyName': _nullableString,
};

// Non-null meanings form lookup keys and require installed native declarations.
const _pluralArguments = {
  'zero': _nullableString,
  'one': _nullableString,
  'two': _nullableString,
  'few': _nullableString,
  'many': _nullableString,
  'other': ValueType.string,
  'locale': _nullableString,
  'precision': _nullableInt,
  'meaning': ValueType.nullType,
};
const _genderArguments = {
  'female': _nullableString,
  'male': _nullableString,
  'other': ValueType.string,
  'locale': _nullableString,
  'meaning': ValueType.nullType,
};

/// Pure validation registry. Evaluation is supplied by the installed runtime.
const Map<String, ValueOperation> kIntlValueOperations = {
  ...kTemporalValueOperations,
  'intl.date.new': IntlValueOperation('intl.date.new'),
  'intl.date.add': IntlValueOperation('intl.date.add'),
  'intl.date.digits': IntlValueOperation('intl.date.digits'),
  'intl.date.format': IntlValueOperation('intl.date.format'),
  'intl.number.new': IntlValueOperation('intl.number.new'),
  'intl.number.set': IntlValueOperation('intl.number.set'),
  'intl.number.noGrouping': IntlValueOperation('intl.number.noGrouping'),
  'intl.number.format': IntlValueOperation('intl.number.format'),
  'intl.plural': IntlValueOperation('intl.plural'),
  'intl.gender': IntlValueOperation('intl.gender'),
  'intl.select': IntlValueOperation('intl.select'),
  'intl.datetime.new': IntlValueOperation('intl.datetime.new'),
  'intl.datetime.zone': IntlValueOperation('intl.datetime.zone'),
};

/// Validates the closed native formatting vocabulary without importing intl.
class IntlValueOperation implements ValueOperation {
  const IntlValueOperation(this.name);
  @override
  final String name;
  @override
  int get capability => intlValueCapability;

  @override
  Object? evaluate(List<Object?> inputs, Object? options) =>
      throw UnsupportedError(
          'Native intl operations require an installed runtime');

  @override
  void validate(ValueNode node, List<ValueType> inputs) {
    void require(bool condition) {
      if (!condition) throw FormatException('Invalid $name operation');
    }

    require(node.name == null);
    bool result(ValueType type) =>
        type.accepts(node.type) && node.type.accepts(type);
    bool input(int index, ValueType type) =>
        index < inputs.length && type.accepts(inputs[index]);
    Map<String, Object?> options(Set<String> allowed) {
      final value = node.value;
      require(value is Map<String, Object?>);
      final map = value! as Map<String, Object?>;
      require(map.keys.every(allowed.contains));
      return map;
    }

    List<String> arguments(Map<String, Object?> options) {
      final values = options['arguments'];
      require(values is List && values.every((v) => v is String));
      final names = (values! as List).cast<String>();
      require(names.toSet().length == names.length);
      return names;
    }

    void named(List<String> names, Map<String, ValueType> types, int offset) {
      require(inputs.length == names.length + offset);
      for (var i = 0; i < names.length; i++) {
        require(types[names[i]] != null && input(i + offset, types[names[i]]!));
      }
    }

    switch (name) {
      case 'intl.date.new':
        final o = options({'arguments'});
        named(arguments(o),
            {'pattern': _nullableString, 'locale': _nullableString}, 0);
        require(result(dateFormatterValueType));
      case 'intl.date.add':
        require(node.value == null &&
            inputs.length == 3 &&
            input(0, dateFormatterValueType) &&
            input(1, _nullableString) &&
            input(2, ValueType.string) &&
            result(dateFormatterValueType));
      case 'intl.date.digits':
        require(node.value == null &&
            inputs.length == 2 &&
            input(0, dateFormatterValueType) &&
            input(1, ValueType.boolean) &&
            result(dateFormatterValueType));
      case 'intl.date.format':
        require(node.value == null &&
            inputs.length == 2 &&
            input(0, dateFormatterValueType) &&
            input(1, dateTimeValueType) &&
            result(ValueType.string));
      case 'intl.number.new':
        final o = options({'constructor', 'arguments'});
        final types = numberFormatArguments[o['constructor']];
        require(types != null && result(numberFormatterValueType));
        named(arguments(o), types!, 0);
      case 'intl.number.set':
        final o = options({'setter'});
        final type = numberFormatSetters[o['setter']];
        require(type != null &&
            inputs.length == 2 &&
            input(0, numberFormatterValueType) &&
            input(1, type) &&
            result(numberFormatterValueType));
      case 'intl.number.noGrouping':
        require(node.value == null &&
            inputs.length == 1 &&
            input(0, numberFormatterValueType) &&
            result(numberFormatterValueType));
      case 'intl.number.format':
        require(node.value == null &&
            inputs.length == 2 &&
            input(0, numberFormatterValueType) &&
            input(1, ValueType.number) &&
            result(ValueType.string));
      case 'intl.plural':
      case 'intl.gender':
        final o = options({'arguments'});
        final names = arguments(o);
        require(names.contains('other') &&
            result(ValueType.string) &&
            input(0,
                name == 'intl.plural' ? ValueType.number : ValueType.string));
        named(names,
            name == 'intl.plural' ? _pluralArguments : _genderArguments, 1);
      case 'intl.select':
        final o = options({'keys', 'arguments', 'choiceEnum'});
        final keys = o['keys'];
        require(
            keys is List && keys.length <= 256 && keys.every(isIntlSelectKey));
        require(o['choiceEnum'] == null ||
            o['choiceEnum'] is String && input(0, ValueType.string));
        final cases = keys! as List;
        require(cases.contains('other') &&
            result(ValueType.string) &&
            inputs.isNotEmpty &&
            !inputs[0].nullable &&
            const {'String', 'int', 'double', 'num', 'bool'}
                .contains(inputs[0].kind));
        for (var i = 0; i < cases.length; i++) {
          require(input(i + 1, ValueType.string));
        }
        named(
            arguments(o),
            {'locale': _nullableString, 'meaning': ValueType.nullType},
            1 + cases.length);
      case 'intl.datetime.new':
        final o = options({'constructor', 'arguments'});
        final constructor = o['constructor'];
        require(result(dateTimeValueType));
        switch (constructor) {
          case '':
          case 'utc':
            require(inputs.isNotEmpty &&
                inputs.length <= 8 &&
                inputs.every((v) => ValueType.integer.accepts(v)) &&
                arguments(o).isEmpty);
          case 'fromMillisecondsSinceEpoch':
          case 'fromMicrosecondsSinceEpoch':
            require(input(0, ValueType.integer));
            named(arguments(o), {'isUtc': ValueType.boolean}, 1);
          case 'parse':
            require(inputs.length == 1 &&
                input(0, ValueType.string) &&
                arguments(o).isEmpty);
          default:
            require(false);
        }
      case 'intl.datetime.zone':
        final o = options({'utc'});
        require(o['utc'] is bool &&
            inputs.length == 1 &&
            input(0, dateTimeValueType) &&
            result(dateTimeValueType));
      default:
        require(false);
    }
  }
}

/// A select key is a scalar or an exact, resolved enum identity.
bool isIntlSelectKey(Object? key) =>
    key is String ||
    key is num ||
    key is bool ||
    key is Map<String, Object?> &&
        key.length == 2 &&
        key['enum'] is String &&
        key['name'] is String;
