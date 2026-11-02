import 'package:restage_core/src/runtime/intl_value_operations.dart';
import 'package:restage_codegen/src/intl_format_recognition.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:restage_codegen/src/builder_expression_lowering.dart';
import 'package:restage_codegen/src/closed_callback_lowering.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';
import 'helpers.dart';

enum ReviewAxis { horizontal, vertical }

enum OtherReviewAxis { horizontal, vertical }

final class _NoCaptures implements ValueReader {
  @override
  int length(List<Object> path) => throw StateError('Unexpected capture');
  @override
  Object? read(List<Object> path, ValueType type) =>
      throw StateError('Unexpected capture');
}

final class _BorrowedRows implements ValueReader {
  _BorrowedRows(this.rows, {this.failure});
  final List<List<num>> rows;
  final String? failure;
  final reads = <String>[];
  Object? _at(List<Object> path) {
    Object? value = {'c0': rows};
    for (final segment in path) {
      value = segment is int
          ? (value! as List)[segment]
          : (value! as Map)[segment];
    }
    return value;
  }

  @override
  int length(List<Object> path) {
    reads.add('${path.join('.')}.length');
    return (_at(path)! as List).length;
  }

  @override
  Object? read(List<Object> path, ValueType type) {
    final key = path.join('.');
    reads.add(key);
    if (key == failure) throw StateError('Borrowed leaf failed');
    if (type.kind == 'list') return ValueListView(this, path, type.item!);
    return _at(path);
  }
}

