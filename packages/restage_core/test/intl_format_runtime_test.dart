import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';
import 'package:rfw/rfw.dart';
import 'package:rfw/formats.dart' as rfw;
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:restage_core/src/runtime/intl_value_operations.dart';
import 'package:restage_shared/restage_shared.dart';

enum _Status { active }

final class _NoCaptures implements ValueReader {
  @override
  Object? read(List<Object> path, ValueType type) =>
      throw StateError('No captures');
  @override
  int length(List<Object> path) => throw StateError('No captures');
}

final class _Graph {
  final nodes = <ValueNode>[];
  int literal(Object? value, ValueType type) {
    nodes.add(ValueNode('literal', type, value: value));
    return nodes.length - 1;
  }

  int op(String op, ValueType type, List<int> inputs, [Object? value]) {
    nodes.add(ValueNode(op, type, inputs: inputs, value: value));
    return nodes.length - 1;
  }

  int string(String? value) =>
      literal(value, value == null ? ValueType.nullType : ValueType.string);
  int date(DateTime value) => literal({
        'microsecondsSinceEpoch': value.microsecondsSinceEpoch,
        'isUtc': value.isUtc,
      }, dateTimeValueType);
  int formatter(String? pattern, String? locale) =>
      op('intl.date.new', dateFormatterValueType, [
        string(pattern),
        string(locale)
      ], {
        'arguments': ['pattern', 'locale']
      });
  int number(String constructor, Map<String, Object?> args) =>
      op('intl.number.new', numberFormatterValueType, [
        for (final value in args.values)
          literal(
              value,
              switch (value) {
                null => ValueType.nullType,
                String() => ValueType.string,
                bool() => ValueType.boolean,
                int() => ValueType.integer,
                _ => throw StateError('Unexpected number argument'),
              })
      ], {
        'constructor': constructor,
        'arguments': args.keys.toList()
      });
  Object? evaluate(int root) {
    final encoded = ValueProgram(nodes: nodes, root: root).encode();
    final program =
        ValueProgram.decode(encoded, operations: kIntlValueOperations);
    return ValueEvaluator(program,
            captures: _NoCaptures(),
            parameters: const {},
            operations: kNativeIntlValueOperations)
        .evaluate();
  }
}

Object _failure(Object? Function() compute) {
  try {
    compute();
  } on Object catch (error) {
    return error.runtimeType;
  }
  return 'did not throw';
}

