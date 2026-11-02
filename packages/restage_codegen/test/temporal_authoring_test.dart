import 'dart:io';
import 'dart:convert';

import 'package:restage_codegen/src/catalog_validator.dart';
import 'package:restage_codegen/src/builder_expression_lowering.dart';
import 'package:restage_codegen/src/closed_callback_lowering.dart';
import 'package:restage_codegen/src/intl_format_recognition.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:restage_core/src/runtime/intl_value_operations.dart';
import 'package:restage_compiler_core/restage_compiler_core.dart';

import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart' as rfw;
import 'package:test/test.dart';

import 'support/intl_format_authoring.dart';
import 'support/temporal_authoring.dart';
import 'support/temporal_collection_authoring.dart';
import 'support/collection_authoring.dart';
import 'helpers.dart';

final class _Reader implements ValueReader {
  _Reader([this.values = const {}]);
  final Map<String, Object?> values;
  @override
  Object? read(List<Object> path, ValueType type) {
    Object? value = values;
    for (final key in path) {
      value = key is int ? (value! as List)[key] : (value! as Map)[key];
    }
    return value;
  }

  @override
  int length(List<Object> path) =>
      (read(path, ValueType.integer)! as List).length;
}

List<rfw.ConstructorCall> _clockSlots(Object? value) {
  final slots = <rfw.ConstructorCall>[];
  void visit(Object? value) {
    if (value is rfw.ConstructorCall) {
      if (value.name == kBuilderContinuationWidgetName) slots.add(value);
      for (final argument in value.arguments.values) visit(argument);
    } else if (value is rfw.WidgetBuilderDeclaration) {
      visit(value.widget);
    } else if (value is List) {
      value.forEach(visit);
    } else if (value is Map) {
      value.values.forEach(visit);
    }
  }

  visit(value);
  return slots;
}

