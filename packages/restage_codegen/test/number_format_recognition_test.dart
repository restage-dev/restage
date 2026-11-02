import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart' as rfw;
import 'package:test/test.dart';

import 'helpers.dart';

/// Resolved native formatters emit typed values, retaining their constructor
/// configuration and numeric input. Custom lookalikes remain unsupported.
void main() {
  late ExpressionTranslator translator;

  setUp(() {
    translator = ExpressionTranslator(
      catalog: kEmptyCatalog,
      helpers: HelperRegistry(),
    );
  });

  Future<TranslationResult> run(String body) async => translator.translate(
    await parseExpressionFromSourceForTest('''
import 'package:intl/intl.dart';
Object x() => $body;
'''),
  );

  void expectNumberProgram(
    TranslationResult result, {
    required String constructor,
    required Map<String, Object> arguments,
    required double amount,
  }) {
    expect(result.issues, isEmpty);
    final root =
        rfw
                .parseLibraryFile('widget Root = Slot(value: ${result.dsl});')
                .widgets
                .single
                .root
            as rfw.ConstructorCall;
    final slot = root.arguments['value']! as Map;
    expect(slot['version'], valueProgramVersion);
    expect(slot['captures'], isEmpty);
    final program = ValueProgram.decode(
      slot['program']! as String,
      operations: kIntlValueOperations,
    );
    expect(program.captures, isEmpty);
    expect(program.parameters, isEmpty);
    expect(
      valueProgramRequiredCapability(program, operations: kIntlValueOperations),
      23,
    );
    final format = program.nodes[program.root];
    expect(format.op, 'intl.number.format');
    expect(format.type.toJson(), ValueType.string.toJson());
    expect(format.inputs, hasLength(2));
    final formatter = program.nodes[format.inputs.first];
    expect(formatter.op, 'intl.number.new');
    expect(formatter.type.toJson(), numberFormatterValueType.toJson());
    expect(formatter.value, {
      'constructor': constructor,
      'arguments': arguments.keys.toList(),
    });
    expect(formatter.inputs, hasLength(arguments.length));

    void expectLiteral(int input, Object value) {
      final node = program.nodes[input];
      expect(node.op, 'literal');
      expect(node.value, value);
      expect(node.type.kind, switch (value) {
        String() => 'String',
        int() => 'int',
        double() => 'double',
        _ => throw StateError('Unexpected formatter argument'),
      });
    }

    final values = arguments.values.toList();
    for (var index = 0; index < values.length; index++) {
      expectLiteral(formatter.inputs[index], values[index]);
    }
    expectLiteral(format.inputs.last, amount);
  }

  group('resolved native currency values', () {
    test(
      'NumberFormat.currency preserves locale symbol and decimal digits',
      () async {
        final result = await run(
          "NumberFormat.currency(locale: 'en_US', symbol: 'USD', "
          'decimalDigits: 2).format(1234.5)',
        );
        expectNumberProgram(
          result,
          constructor: 'currency',
          arguments: {'locale': 'en_US', 'symbol': 'USD', 'decimalDigits': 2},
          amount: 1234.5,
        );
      },
    );

    test(
      'NumberFormat.simpleCurrency preserves its native constructor',
      () async {
        final result = await run(
          "NumberFormat.simpleCurrency(locale: 'en_US').format(9.99)",
        );
        expectNumberProgram(
          result,
          constructor: 'simpleCurrency',
          arguments: {'locale': 'en_US'},
          amount: 9.99,
        );
      },
    );
  });

  group('resolved native decimal values', () {
    test(
      'unnamed NumberFormat preserves the omitted native configuration',
      () async {
        final result = await run('NumberFormat().format(1234.5)');
        expectNumberProgram(
          result,
          constructor: '',
          arguments: {},
          amount: 1234.5,
        );
      },
    );

    test(
      'NumberFormat.decimalPattern preserves its positional locale',
      () async {
        final result = await run(
          "NumberFormat.decimalPattern('de_DE').format(1234.5)",
        );
        expectNumberProgram(
          result,
          constructor: 'decimalPattern',
          arguments: {'locale': 'de_DE'},
          amount: 1234.5,
        );
      },
    );
  });

  test('a custom NumberFormat.currency lookalike is refused', () async {
    final result = translator.translate(
      await parseExpressionFromSourceForTest('''
class NumberFormat {
  factory NumberFormat.currency({
    String? locale,
    String? symbol,
    int? decimalDigits,
  }) = NumberFormat._;
  NumberFormat._();
  String format(num n) => '';
}
Object x() => NumberFormat.currency(
  locale: 'en_US', symbol: 'USD', decimalDigits: 2,
).format(1234.5);
'''),
    );
    expect(result.dsl, isEmpty);
    expect(result.issues, isNotEmpty);
    expect(
      result.issues.map((i) => i.message).join('\n'),
      isNot(contains('RestagePrice')),
    );
  });

  test(
    'NumberFormat.percentPattern preserves its native constructor',
    () async {
      final result = await run(
        "NumberFormat.percentPattern('en_US').format(0.25)",
      );
      expectNumberProgram(
        result,
        constructor: 'percentPattern',
        arguments: {'locale': 'en_US'},
        amount: 0.25,
      );
    },
  );
}