void main() {
  test('date decoding retains native missing initialization failure', () {
    final graph = _Graph();
    final format = graph.formatter('yMMMd', 'fr');
    final root = graph.op('intl.date.format', ValueType.string,
        [format, graph.date(DateTime.utc(2024, 2, 29))]);
    expect(
        _failure(() => graph.evaluate(root)),
        _failure(
            () => DateFormat.yMMMd('fr').format(DateTime.utc(2024, 2, 29))));
  });

  test('date patterns, chains, native digits, UTC and local agree with intl',
      () async {
    await initializeDateFormatting();
    for (final locale in ['en_US', 'fr', 'ar', 'ru']) {
      for (final date in [
        DateTime.utc(2024, 2, 29, 17, 23, 41, 123, 456),
        DateTime(2024, 2, 29, 17, 23, 41, 123, 456)
      ]) {
        final graph = _Graph();
        var format = graph.formatter('yMMMd', locale);
        format = graph.op('intl.date.add', dateFormatterValueType,
            [format, graph.string('Hms'), graph.string(' | ')]);
        format = graph.op('intl.date.digits', dateFormatterValueType,
            [format, graph.literal(false, ValueType.boolean)]);
        final root = graph.op(
            'intl.date.format', ValueType.string, [format, graph.date(date)]);
        final native = DateFormat.yMMMd(locale).addPattern('Hms', ' | ')
          ..useNativeDigits = false;
        expect(graph.evaluate(root), native.format(date),
            reason: '$locale $date');
      }
    }
  });

  test('all NumberFormat constructor families preserve native semantics', () {
    for (final locale in ['en_US', 'fr', 'ar', 'ru']) {
      final families = <(String, Map<String, Object?>, NumberFormat)>[
        (
          '',
          {'pattern': '#,##0.000', 'locale': locale},
          NumberFormat('#,##0.000', locale)
        ),
        (
          'decimalPattern',
          {'locale': locale},
          NumberFormat.decimalPattern(locale)
        ),
        (
          'decimalPatternDigits',
          {'locale': locale, 'decimalDigits': 4},
          NumberFormat.decimalPatternDigits(locale: locale, decimalDigits: 4)
        ),
        (
          'percentPattern',
          {'locale': locale},
          NumberFormat.percentPattern(locale)
        ),
        (
          'decimalPercentPattern',
          {'locale': locale, 'decimalDigits': 1},
          NumberFormat.decimalPercentPattern(locale: locale, decimalDigits: 1)
        ),
        (
          'scientificPattern',
          {'locale': locale},
          NumberFormat.scientificPattern(locale)
        ),
        (
          'currencyPattern',
          {'locale': locale, 'name': 'EUR'},
          NumberFormat.currencyPattern(locale, 'EUR')
        ),
        (
          'currency',
          {
            'locale': locale,
            'name': 'EUR',
            'symbol': 'EU',
            'decimalDigits': 3,
            'customPattern': '¤ #,##0.000'
          },
          NumberFormat.currency(
              locale: locale,
              name: 'EUR',
              symbol: 'EU',
              decimalDigits: 3,
              customPattern: '¤ #,##0.000')
        ),
        (
          'simpleCurrency',
          {'locale': locale, 'name': 'EUR'},
          NumberFormat.simpleCurrency(locale: locale, name: 'EUR')
        ),
        (
          'compact',
          {'locale': locale, 'explicitSign': true},
          NumberFormat.compact(locale: locale, explicitSign: true)
        ),
        (
          'compactLong',
          {'locale': locale, 'explicitSign': true},
          NumberFormat.compactLong(locale: locale, explicitSign: true)
        ),
        (
          'compactCurrency',
          {'locale': locale, 'name': 'EUR', 'symbol': 'EU', 'decimalDigits': 2},
          NumberFormat.compactCurrency(
              locale: locale, name: 'EUR', symbol: 'EU', decimalDigits: 2)
        ),
        (
          'compactSimpleCurrency',
          {'locale': locale, 'name': 'EUR', 'decimalDigits': 2},
          NumberFormat.compactSimpleCurrency(
              locale: locale, name: 'EUR', decimalDigits: 2)
        ),
      ];
      for (final (constructor, args, native) in families) {
        final graph = _Graph();
        final formatter = graph.number(constructor, args);
        final root = graph.op('intl.number.format', ValueType.string,
            [formatter, graph.literal(1234.56789, ValueType.real)]);
        expect(graph.evaluate(root), native.format(1234.56789),
            reason: '$locale $constructor');
      }
    }
  });

  test('ordered NumberFormat setters retain native interactions', () {
    final graph = _Graph();
    var format = graph.number('decimalPattern', {'locale': 'en_US'});
    for (final (setter, value) in [
      ('minimumFractionDigits', 4),
      ('maximumFractionDigits', 2),
      ('minimumSignificantDigits', 3)
    ]) {
      format = graph.op(
          'intl.number.set',
          numberFormatterValueType,
          [format, graph.literal(value, ValueType.integer)],
          {'setter': setter});
    }
    format =
        graph.op('intl.number.noGrouping', numberFormatterValueType, [format]);
    final root = graph.op('intl.number.format', ValueType.string,
        [format, graph.literal(12345.6789, ValueType.real)]);
    final native = NumberFormat.decimalPattern('en_US')
      ..minimumFractionDigits = 4
      ..maximumFractionDigits = 2
      ..minimumSignificantDigits = 3
      ..turnOffGrouping();
    expect(graph.evaluate(root), native.format(12345.6789));
  });

  test('plural precision and gender/select fallback agree with intl', () {
    for (final locale in ['en_US', 'fr', 'ar', 'ru']) {
      for (final count in <num>[0, 1, 2, 3, 5, 11, 1.2]) {
        for (final precision in [null, 0, 2]) {
          final graph = _Graph();
          final root = graph.op('intl.plural', ValueType.string, [
            graph.literal(
                count, count is int ? ValueType.integer : ValueType.real),
            for (final v in [
              'zero',
              'one',
              'two',
              'few',
              'many',
              'other',
              locale
            ])
              graph.string(v),
            graph.literal(precision,
                precision == null ? ValueType.nullType : ValueType.integer),
          ], {
            'arguments': [
              'zero',
              'one',
              'two',
              'few',
              'many',
              'other',
              'locale',
              'precision'
            ]
          });
          expect(
              graph.evaluate(root),
              Intl.plural(count,
                  zero: 'zero',
                  one: 'one',
                  two: 'two',
                  few: 'few',
                  many: 'many',
                  other: 'other',
                  locale: locale,
                  precision: precision));
        }
      }
      for (final gender in ['female', 'male', 'unknown']) {
        final graph = _Graph();
        final root = graph.op('intl.gender', ValueType.string, [
          graph.string(gender),
          graph.string('she'),
          graph.string('they'),
          graph.string(locale)
        ], {
          'arguments': ['female', 'other', 'locale']
        });
        expect(graph.evaluate(root),
            Intl.gender(gender, female: 'she', other: 'they', locale: locale));
      }
      for (final choice in ['Status.active', 'active', 'absent']) {
        final graph = _Graph();
        final root = graph.op('intl.select', ValueType.string, [
          graph.string(choice),
          graph.string('exact'),
          graph.string('short'),
          graph.string('fallback'),
          graph.string(locale),
        ], {
          'keys': ['Status.active', 'active', 'other'],
          'arguments': ['locale']
        });
        expect(
            graph.evaluate(root),
            Intl.select(
                choice,
                {
                  'Status.active': 'exact',
                  'active': 'short',
                  'other': 'fallback'
                },
                locale: locale));
      }
    }
  });

  test(
      'omitted locale follows Intl.withLocale without substituting Flutter locale',
      () {
    for (final locale in ['fr', 'ar']) {
      Intl.withLocale(locale, () {
        final graph = _Graph();
        final formatter = graph.number('decimalPattern', {});
        final root = graph.op('intl.number.format', ValueType.string,
            [formatter, graph.literal(1234.5, ValueType.real)]);
        expect(
            graph.evaluate(root), NumberFormat.decimalPattern().format(1234.5));
      });
    }
  });

  test('nonselected plural arguments retain eager native failure', () {
    final graph = _Graph();
    final badDate = graph.op(
        'intl.datetime.new',
        dateTimeValueType,
        [graph.string('not a timestamp')],
        {'constructor': 'parse', 'arguments': <String>[]});
    final badBranch = graph.op('intl.date.format', ValueType.string,
        [graph.formatter('yMd', 'en_US'), badDate]);
    final root = graph.op('intl.plural', ValueType.string, [
      graph.literal(2, ValueType.integer),
      badBranch,
      graph.string('two')
    ], {
      'arguments': ['one', 'other']
    });
    expect(
        _failure(() => graph.evaluate(root)),
        _failure(() => Intl.plural(2,
            one: DateFormat.yMd('en_US')
                .format(DateTime.parse('not a timestamp')),
            other: 'two')));
  });

  test('DateTime constructors preserve overflow, offsets and microseconds', () {
    for (final utc in [false, true]) {
      final graph = _Graph();
      final root = graph.op('intl.datetime.new', dateTimeValueType, [
        for (final value in [2024, 2, 30, 17, 23, 41, 123, 456])
          graph.literal(value, ValueType.integer),
      ], {
        'constructor': utc ? 'utc' : '',
        'arguments': <String>[]
      });
      final native = utc
          ? DateTime.utc(2024, 2, 30, 17, 23, 41, 123, 456)
          : DateTime(2024, 2, 30, 17, 23, 41, 123, 456);
      expect(graph.evaluate(root), {
        'microsecondsSinceEpoch': native.microsecondsSinceEpoch,
        'isUtc': native.isUtc
      });
    }
    final graph = _Graph();
    final root = graph.op(
        'intl.datetime.new',
        dateTimeValueType,
        [graph.string('2024-02-29T17:23:41.123456+05:30')],
        {'constructor': 'parse', 'arguments': <String>[]});
    final native = DateTime.parse('2024-02-29T17:23:41.123456+05:30');
    expect(graph.evaluate(root), {
      'microsecondsSinceEpoch': native.microsecondsSinceEpoch,
      'isUtc': true
    });
  });

  test('DateTime.parse recipes preserve native invalid ISO errors', () {
    Object? result(Object? Function() compute) {
      try {
        return compute();
      } on Object catch (error) {
        return (error.runtimeType, error.toString());
      }
    }

    for (final source in ['', 'not a timestamp', '2024-02-29T12:00:00+bad']) {
      final graph = _Graph();
      final root = graph.op(
          'intl.datetime.new',
          dateTimeValueType,
          [graph.string(source)],
          {'constructor': 'parse', 'arguments': <String>[]});
      expect(result(() => graph.evaluate(root)),
          result(() => DateTime.parse(source)));
    }
  });

  test('native select retains untagged scalar choices', () {
    for (final (type, choice) in <(ValueType, Object)>[
      (ValueType.string, 'active'),
      (ValueType.integer, 1),
      (ValueType.real, 1.25),
      (ValueType.number, 2.5),
      (ValueType.boolean, true),
    ]) {
      final graph = _Graph();
      final root = graph.op('intl.select', ValueType.string, [
        graph.literal(choice, type),
        graph.string('exact'),
        graph.string('fallback'),
      ], {
        'keys': [choice, 'other'],
        'arguments': <String>[],
      });
      expect(graph.evaluate(root),
          Intl.select(choice, {choice: 'exact', 'other': 'fallback'}));
    }
  });

  test('unknown and translated named-message options cannot enter a recipe',
      () {
    final graph = _Graph();
    final root = graph.op('intl.plural', ValueType.string, [
      graph.literal(1, ValueType.integer),
      graph.string('other'),
      graph.string('message')
    ], {
      'arguments': ['other', 'name']
    });
    expect(() => graph.evaluate(root), throwsFormatException);
  });
  testWidgets(
      'nested String lists and inline spans share native value decoding',
      (tester) async {
    final graph = _Graph();
    final root = graph.op('intl.plural', ValueType.string, [
      graph.literal(2, ValueType.integer),
      graph.string('One'),
      graph.string('Two'),
    ], {
      'arguments': ['one', 'other']
    });
    final envelope =
        jsonEncode(ValueProgram(nodes: graph.nodes, root: root).encode());
    final value = '{version:1,program:$envelope,captures:{}}';
    final runtime = Runtime()
      ..update(const LibraryName(['restage', 'core']), buildCoreWidgetLibrary())
      ..update(
          const LibraryName(['test']),
          rfw.parseLibraryFile(
              'import restage.core; widget Root = Column(children:['
              'Text(text:["Items: ",$value]),'
              'TextRich(textSpan:{children:[{text:"Starts "},{text:$value}]})]);'));
    await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: RemoteWidget(
            runtime: runtime,
            data: DynamicContent(),
            widget: const FullyQualifiedWidgetName(
                LibraryName(['test']), 'Root'))));
    expect(find.text('Items: Two'), findsOneWidget);
    expect(find.text('Starts Two', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a native layout callback evaluates formatting from current constraints',
      (tester) async {
    const shape = ValueType('record', fields: {'maxWidth': ValueType.real});
    const values = ValueProgram(
        nodes: [
          ValueNode('parameter', shape, name: 'arg1'),
          ValueNode('field', ValueType.real, inputs: [0], name: 'maxWidth'),
          ValueNode('floor', ValueType.integer, inputs: [1]),
          ValueNode('literal', ValueType.string, value: 'One'),
          ValueNode('literal', ValueType.string, value: 'More'),
          ValueNode('intl.plural', ValueType.string, inputs: [
            2,
            3,
            4
          ], value: {
            'arguments': ['one', 'other']
          }),
        ],
        root: 5,
        parameters: {'arg1': shape});
    const program = BuilderProgram(
        values: values,
        result: BuilderResult.body(0, values: {'label': 5}),
        bodyCount: 1);
    final slot =
        '__RestageBuilderContinuation(version:1,program:${jsonEncode(program.encode())},captures:{},'
        'bodies:[(scope)=>Text(text:scope.values.label)])';
    for (final width in [1.0, 2.0]) {
      final runtime = Runtime()
        ..update(
            const LibraryName(['restage', 'core']), buildCoreWidgetLibrary())
        ..update(
            const LibraryName(['test']),
            rfw.parseLibraryFile(
                'import restage.core; widget Root = LayoutBuilder(builder:$slot);'));
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
      expect(find.text(width == 1 ? 'One' : 'More'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
  test('native select exact enum match precedes string fallback', () {
    final graph = _Graph();
    final root = graph.op('intl.select', ValueType.string, [
      graph.string('active'),
      graph.string('exact'),
      graph.string('short'),
      graph.string('fallback'),
    ], {
      'choiceEnum': 'package:fixture/status.dart#_Status',
      'keys': [
        {'enum': 'package:fixture/status.dart#_Status', 'name': 'active'},
        'active',
        'other'
      ],
      'arguments': <String>[]
    });
    expect(
        graph.evaluate(root),
        Intl.select(_Status.active,
            {_Status.active: 'exact', 'active': 'short', 'other': 'fallback'}));
  });

  test(
      'formatter construction fails before evaluating its later format argument',
      () {
    final graph = _Graph();
    final formatter = graph.formatter('yMd', 'unknown_locale');
    final badDate = graph.op(
        'intl.datetime.new',
        dateTimeValueType,
        [graph.string('bad date')],
        {'constructor': 'parse', 'arguments': <String>[]});
    final root =
        graph.op('intl.date.format', ValueType.string, [formatter, badDate]);
    final nativeFailure = _failure(() =>
        DateFormat.yMd('unknown_locale').format(DateTime.parse('bad date')));
    expect(nativeFailure, isNot('did not throw'));
    expect(_failure(() => graph.evaluate(root)), nativeFailure);
  });

  test('timezone skeletons retain the installed intl result', () {
    final graph = _Graph();
    final root = graph.op('intl.date.format', ValueType.string, [
      graph.formatter('jmv', 'en_US'),
      graph.date(DateTime.utc(2024, 2, 29))
    ]);
    Object? observe(Object? Function() compute) {
      try {
        return compute();
      } on Object catch (error) {
        return error.runtimeType;
      }
    }

    expect(
        observe(() => graph.evaluate(root)),
        observe(
            () => DateFormat.jmv('en_US').format(DateTime.utc(2024, 2, 29))));
  });
  testWidgets(
      'nested String and span programs read the current native locale context',
      (tester) async {
    const values = ValueProgram(
        nodes: [
          ValueNode('parameter', ValueType.string,
              name: 'context:device:languageCode'),
          ValueNode('intl.number.new', numberFormatterValueType, inputs: [
            0
          ], value: {
            'constructor': 'decimalPattern',
            'arguments': ['locale']
          }),
          ValueNode('literal', ValueType.real, value: 1234.5),
          ValueNode('intl.number.format', ValueType.string, inputs: [1, 2]),
        ],
        root: 3,
        parameters: {'context:device:languageCode': ValueType.string});
    final value =
        '{version:1,program:${jsonEncode(values.encode())},captures:{}}';
    final runtime = Runtime()
      ..update(const LibraryName(['restage', 'core']), buildCoreWidgetLibrary())
      ..update(
          const LibraryName(['test']),
          rfw.parseLibraryFile(
              'import restage.core; widget Root = Column(children:['
              'Text(text:["Price: ",$value]),Text(text:"Fonts",fontFamily:$value,fontFamilyFallback:[$value]),TextRich(textSpan:{children:[{text:$value,style:{fontFamily:$value}}]})]);'));
    for (final locale in ['fr', 'ar']) {
      await tester.pumpWidget(Localizations(
          locale: Locale(locale),
          delegates: const [DefaultWidgetsLocalizations.delegate],
          child: Directionality(
              textDirection: TextDirection.ltr,
              child: RemoteWidget(
                  runtime: runtime,
                  data: DynamicContent(),
                  widget: const FullyQualifiedWidgetName(
                      LibraryName(['test']), 'Root')))));
      final expected = NumberFormat.decimalPattern(locale).format(1234.5);
      expect(find.text('Price: $expected'), findsOneWidget);
      final fonts = tester.widget<Text>(find.text('Fonts'));
      expect(fonts.style!.fontFamily, expected);
      expect(fonts.style!.fontFamilyFallback, [expected]);
      final rich = tester.widget<RichText>(find.byWidgetPredicate((widget) =>
          widget is RichText && widget.text.toPlainText() == expected));
      bool hasFamily(InlineSpan span) =>
          span is TextSpan &&
          (span.style?.fontFamily == expected ||
              (span.children?.any(hasFamily) ?? false));
      expect(hasFamily(rich.text), isTrue);

      expect(find.text(expected, findRichText: true), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
  test('eager helper bindings preserve unused native formatter failures', () {
    final graph = _Graph();
    final invalid = graph.op(
        'intl.datetime.new',
        dateTimeValueType,
        [graph.string('not a date')],
        {'constructor': 'parse', 'arguments': <String>[]});
    final argument = graph.op('intl.date.format', ValueType.string,
        [graph.formatter('yMd', 'en_US'), invalid]);
    final helper =
        graph.op('let', ValueType.string, [argument, graph.string('safe')]);
    final root = graph.op('intl.plural', ValueType.string, [
      graph.literal(2, ValueType.integer),
      helper
    ], {
      'arguments': ['other']
    });
    String ignore(String unused) => 'safe';
    final nativeFailure = _failure(() => Intl.plural(2,
        other: ignore(
            DateFormat.yMd('en_US').format(DateTime.parse('not a date')))));
    expect(nativeFailure, isNot('did not throw'));
    expect(_failure(() => graph.evaluate(root)), nativeFailure);
  });

  testWidgets(
      'nested host DateTime captures preserve microseconds, UTC and updates',
      (tester) async {
    final graph = _Graph();
    final date = graph.op('capture', dateTimeValueType, []);
    graph.nodes[date] =
        const ValueNode('capture', dateTimeValueType, name: 'c0');
    final formatted = graph.op('intl.date.format', ValueType.string,
        [graph.formatter('y-MM-dd HH:mm:ss.SSS', 'en_US'), date]);
    final epoch = graph.op('field', ValueType.integer, [date]);
    graph.nodes[epoch] = ValueNode('field', ValueType.integer,
        inputs: [date], name: 'microsecondsSinceEpoch');
    final utc = graph.op('field', ValueType.boolean, [date]);
    graph.nodes[utc] =
        ValueNode('field', ValueType.boolean, inputs: [date], name: 'isUtc');
    final root = graph.op('concat', ValueType.string, [
      formatted,
      graph.string('|'),
      graph.op('string', ValueType.string, [epoch]),
      graph.string('|'),
      graph.op('string', ValueType.string, [utc])
    ]);
    final program = ValueProgram(
        nodes: graph.nodes,
        root: root,
        captures: const {'c0': dateTimeValueType});
    final runtime = Runtime()
      ..update(const LibraryName(['restage', 'core']), buildCoreWidgetLibrary())
      ..update(
          const LibraryName(['test']),
          rfw.parseLibraryFile(
              'import restage.core; widget Root = Text(text:{version:1,program:${jsonEncode(program.encode())},captures:{c0:data.calendar.entries.0.start}});'));
    final data = DynamicContent();
    for (final date in [
      DateTime.utc(2024, 2, 29, 17, 23, 41, 123, 456),
      DateTime(2024, 2, 29, 17, 23, 41, 123, 789)
    ]) {
      data.update('calendar', {
        'entries': [
          {
            'start': {
              'microsecondsSinceEpoch': date.microsecondsSinceEpoch,
              'isUtc': date.isUtc
            }
          }
        ]
      });
      await tester.pumpWidget(Directionality(
          textDirection: TextDirection.ltr,
          child: RemoteWidget(
              runtime: runtime,
              data: data,
              widget: const FullyQualifiedWidgetName(
                  LibraryName(['test']), 'Root'))));
      await tester.pump();
      final expected =
          '${DateFormat('y-MM-dd HH:mm:ss.SSS', 'en_US').format(date)}|${date.microsecondsSinceEpoch}|${date.isUtc}';
      expect(find.text(expected), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