void main() {
  for (final key in temporalCollectionSources.keys) {
    test('clock collection source passes catalog and capability: $key', () async {
      final (source, catalog) = await compileCollectionAuthoring(
        authoredSource: temporalCollectionSources[key]!,
      );
      final fixture =
          (jsonDecode(
                File(
                  '../restage_core/test/fixtures/temporal_collection_programs.json',
                ).readAsStringSync(),
              )
              as Map)[key];
      expect(source, fixture);
      final library = rfw.parseLibraryFile(source);
      expect(validateModelAgainstCatalog(library, catalog), isEmpty);
      expect(deriveSurfaceCapability(library, catalog).builtInFloor, 24);
      if (const {
        'strings',
        'records',
        'aliases',
        'colors',
        'helper',
      }.contains(key))
        expect(source, contains('forEachItem'));
    });
  }
  test(
    'clock collection catalog scope isolates roots and honors installed operations',
    () async {
      final (source, catalog) = await compileCollectionAuthoring(
        authoredSource: temporalCollectionSources['strings']!,
      );
      final library = rfw.parseLibraryFile(source);
      final slots = _clockSlots(library.widgets.single.root);
      final orphaned = rfw.RemoteWidgetLibrary(library.imports, [
        ...library.widgets,
        rfw.WidgetDeclaration('Orphan', null, slots[1]),
      ]);
      expect(
        () => validateModelAgainstCatalog(orphaned, catalog),
        throwsFormatException,
      );
      expect(
        () => validateModelAgainstCatalog(
          library,
          catalog,
          operations: kIntlValueOperations,
        ),
        throwsFormatException,
      );
    },
  );

  for (final key in ['strings', 'records']) {
    test(
      'enclosing clock and live frame survive authored for-in: $key',
      () async {
        final (source, _) = await compileCollectionAuthoring(
          authoredSource: temporalCollectionSources[key]!,
        );
        final slots = _clockSlots(
          rfw.parseLibraryFile(source).widgets.single.root,
        );
        expect(slots, hasLength(2));
        var reads = 0;
        final installed = {
          ...kCollectionValueOperations,
          ...kNativeIntlValueOperations,
          'clock.now': ClockNowOperation(
            read: () => DateTime.fromMicrosecondsSinceEpoch(++reads),
          ),
        };
        for (var invocation = 0; invocation < 2; invocation++) {
          final outer = BuilderProgram.decode(
            slots[0].arguments['program']! as String,
            operations: installed,
          ).invoke(captures: _Reader(), parameters: {}, operations: installed);
          final sample = key == 'strings'
              ? invocation * 4 + 1
              : invocation * 3 + 1;
          expect(reads, sample);
          final context = ValueOperationContext(
            operations: installed,
            frame: outer.frame,
            locals: outer.frame!.visibleTypes,
          );
          final program = BuilderProgram.decode(
            slots[1].arguments['program']! as String,
            operations: installed,
            context: context,
          );
          final rows = program.invokeAll(
            captures: _Reader(),
            parameters: {},
            operations: installed,
            context: context,
          );
          final labels = rows.map((row) => row.values.values.single).toList();
          expect(
            labels,
            key == 'strings'
                ? [
                    'one:$sample|${sample + 1}|${sample + 1}|1',
                    'two:$sample|${sample + 2}|${sample + 2}|2',
                    'three:$sample|${sample + 3}|${sample + 3}|3',
                    'visited3',
                  ]
                : [
                    '2024:$sample|${sample + 1}|${sample + 1}',
                    '2025:$sample|${sample + 2}|${sample + 2}',
                  ],
          );
          expect(reads, sample + (key == 'strings' ? 3 : 2));
        }
      },
    );
  }
  test(
    'primitive and temporal aggregate aliases retain their evaluated samples',
    () async {
      final (source, _) = await compileCollectionAuthoring(
        authoredSource: temporalCollectionSources['aliases']!,
      );
      final slots = _clockSlots(
        rfw.parseLibraryFile(source).widgets.single.root,
      );
      expect(slots, hasLength(2));
      var reads = 0;
      final installed = {
        ...kCollectionValueOperations,
        ...kNativeIntlValueOperations,
        'clock.now': ClockNowOperation(
          read: () => DateTime.fromMicrosecondsSinceEpoch(++reads),
        ),
      };
      final parent = BuilderProgram.decode(
        slots[0].arguments['program']! as String,
        operations: installed,
      ).invoke(captures: _Reader(), parameters: {}, operations: installed);
      expect(reads, 4);
      final context = ValueOperationContext(
        operations: installed,
        frame: parent.frame,
        locals: parent.frame!.visibleTypes,
      );
      final captures = <String, Object?>{};
      for (final entry in (slots[1].arguments['captures']! as Map).entries) {
        final reference = entry.value as rfw.WidgetBuilderArgReference;
        expect(reference.parts.first, 'values');
        captures[entry.key as String] = parent.values[reference.parts.last];
      }
      final program = BuilderProgram.decode(
        slots[1].arguments['program']! as String,
        operations: installed,
        context: context,
      );
      final rows = program.invokeAll(
        captures: _Reader(captures),
        parameters: {},
        operations: installed,
        context: context,
      );
      expect(rows.map((row) => row.values.values.single), [
        'one:1|2|3|4',
        'two:1|2|3|4',
      ]);
      expect(reads, 4);
    },
  );

  for (final key in ['colors', 'helper']) {
    test(
      'native aggregate initializer is retained across callback programs: $key',
      () async {
        final (source, _) = await compileCollectionAuthoring(
          authoredSource: temporalCollectionSources[key]!,
        );
        final slots = _clockSlots(
          rfw.parseLibraryFile(source).widgets.single.root,
        );
        expect(slots, hasLength(key == 'helper' ? 3 : 2));
        var reads = 0;
        final installed = {
          ...kCollectionValueOperations,
          ...kNativeIntlValueOperations,
          'clock.now': ClockNowOperation(
            read: () => DateTime.fromMicrosecondsSinceEpoch(++reads),
          ),
        };
        for (var invocation = 0; invocation < 2; invocation++) {
          ValueOperationContext? context;
          for (final slot in slots.take(slots.length - 1)) {
            final program = BuilderProgram.decode(
              slot.arguments['program']! as String,
              operations: installed,
              context: context,
            );
            final result = program.invoke(
              captures: _Reader(),
              parameters: {},
              operations: installed,
              context: context,
            );
            context = ValueOperationContext(
              operations: installed,
              frame: result.frame,
              locals: result.frame!.visibleTypes,
            );
          }
          final sample = key == 'helper' ? invocation * 2 + 1 : invocation + 1;
          expect(reads, sample + (key == 'helper' ? 1 : 0));
          final program = BuilderProgram.decode(
            slots.last.arguments['program']! as String,
            operations: installed,
            context: context,
          );
          final rows = program.invokeAll(
            captures: _Reader(),
            parameters: {},
            operations: installed,
            context: context,
          );
          expect(rows, hasLength(2));
          for (var index = 0; index < rows.length; index++) {
            final row = index == 0 ? 'one' : 'two';
            expect(
              rows[index].values.values,
              contains(
                key == 'helper'
                    ? '$row:${sample / 255}|${sample + 1}'
                    : '$row:${sample / 255}',
              ),
            );
          }
          expect(reads, sample + (key == 'helper' ? 1 : 0));
        }
      },
    );
  }
  test(
    'merged native locals keep nominal nullability and base-family guards',
    () async {
      Future<ValueProgram> lower(
        String parameters,
        String body,
        List<ValueType> types,
      ) async {
        final callback =
            await parseExpressionFromSourceForTest(
                  "import 'package:flutter/material.dart'; Object x($parameters) => () { $body };",
                  rootPackage: 'apps_examples',
                )
                as FunctionExpression;
        final declaration = (callback.root as CompilationUnit).declarations
            .whereType<FunctionDeclaration>()
            .single;
        final nativeParameters =
            declaration.declaredFragment!.element.formalParameters;
        final values = BuilderExpressionLowering(
          capture: (_) => throw StateError('Unexpected capture'),
        );
        for (var index = 0; index < nativeParameters.length; index++) {
          values.parameter(nativeParameters[index], 'p$index', types[index]);
        }
        final root = closedValueCallback(values).body(callback.body);
        final program = values.program(root)..validate();
        return program;
      }

      final program = await lower(
        'Color? first, Color second',
        'Color? value = first; value = second; return value;',
        const [
          ValueType.native('flutter.Color', nullable: true),
          ValueType.native('flutter.Color'),
        ],
      );
      expect(program.locals.values.single.kind, 'native');
      expect(program.locals.values.single.nativeType, 'flutter.Color');
      expect(program.locals.values.single.nullable, isTrue);
      await expectLater(
        lower(
          'ValueKey<int> first',
          'ValueKey<num> value = first; return value;',
          const [ValueType.native('flutter.Key')],
        ),
        throwsA(isA<BuilderLoweringException>()),
      );
    },
  );

  test(
    'immutable slot provenance preserves native base and material token without proving mutable reads',
    () async {
      Future<(BuilderExpressionLowering, int)> lower(
        String body, {
        String declarations = '',
      }) async {
        final callback =
            await parseExpressionFromSourceForTest(
                  "import 'package:flutter/material.dart'; $declarations Object x() => () { $body };",
                  rootPackage: 'apps_examples',
                )
                as FunctionExpression;
        final values = BuilderExpressionLowering(
          capture: (_) => throw StateError('Unexpected capture'),
          extension: (expression, values) {
            if (expression is MethodInvocation) {
              final helper = pureBuilderHelperFor(
                expression,
                expression.methodName.element,
              );
              if (helper != null) return values.lowerHelper(helper, expression);
            }
            return lowerIntlValue(expression, values);
          },
        );
        final root = closedValueCallback(values).body(callback.body);
        return (values, root);
      }

      final (color, colorRoot) = await lower(
        'final color = Color(1); final alias = color; return alias;',
      );
      expect(color.provesNativeBase(colorRoot, 'Color'), isTrue);
      expect(color.materialColorToken(colorRoot), '');
      final (material, materialRoot) = await lower(
        'final color = Colors.blue; final alias = color; return alias;',
      );
      expect(material.materialColorToken(materialRoot), 'blue');
      final (mutable, mutableRoot) = await lower(
        'var color = Color(1); color = Color(2); return color;',
      );
      expect(mutable.provesNativeBase(mutableRoot, 'Color'), isFalse);
      expect(mutable.materialColorToken(mutableRoot), isNull);
      final (parameter, parameterRoot) = await lower(
        'return keep(Color(1));',
        declarations: 'Color keep(Color color) => color;',
      );
      expect(parameter.provesNativeBase(parameterRoot, 'Color'), isTrue);
      final (written, writtenRoot) = await lower(
        'return replace(Color(1));',
        declarations:
            'Color replace(Color color) { color = Color(2); return color; }',
      );
      expect(written.provesNativeBase(writtenRoot, 'Color'), isFalse);
      expect(written.materialColorToken(writtenRoot), isNull);
      final (deferred, deferredRoot) = await lower(
        'return replaceLater(Color(1));',
        declarations:
            'Color replaceLater(Color color) { final updates = [0].map((item) { color = Color(2); return item; }); final force = updates.first; return color; }',
      );
      expect(deferred.provesNativeBase(deferredRoot, 'Color'), isFalse);
      expect(deferred.materialColorToken(deferredRoot), isNull);
      final program = deferred.program(deferredRoot);
      const installed = {
        ...kCollectionValueOperations,
        ...kNativeIntlValueOperations,
      };
      final result =
          ValueEvaluator(
                program,
                captures: _Reader(),
                parameters: {},
                operations: installed,
              ).evaluate()!
              as Map;
      expect(result['b'], 2 / 255);
      final (shadowed, shadowedRoot) = await lower(
        'return shadow(Color(1));',
        declarations:
            'Color shadow(Color color) { final updates = [0].map((item) { var color = 0; color++; return color; }); return color; }',
      );
      expect(shadowed.provesNativeBase(shadowedRoot, 'Color'), isTrue);
      await expectLater(
        lower(
          'return replacePattern(Color(1));',
          declarations:
              'Color replacePattern(Color color) { (color,) = (Color(2),); return color; }',
        ),
        throwsA(isA<BuilderLoweringException>()),
      );
    },
  );

  test(
    'immutable captured fresh list keeps native sort ownership and aliases',
    () async {
      final (source, _) = await compileCollectionAuthoring(
        authoredSource: temporalCollectionSources['sort']!,
      );
      final slot = _clockSlots(
        rfw.parseLibraryFile(source).widgets.single.root,
      ).single;
      const installed = {
        ...kCollectionValueOperations,
        ...kNativeIntlValueOperations,
      };
      final program = BuilderProgram.decode(
        slot.arguments['program']! as String,
        operations: installed,
      );
      expect(
        program
            .invoke(captures: _Reader(), parameters: {}, operations: installed)
            .values
            .values
            .single,
        '1,2,3|1',
      );
    },
  );

  test(
    'authored lazy map skips length and false branch and rereads per traversal',
    () async {
      final (source, _) = await compileCollectionAuthoring(
        authoredSource: temporalCollectionSources['lazy']!,
      );
      final slots = _clockSlots(
        rfw.parseLibraryFile(source).widgets.single.root,
      );
      expect(slots, hasLength(1));
      var reads = 0;
      final installed = {
        ...kCollectionValueOperations,
        ...kNativeIntlValueOperations,
        'clock.now': ClockNowOperation(
          read: () => DateTime.fromMicrosecondsSinceEpoch(++reads),
        ),
      };
      final program = BuilderProgram.decode(
        slots.single.arguments['program']! as String,
        operations: installed,
      );
      expect(
        program
            .invoke(captures: _Reader(), parameters: {}, operations: installed)
            .values
            .values
            .single,
        '3|0|13|24,25',
      );
      expect(reads, 4);
      expect(
        program
            .invoke(captures: _Reader(), parameters: {}, operations: installed)
            .values
            .values
            .single,
        '3|0|21|32,33',
      );
      expect(reads, 8);
    },
  );

  test(
    'declared clock lowers before mount hoisting with distinct source reads',
    () async {
      final result = await translateFormatting(
        "Text('\${DateTime.now().microsecondsSinceEpoch}|\${DateTime.now().microsecondsSinceEpoch}')",
      );
      expect(result.issues.where((i) => !i.code.isBuildNotice), isEmpty);
      expect(result.hoisted, isEmpty);
      final program = (await authoredFormattingPrograms([
        "'\${DateTime.now().microsecondsSinceEpoch}|\${DateTime.now().microsecondsSinceEpoch}'",
      ])).single;
      var reads = 0;
      final operations = {
        ...kIntlValueOperations,
        'clock.now': ClockNowOperation(
          read: () => DateTime.fromMicrosecondsSinceEpoch(++reads),
        ),
      };
      expect(
        ValueEvaluator(
          program,
          captures: _Reader(),
          parameters: {},
          operations: operations,
        ).evaluate(),
        '1|2',
      );
      expect(reads, 2);
      expect(
        valueProgramRequiredCapability(program, operations: operations),
        24,
      );
    },
  );

  test(
    'temporal fixture is generated from the original native cases',
    () async {
      expect(
        File(
          '../restage_core/test/fixtures/temporal_authoring_programs.json',
        ).readAsStringSync(),
        await compileTemporalFixture(),
      );
    },
  );

  test(
    'native callback reuses final now once and reevaluates on invocation',
    () async {
      final result = await translateFormatting(
        "LayoutBuilder(builder: (context, constraints) { final now = DateTime.now(); return Text('\${now.microsecondsSinceEpoch}|\${now.microsecondsSinceEpoch}'); })",
      );
      expect(result.issues.where((i) => !i.code.isBuildNotice), isEmpty);
      expect(result.hoisted, isEmpty);
      final root =
          rfw
                  .parseLibraryFile(
                    'import restage.core;widget root=${result.dsl};',
                  )
                  .widgets
                  .single
                  .root
              as rfw.ConstructorCall;
      final continuation = root.arguments['builder']! as rfw.ConstructorCall;
      final program = BuilderProgram.decode(
        continuation.arguments['program']! as String,
        operations: kIntlValueOperations,
      );
      var reads = 0;
      final operations = {
        ...kIntlValueOperations,
        'clock.now': ClockNowOperation(
          read: () => DateTime.fromMicrosecondsSinceEpoch(++reads),
        ),
      };
      final first = program.invoke(
        captures: _Reader(),
        parameters: {},
        operations: operations,
      );
      expect(first.values.values, contains('1|1'));
      final second = program.invoke(
        captures: _Reader(),
        parameters: {},
        operations: operations,
      );
      expect(second.values.values, contains('2|2'));
      expect(reads, 2);
    },
  );

  test('an unselected authored clock branch makes zero reads', () async {
    final program = (await authoredFormattingPrograms([
      "'\${false ? DateTime.now().microsecondsSinceEpoch : 0}'",
    ])).single;
    expect(program.nodes.any((node) => node.op == 'clock.now'), isTrue);
    var reads = 0;
    final operations = {
      ...kIntlValueOperations,
      'clock.now': ClockNowOperation(
        read: () {
          reads++;
          return DateTime.utc(2024);
        },
      ),
    };
    expect(
      ValueEvaluator(
        program,
        captures: _Reader(),
        parameters: {},
        operations: operations,
      ).evaluate(),
      '0',
    );
    expect(reads, 0);
  });
  test('Duration evaluates named units in their authored source order', () async {
    final program = (await authoredFormattingPrograms([
      "'\${Duration(microseconds: DateTime.now().microsecondsSinceEpoch, seconds: DateTime.now().microsecondsSinceEpoch).inMicroseconds}'",
    ])).single;
    var reads = 0;
    final operations = {
      ...kIntlValueOperations,
      'clock.now': ClockNowOperation(
        read: () => DateTime.fromMicrosecondsSinceEpoch(++reads),
      ),
    };
    expect(
      ValueEvaluator(
        program,
        captures: _Reader(),
        parameters: {},
        operations: operations,
      ).evaluate(),
      '2000001',
    );
    expect(reads, 2);
  });

  test(
    'numeric and boolean temporal properties lower before mount hoisting',
    () async {
      final result = await translateFormatting(
        "Column(children: [Opacity(opacity: DateTime.now().second / 60, child: SizedBox()), Text('clock', maxLines: DateTime.now().second), Offstage(offstage: DateTime.now().isUtc)])",
      );
      expect(result.issues.where((i) => !i.code.isBuildNotice), isEmpty);
      expect(result.hoisted, isEmpty);
      expect(RegExp('clock.now').allMatches(result.dsl).length, 3);
      expect(result.dsl, contains('temporal.datetime.get'));
    },
  );

  test('resolved temporal lookalikes cannot select native operations', () async {
    for (final (body, extraSource) in [
      (
        "Text('\${DateTime.now().microsecondsSinceEpoch}')",
        'class DateTime { DateTime.now(); int get microsecondsSinceEpoch => 1; }',
      ),
      (
        "Text('\${Duration(microseconds: 1).inSeconds}')",
        'class Duration { Duration({int microseconds = 0}); int get inSeconds => 1; }',
      ),
    ]) {
      final result = await translateFormatting(
        body,
        extraSource: extraSource,
        hoist: false,
      );
      expect(result.dsl, isNot(contains('clock.now')));
      expect(result.dsl, isNot(contains('temporal.')));
      expect(result.issues.where((i) => !i.code.isBuildNotice), isNotEmpty);
    }
  });
}