void main() {
  const operations = {
    ...kCollectionValueOperations,
    ...kNativeIntlValueOperations,
  };
  Future<ValueProgram> lower(
    String body, {
    String parameters = '',
    String declarations = '',
    bool borrowed = false,
  }) async {
    final callback =
        await parseExpressionFromSourceForTest(
              '$declarations Object x($parameters) => () { $body };',
              rootPackage: 'apps_examples',
            )
            as FunctionExpression;
    final values = BuilderExpressionLowering(
      capture: (_) =>
          borrowed ? 'data.rows' : throw StateError('Unexpected capture'),
      extension: (value, lowering) => lowerIntlValue(value, lowering),
      operations: operations,
    );
    final root = closedValueCallback(values).body(callback.body);
    final program = values.program(root);
    return ValueProgram.decode(program.encode(), operations: operations);
  }

  Future<Object?> run(String body, {String declarations = ''}) async =>
      ValueEvaluator(
        await lower(body, declarations: declarations),
        captures: _NoCaptures(),
        parameters: {},
        operations: operations,
      ).evaluate();

  test(
    'collection helper receivers retain native failures or refuse',
    () async {
      const declarations = '''class ReviewHelper {
      int twice(int value) => value * 2;
      static int staticTwice(int value) => value * 2;
    }
    ReviewHelper badReceiver() => throw StateError('receiver');
    ReviewHelper get badGetter => throw StateError('getter');
    ReviewHelper? nullableReceiver() => null;
    int topTwice(int value) => value * 2;
    ''';
      for (final receiver in [
        'badReceiver()',
        'badGetter',
        'nullableReceiver()!',
      ]) {
        for (final callback in [
          '$receiver.twice',
          '(v) => $receiver.twice(v)',
        ]) {
          await expectLater(
            lower(
              'return [1].map($callback).first;',
              declarations: declarations,
            ),
            throwsA(isA<BuilderLoweringException>()),
            reason: callback,
          );
        }
      }
      _ReviewHelper fail() => throw StateError('receiver');
      expect(() => [1].map(fail().twice).first, throwsStateError);
      expect(() => [1].map((v) => fail().twice(v)).first, throwsStateError);
      expect(() => [1].map(_badReviewGetter.twice).first, throwsStateError);
      expect(
        () => [1].map((v) => _badReviewGetter.twice(v)).first,
        throwsStateError,
      );
      _ReviewHelper? nullable() => null;
      expect(() => [1].map(nullable()!.twice).first, throwsA(isA<TypeError>()));
      expect(
        () => [1].map((v) => nullable()!.twice(v)).first,
        throwsA(isA<TypeError>()),
      );
      for (final callback in [
        'topTwice',
        'ReviewHelper.staticTwice',
        '(v) => topTwice(v)',
        '(v) => ReviewHelper.staticTwice(v)',
      ]) {
        expect(
          await run(
            'return [1].map($callback).first;',
            declarations: declarations,
          ),
          2,
          reason: callback,
        );
      }
    },
  );

  test('collection callbacks admit implicit own instance helpers', () async {
    for (final callback in ['twice', '(v) => twice(v)']) {
      final probe = await parseMethodExpressionFromSourceForTest(
        'class P { int twice(int v) => v * 2; Object build() => () { return [1].map($callback).first; }; }',
        className: 'P',
        rootPackage: 'apps_examples',
      );
      final values = BuilderExpressionLowering(
        capture: (_) => throw StateError('capture'),
        operations: operations,
      );
      final root = closedValueCallback(
        values,
      ).body((probe.expression as FunctionExpression).body);
      expect(
        ValueEvaluator(
          values.program(root),
          captures: _NoCaptures(),
          parameters: {},
          operations: operations,
        ).evaluate(),
        2,
      );
    }
  });

  test('native lazy map retains live locals on each traversal', () async {
    final actual = await run('''
      var factor = 1;
      final mapped = [1, 2].map((item) => item * factor);
      factor = 2;
      final first = mapped.toList();
      factor = 3;
      final second = mapped.toList();
      return [first, second];
    ''');
    var factor = 1;
    final mapped = [1, 2].map((item) => item * factor);
    factor = 2;
    final first = mapped.toList();
    factor = 3;
    expect(actual, [first, mapped.toList()]);
  });
  test('mapped length skips callbacks; where length demands them', () async {
    expect(
      await run(
        '''var calls = 0; final values = [1, 2, 3].map((v) { calls++; return v; });
      final count = values.length; return calls * 10 + count;''',
      ),
      3,
    );
    expect(
      await run(
        '''var calls = 0; final values = [1, 2, 3].where((v) { calls++; return v > 1; });
      final count = values.length; return calls * 10 + count;''',
      ),
      32,
    );
  });
  test('short circuit never reaches throwing second mapper item', () async {
    expect(
      await run('return [1, 0].map((v) => 1 ~/ v).firstWhere((v) => v == 1);'),
      1,
    );
    expect(
      await run('return [1, 0].map((v) => 1 ~/ v).any((v) => v == 1);'),
      true,
    );
  });
  test('fold, reduce, terminal and search methods use native results', () async {
    final cases = <String, Object?>{
      'return [1, 2, 3].fold<int>(0, (sum, item) => sum + item);': [
        1,
        2,
        3,
      ].fold<int>(0, (a, b) => a + b),
      'return [1, 2, 3].reduce((a, b) => a + b);': [
        1,
        2,
        3,
      ].reduce((a, b) => a + b),
      'return [1, 2, 3].where((i) => i > 1).join(",");': [
        1,
        2,
        3,
      ].where((i) => i > 1).join(','),
      'return [1, 2, 1].lastIndexWhere((i) => i == 1, 1);': [
        1,
        2,
        1,
      ].lastIndexWhere((i) => i == 1, 1),
      'return [1, 2, 1].indexOf(1, 1);': [1, 2, 1].indexOf(1, 1),
      'return [1, 2, 1].lastIndexOf(1);': [1, 2, 1].lastIndexOf(1),
      'return [1, 2].firstWhere((i) => i == 3, orElse: () => 9);': [
        1,
        2,
      ].firstWhere((i) => i == 3, orElse: () => 9),
      'return [1, 2, 3].skip(1).take(1).single;': [
        1,
        2,
        3,
      ].skip(1).take(1).single,
      'return [1, 2, 3].takeWhile((i) => i < 3).skipWhile((i) => i < 2).last;':
          [1, 2, 3].takeWhile((i) => i < 3).skipWhile((i) => i < 2).last,
    };
    for (final entry in cases.entries)
      expect(await run(entry.key), entry.value, reason: entry.key);
  });
  test('negative counts and empty reduce retain native failures', () async {
    await expectLater(run('return [1, 2].take(-1);'), throwsRangeError);
    await expectLater(run('return [1, 2].skip(-1);'), throwsRangeError);
    await expectLater(
      run('return <int>[].reduce((a, b) => a + b);'),
      throwsStateError,
    );
  });
  test('explicit materialization is typed and retains fixed length', () async {
    final result = await run(
      'return [1, 2].map((i) => i + 1).toList(growable: false);',
    );
    expect(result, isA<List<int>>());
    expect(() => (result! as List<int>).add(4), throwsUnsupportedError);
    expect(await run('return List<int>.of([1, 2]);'), isA<List<int>>());
  });
  test(
    'sorting preserves fresh list aliases and native comparator order',
    () async {
      expect(
        await run('''final sorted = [3, 1, 2].toList(); final alias = sorted;
      sorted.sort((a, b) => a.compareTo(b)); return alias;'''),
        [1, 2, 3],
      );
    },
  );
  test('scalar collections preserve nested spread if and for evaluation', () async {
    expect(
      await run(
        "return [0, for (final x in [1, 2, 3].where((x) => x > 1)) if (x == 2) ...[x, x + 1] else x, ...?null];",
      ),
      [0, 2, 3, 3],
    );
    expect(
      await run(
        "var calls = 0; final items = [for (final x in [1, 2]) ++calls, ++calls]; return items;",
      ),
      [1, 2, 3],
    );
    expect(await run("return [3, 1, 2].toList()..sort();"), [1, 2, 3]);
  });
  test(
    'named-first orElse remains deferred with native argument order',
    () async {
      expect(
        await run(
          "var count = 0; final result = [1].firstWhere(orElse: () { count += 10; return 9; }, (i) { count++; return true; }); return result * 10 + count;",
        ),
        11,
      );
    },
  );
  test(
    'enclosing clock reads once and lazy item clocks read per demand and traversal',
    () async {
      final program = await lower("""
      final outer = DateTime.now().microsecondsSinceEpoch;
      final items = [1, 2, 3].map((item) => outer + DateTime.now().microsecondsSinceEpoch);
      final first = items.take(1).toList();
      final second = items.take(2).toList();
      return [first, second];
    """);
      var reads = 0;
      final installed = {
        ...operations,
        'clock.now': ClockNowOperation(
          read: () => DateTime.fromMicrosecondsSinceEpoch(++reads),
        ),
      };
      final value = ValueEvaluator(
        program,
        captures: _NoCaptures(),
        parameters: {},
        operations: installed,
      ).evaluate();
      expect(value, [
        [3],
        [4, 5],
      ]);
      expect(reads, 4);
      expect(
        valueProgramRequiredCapability(program, operations: installed),
        24,
      );
    },
  );
  test(
    'named-first copy arguments evaluate before source and native downcasts throw',
    () async {
      expect(
        await run(
          'var count = 0; return List<int>.of(growable: ++count == 1, [++count]);',
        ),
        [2],
      );
      await expectLater(
        run('return List<int>.from(<num>[1, 2.5]);'),
        throwsA(isA<TypeError>()),
      );
      expect(await run('return List<num>.of([1, 2]);'), isA<List<num>>());
    },
  );
  test('fresh mutable list locals sort with aliases', () async {
    expect(
      await run(
        'var sorted = [3, 2, 1].toList(); final alias = sorted; sorted.sort(); return alias;',
      ),
      [1, 2, 3],
    );
  });
  test(
    'temporal collection equality uses native values and zone identity',
    () async {
      expect(
        await run(
          'return [DateTime.utc(2024)].contains(DateTime.utc(2024).toLocal());',
        ),
        [DateTime.utc(2024)].contains(DateTime.utc(2024).toLocal()),
      );
      expect(
        await run(
          'return [Duration(microseconds: -1), Duration()].indexOf(Duration(microseconds: -1));',
        ),
        [
          const Duration(microseconds: -1),
          Duration(),
        ].indexOf(const Duration(microseconds: -1)),
      );
      expect(
        await run(
          'return [DateTime.utc(2024), DateTime.utc(2024)].lastIndexOf(DateTime.utc(2024));',
        ),
        1,
      );
    },
  );
  test(
    'same-unit callback helper uses the shared closed body compiler',
    () async {
      final callback =
          await parseExpressionFromSourceForTest(
                'int twice(int value) { var result = value; result *= 2; return result; } Object x() => () { return [1, 2].map(twice).toList(); };',
                rootPackage: 'apps_examples',
              )
              as FunctionExpression;
      final expressions = BuilderExpressionLowering(
        capture: (_) => throw StateError('Unexpected capture'),
        operations: operations,
      );
      final root = closedValueCallback(expressions).body(callback.body);
      expect(
        ValueEvaluator(
          expressions.program(root),
          captures: _NoCaptures(),
          parameters: {},
          operations: operations,
        ).evaluate(),
        [2, 4],
      );
    },
  );

  test(
    'explicit map generic preserves widening and nullable output types',
    () async {
      expect(
        await run('return [1, 2].map<num>((item) => item).toList();'),
        isA<List<num>>(),
      );
      expect(
        await run('return [1, 2].map<int?>((item) => null).toList();'),
        isA<List<int?>>(),
      );
    },
  );

  test('sort uses the native comparator algorithm for duplicate keys', () async {
    final native = [
      [2, 0],
      [1, 1],
      [2, 2],
      [1, 3],
      [2, 4],
    ].toList();
    var trace = '';
    native.sort((a, b) {
      trace += '${a[1]}:${b[1]},';
      return a[0].compareTo(b[0]);
    });
    final actual = await run(
      r"var trace = ''; final items = [[2, 0], [1, 1], [2, 2], [1, 3], [2, 4]].toList(); items.sort((a, b) { trace += '${a[1]}:${b[1]},'; return a[0].compareTo(b[0]); }); return trace;",
    );
    expect(actual, trace);
  });

  test(
    'nullable bounded Iterable locals retain native null-aware spread',
    () async {
      expect(
        await run(
          'Iterable<int>? items = null; final first = [...?items]; items = [1, 2]; return [first, [...?items]];',
        ),
        [
          <int>[],
          [1, 2],
        ],
      );
    },
  );
  test(
    'explicit fresh literals sort while const list mutation is refused',
    () async {
      expect(await run('return [3, 1, 2]..sort();'), [1, 2, 3]);
      await expectLater(
        lower('final values = const [3, 1, 2]; values.sort(); return values;'),
        throwsA(isA<BuilderLoweringException>()),
      );
    },
  );
  test(
    'const composite lists retain their refusal through aliases and nesting',
    () async {
      expect(
        () => (const <int>[
          ...[3, 1, 2],
        ]).sort(),
        throwsUnsupportedError,
      );
      for (final body in [
        'final values = const <int>[...[3, 1, 2]]; values.sort(); return values;',
        'final values = const <int>[if (true) 3, 1, 2]; final alias = values; alias.sort(); return values;',
        'var values = const <int>[...[if (true) 3], 1, 2]; values.sort(); return values;',
      ]) {
        await expectLater(
          lower(body),
          throwsA(isA<BuilderLoweringException>()),
        );
      }
      expect(
        await run(
          'final values = const <int>[...[3, 1, 2]]; return values.toList()..sort();',
        ),
        [1, 2, 3],
      );
      expect(
        await run(
          'final values = <int>[...const [3, 1, 2]]; values.sort(); return values;',
        ),
        [1, 2, 3],
      );
    },
  );

  test(
    'join refuses aggregates instead of stringifying projected native records',
    () async {
      for (final body in [
        'return [[DateTime.utc(2024)]].join();',
        'return [[Duration(microseconds: 1)]].join();',
        'return [[1, 2]].join();',
      ])
        await expectLater(
          lower(body),
          throwsA(isA<BuilderLoweringException>()),
        );
      expect(
        await run("return <int?>[1, null, 2].join(',');"),
        <int?>[1, null, 2].join(','),
      );
    },
  );

  test(
    'nested Iterable outputs are refused during validation before evaluation',
    () async {
      for (final body in [
        'return [1, 2].map((v) => [v].map((x) => x)).length;',
        'return [[1].map((x) => x)];',
      ])
        await expectLater(lower(body), throwsFormatException);
      expect([1, 2].map((v) => [v].map((x) => x)).length, 2);
    },
  );

  Future<Object?> borrowed(
    String body,
    _BorrowedRows reader, {
    String item = 'int',
  }) async {
    final program = await lower(
      body,
      parameters: 'List<List<$item>> rows',
      borrowed: true,
    );
    return ValueEvaluator(
      program,
      captures: reader,
      parameters: {},
      operations: operations,
    ).evaluate();
  }

  test(
    'borrowed nested list copies reify lazily and preserve shallow aliases',
    () async {
      final rows = <List<int>>[
        [1, 2],
        [3],
      ];
      final reader = _BorrowedRows(rows, failure: 'c0.1.0');
      final copied = await borrowed(
        'return rows.toList(growable: false);',
        reader,
      );
      expect(copied, isA<List<List<int>>>());
      expect(reader.reads, isNot(contains('c0.0.0')));
      expect(reader.reads, isNot(contains('c0.1.0')));
      final typed = copied! as List<List<int>>;
      expect(() => typed.add(<int>[]), throwsUnsupportedError);
      expect(() => typed.first.add(4), throwsUnsupportedError);
      rows.first[0] = 9;
      expect(typed.first.first, 9);
      expect(() => typed.last.first, throwsStateError);
      final aliases =
          (await borrowed(
                'return [rows, rows.toList()];',
                _BorrowedRows(rows),
              ))!
              as List<List<List<int>>>;
      expect(identical(aliases[0].first, aliases[1].first), isTrue);
      expect(identical(rows.first, rows.toList().first), isTrue);
    },
  );

  test(
    'borrowed nested transforms preserve mapper demand and throwing leaf order',
    () async {
      final skipped = _BorrowedRows(<List<int>>[
        [1],
        [2],
      ], failure: 'c0.1.0');
      expect(
        await borrowed('return rows.map((row) => row.first).length;', skipped),
        2,
      );
      expect(skipped.reads, isNot(contains('c0.0')));
      final first = _BorrowedRows(<List<int>>[
        [1],
        [2],
      ], failure: 'c0.1.0');
      expect(
        await borrowed(
          'return rows.map((row) => row.first).take(1).toList();',
          first,
        ),
        [1],
      );
      expect(first.reads, isNot(contains('c0.1.0')));
      await expectLater(
        borrowed('return rows.map((row) => row.first).skip(1).first;', first),
        throwsStateError,
      );
      for (final body in [
        'return rows.map((row) => row).toList();',
        'return rows.where((row) => row.isNotEmpty).toList();',
        'return rows.reversed.toList();',
      ]) {
        expect(
          await borrowed(
            body,
            _BorrowedRows(<List<int>>[
              [1],
              [2],
            ]),
          ),
          isA<List<List<int>>>(),
        );
      }
    },
  );

  test(
    'borrowed list reification keeps argument failures and native downcasts ordered',
    () async {
      final reader = _BorrowedRows(<List<int>>[
        [1],
        [2],
      ], failure: 'c0.0.0');
      await expectLater(
        borrowed('return rows.toList(growable: (1 ~/ 0) == 0);', reader),
        throwsA(isA<IntegerDivisionByZeroException>()),
      );
      expect(reader.reads, ['c0']);
      final source = <List<num>>[
        <num>[1],
        <num>[2],
      ];
      expect(() => List<List<double>>.from(source), throwsA(isA<TypeError>()));
      final narrowed = _BorrowedRows(source);
      await expectLater(
        borrowed(
          'return List<List<double>>.from(rows);',
          narrowed,
          item: 'num',
        ),
        throwsA(isA<BuilderLoweringException>()),
      );
      expect(narrowed.reads, isEmpty);
      final widened = await borrowed(
        'return List<List<num>>.of(rows);',
        _BorrowedRows(<List<int>>[
          [1],
          [2],
        ]),
      );
      expect(widened, isA<List<List<num>>>());
    },
  );
  test(
    'join refuses projected enum values instead of changing native strings',
    () async {
      final native = [ReviewAxis.horizontal].join();
      expect(native, 'ReviewAxis.horizontal');
      expect(native, isNot('horizontal'));
      for (final body in [
        'return [ReviewAxis.horizontal].join();',
        'return <ReviewAxis?>[ReviewAxis.horizontal, null].join();',
        'return [1].map((value) => ReviewAxis.horizontal).join();',
        'return [ReviewAxis.horizontal].where((value) => true).toList().join();',
      ]) {
        await expectLater(
          lower(body, declarations: 'enum ReviewAxis { horizontal, vertical }'),
          throwsA(
            isA<BuilderLoweringException>().having(
              (error) => error.reason,
              'reason',
              contains('native scalar elements'),
            ),
          ),
        );
      }
      expect(await run("return ['horizontal'].join();"), ['horizontal'].join());
    },
  );

  test(
    'scalar collection boundaries reject native projections before comparing or sorting',
    () async {
      expect(<Object>['horizontal'].contains(ReviewAxis.horizontal), isFalse);
      expect(<Object>[ReviewAxis.horizontal].contains('horizontal'), isFalse);
      for (final body in [
        "return ['horizontal'].contains(ReviewAxis.horizontal);",
        "return [ReviewAxis.horizontal].contains('horizontal');",
        'return [ReviewAxis.horizontal].indexOf(ReviewAxis.horizontal);',
        'return [ReviewAxis.horizontal].lastIndexOf(ReviewAxis.horizontal);',
        'return [ReviewAxis.vertical, ReviewAxis.horizontal].toList()..sort();',
        'return [FontWeight.w400].join();',
        'return [FontWeight.w400].contains(400);',
        'return [400].contains(FontWeight.w400);',
        'return [FontWeight.w400, FontWeight.w100].toList()..sort();',
      ]) {
        await expectLater(
          lower(
            body,
            declarations:
                "import 'package:flutter/widgets.dart'; enum ReviewAxis { horizontal, vertical }",
          ),
          throwsA(isA<BuilderLoweringException>()),
        );
      }
      expect(await run('return [1, 2].contains(1.0);'), [1, 2].contains(1.0));
    },
  );
  const axisDeclarations =
      'enum ReviewAxis { horizontal, vertical } enum OtherReviewAxis { horizontal, vertical }';

  test(
    'List.from refuses native domains that share erased scalar or record shapes',
    () async {
      final cases = <(String, Object? Function())>[
        (
          'return List<String>.from(<ReviewAxis>[ReviewAxis.horizontal]).join();',
          () => List<String>.from(<ReviewAxis>[ReviewAxis.horizontal]).join(),
        ),
        (
          'final axes = [ReviewAxis.horizontal]; return List<String>.from(axes).join();',
          () {
            final axes = [ReviewAxis.horizontal];
            return List<String>.from(axes).join();
          },
        ),
        (
          'return List<DateTime>.from(<Duration>[Duration()]).length;',
          () => List<DateTime>.from(<Duration>[Duration()]).length,
        ),
        (
          'return List<Duration>.from(<DateTime>[DateTime.utc(2024)]).length;',
          () => List<Duration>.from(<DateTime>[DateTime.utc(2024)]).length,
        ),
        (
          'return List<ReviewAxis>.from(<String>["horizontal"]).map((axis) => axis.name).join();',
          () => List<ReviewAxis>.from(<String>[
            'horizontal',
          ]).map((axis) => axis.name).join(),
        ),
        (
          'return List<OtherReviewAxis>.from(<ReviewAxis>[ReviewAxis.horizontal]).length;',
          () => List<OtherReviewAxis>.from(<ReviewAxis>[
            ReviewAxis.horizontal,
          ]).length,
        ),
        (
          'return List<String>.from(growable: false, <ReviewAxis>[ReviewAxis.horizontal].where((axis) => true));',
          () => List<String>.from(
            growable: false,
            <ReviewAxis>[ReviewAxis.horizontal].where((axis) => true),
          ),
        ),
      ];
      for (final (source, native) in cases) {
        expect(native, throwsA(isA<TypeError>()), reason: source);
        await expectLater(
          lower(source, declarations: axisDeclarations),
          throwsA(
            isA<BuilderLoweringException>().having(
              (error) => error.reason,
              'reason',
              contains('preserved native element domains'),
            ),
          ),
          reason: source,
        );
      }
    },
  );

  test(
    'List.from checks native element domains recursively inside nested Lists',
    () async {
      final cases = <(String, Object? Function())>[
        (
          'return List<List<String>>.from(<List<ReviewAxis>>[[ReviewAxis.horizontal]]).length;',
          () => List<List<String>>.from(<List<ReviewAxis>>[
            [ReviewAxis.horizontal],
          ]).length,
        ),
        (
          'return List<List<DateTime>>.from(<List<Duration>>[[Duration()]]).length;',
          () => List<List<DateTime>>.from(<List<Duration>>[
            [Duration()],
          ]).length,
        ),
        (
          'return List<List<ReviewAxis>>.from(<List<String>>[["horizontal"]]).length;',
          () => List<List<ReviewAxis>>.from(<List<String>>[
            ['horizontal'],
          ]).length,
        ),
        (
          'return List<List<double>>.from(<List<int>>[[1]]).length;',
          () => List<List<double>>.from(<List<int>>[
            [1],
          ]).length,
        ),
      ];
      for (final (source, native) in cases) {
        expect(native, throwsA(isA<TypeError>()), reason: source);
        await expectLater(
          lower(source, declarations: axisDeclarations),
          throwsA(
            isA<BuilderLoweringException>().having(
              (error) => error.reason,
              'reason',
              contains('preserved native element domains'),
            ),
          ),
          reason: source,
        );
      }
    },
  );

  test(
    'supported copies retain native scalar cast failures and same nominal domains',
    () async {
      final errors = <(String, Object? Function())>[
        (
          'return List<int>.from(<num>[1, 2.5]).length;',
          () => List<int>.from(<num>[1, 2.5]).length,
        ),
        (
          'return List<ReviewAxis>.from(<ReviewAxis?>[null]).length;',
          () => List<ReviewAxis>.from(<ReviewAxis?>[null]).length,
        ),
        (
          'return List<DateTime>.from(<DateTime?>[null]).length;',
          () => List<DateTime>.from(<DateTime?>[null]).length,
        ),
      ];
      for (final (source, native) in errors) {
        expect(native, throwsA(isA<TypeError>()), reason: source);
        await expectLater(
          run(source, declarations: axisDeclarations),
          throwsA(isA<TypeError>()),
          reason: source,
        );
      }
      for (final constructor in ['of', 'from']) {
        expect(
          await run(
            'return List<ReviewAxis>.$constructor(<ReviewAxis>[ReviewAxis.horizontal]).map((axis) => axis.name).toList().join();',
            declarations: axisDeclarations,
          ),
          'horizontal',
        );
        expect(
          await run(
            'return List<DateTime>.$constructor(<DateTime>[DateTime.utc(2024)]).first.year;',
          ),
          2024,
        );
        expect(
          await run('return List<num>.$constructor(<int>[1, 2]);'),
          isA<List<num>>(),
        );
      }
      expect(
        await run('return List<List<num>>.from(<List<int>>[[1, 2]]);'),
        isA<List<List<num>>>(),
      );
    },
  );

  test(
    'unadmitted list conversion factories and cast routes remain refused',
    () async {
      for (final source in [
        'return List<String>.unmodifiable(<ReviewAxis>[ReviewAxis.horizontal]).join();',
        'return List<int>.generate(2, (index) => index);',
        'return [ReviewAxis.horizontal].cast<String>().join();',
        'return List.castFrom<ReviewAxis, String>([ReviewAxis.horizontal]).join();',
      ])
        await expectLater(
          lower(source, declarations: axisDeclarations),
          throwsA(isA<BuilderLoweringException>()),
          reason: source,
        );
    },
  );
  test(
    'unsafe nested downcasts are refused when borrowed runtime generics are unknown',
    () async {
      final List<List<num>> native = <List<int>>[
        [1],
      ];
      expect(List<List<int>>.from(native), [
        [1],
      ]);
      final reader = _BorrowedRows(native);
      await expectLater(
        borrowed(
          'return List<List<int>>.from(rows).length;',
          reader,
          item: 'num',
        ),
        throwsA(isA<BuilderLoweringException>()),
      );
      expect(reader.reads, isEmpty);
    },
  );
}

final class _ReviewHelper {
  int twice(int value) => value * 2;
}

_ReviewHelper get _badReviewGetter => throw StateError('getter');
