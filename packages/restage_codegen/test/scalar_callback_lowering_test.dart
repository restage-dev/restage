import 'package:restage_codegen/src/builder_expression_lowering.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:restage_codegen/src/scalar_callback_lowering.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart' as rfw;
import 'package:test/test.dart';

import 'helpers.dart';

final class _Reader implements ValueReader {
  final reads = <List<Object>>[];
  @override
  int length(List<Object> path) => 10000;
  @override
  Object? read(List<Object> path, ValueType type) {
    if (type.kind != 'list' && type.kind != 'record') reads.add(path);
    if (type.kind == 'list') return ValueListView(this, path, type.item!);
    if (type.kind == 'record') return ValueRecordView(this, path, type.fields);
    return path.last == 'id' ? 'id${path[path.length - 2]}' : null;
  }
}

void main() {
  Future<ValueProgram> lower(
    String callback,
    ScalarCallbackContract contract, {
    bool key = false,
  }) async {
    final expression =
        await parseExpressionFromSourceForTest('''
import 'package:flutter/widgets.dart';
class Item { const Item(this.id); final String id; }
Widget x(List<Item> items) => GridView.builder(
 gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:2),
 itemBuilder: (_,i) => Text('item'),
 ${key ? 'findChildIndexCallback' : 'findChildIndexCallback'}: $callback);
''', rootPackage: 'apps_examples')
            as InstanceCreationExpression;
    final fn =
        (expression.argumentList.arguments.last as NamedArgument)
                .argumentExpression
            as FunctionExpression;
    final slot = ScalarCallbackLowering(
      contract: contract,
      capture: (_) => 'data.items',
    ).lower(fn);
    final root =
        rfw
                .parseLibraryFile(
                  'import core; widget Root = Probe(callback: $slot);',
                )
                .widgets
                .single
                .root
            as rfw.ConstructorCall;
    final map = (root.arguments['callback']! as rfw.ConstructorCall).arguments;
    return ValueProgram.decode(
      map['program']! as String,
      operations: kGridValueOperations,
    );
  }

  test('helper projection discovery visits a shared body once', () async {
    final widget =
        await parseExpressionFromSourceForTest('''
import 'package:flutter/widgets.dart';
int readKey(Key key)=>(key as ValueKey<int>).value;
int twice(Key key)=>readKey(key)+readKey(key);
Widget x()=>GridView.builder(
 gridDelegate:const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:2),
 itemBuilder:(_,index)=>null,
 findChildIndexCallback:(key)=>twice(key)+twice(key));
''', rootPackage: 'apps_examples')
            as InstanceCreationExpression;
    final callback =
        (widget.argumentList.arguments.last as NamedArgument).argumentExpression
            as FunctionExpression;
    final discoveries = <String, int>{};
    late final ScalarCallbackLowering lowering;
    lowering = ScalarCallbackLowering(
      contract: const ScalarCallbackContract(
        parameters: [ScalarCallbackParameter.valueKey],
      ),
      capture: (_) => throw StateError('Unexpected capture'),
      helperFor: (call) {
        if (!lowering.expressions.parameters.containsKey('arg0')) {
          discoveries.update(
            call.methodName.name,
            (count) => count + 1,
            ifAbsent: () => 1,
          );
        }
        return pureBuilderHelperFor(call, call.methodName.element);
      },
    );
    final slot = lowering.lower(callback);
    expect(discoveries, {'twice': 2, 'readKey': 2});
    final root =
        rfw
                .parseLibraryFile(
                  'import core; widget Root = Probe(callback:$slot);',
                )
                .widgets
                .single
                .root
            as rfw.ConstructorCall;
    final program = ValueProgram.decode(
      (root.arguments['callback']! as rfw.ConstructorCall).arguments['program']!
          as String,
      operations: kGridValueOperations,
    );
    expect(
      ValueEvaluator(
        program,
        captures: _Reader(),
        parameters: {
          'arg0': {'int': 2},
        },
        operations: kGridValueOperations,
      ).evaluate(),
      8,
    );
  });
  test('nested bounded predicates write live outer cells', () async {
    final program = await lower(
      """(key) {
      var seen = 0;
      final result = items.indexWhere((item) {
        seen++;
        return item.id == 'id3';
      });
      return seen * 10 + result;
    }""",
      const ScalarCallbackContract(
        parameters: [ScalarCallbackParameter.valueKey],
      ),
    );
    expect(
      ValueEvaluator(
        program,
        captures: _Reader(),
        parameters: {},
        operations: kGridValueOperations,
      ).evaluate(),
      43,
    );
    expect(
      valueProgramRequiredCapability(program, operations: kGridValueOperations),
      24,
    );
  });
  test('key predicate demands only fields through first match', () async {
    final program = await lower(
      '(key) => items.indexWhere((item) => item.id == (key as ValueKey<String>).value)',
      const ScalarCallbackContract(
        parameters: [ScalarCallbackParameter.valueKey],
      ),
      key: true,
    );
    final reader = _Reader();
    final result = ValueEvaluator(
      program,
      captures: reader,
      parameters: {
        'arg0': {'String': 'id3'},
      },
      operations: kGridValueOperations,
    ).evaluate();
    expect(result, 3);
    expect(reader.reads, hasLength(4));
    expect(reader.reads.every((p) => p.last == 'id'), isTrue);
  });
  test('predicate locals and shadowing stay inside the nested graph', () async {
    final program = await lower(
      '''(key) {
      final id = 'outer';
      final wanted = (key as ValueKey<String>).value;
      return items.indexWhere((item) {
        final id = item.id;
        final matches = id == wanted;
        return matches;
      });
    }''',
      const ScalarCallbackContract(
        parameters: [ScalarCallbackParameter.valueKey],
      ),
    );
    final reader = _Reader();
    expect(
      ValueEvaluator(
        program,
        captures: reader,
        parameters: {
          'arg0': {'String': 'id3'},
        },
        operations: kGridValueOperations,
      ).evaluate(),
      3,
    );
    expect(reader.reads, hasLength(4));
    final predicate = ValueProgram.decode(
      program.nodes.singleWhere((node) => node.op == 'grid.indexWhere').value!
          as String,
      operations: kGridValueOperations,
    );
    expect(predicate.parameters.keys, unorderedEquals(['item', 'outer0']));
  });
  test('scalar callback tear-offs preserve eager pure helper locals', () async {
    final expression =
        await parseExpressionFromSourceForTest("""
import 'package:flutter/widgets.dart';
int half(int value)=>value~/2;
int? semantic(Widget child,int index) {
 final scaled=half(index);
 return index.isEven ? scaled : null;
}
Widget x()=>GridView.custom(
 gridDelegate:const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:2),
 childrenDelegate:SliverChildListDelegate([Text('a')],semanticIndexCallback:semantic));
""", rootPackage: 'apps_examples')
            as InstanceCreationExpression;
    final delegate =
        (expression.argumentList.arguments.last as NamedArgument)
                .argumentExpression
            as InstanceCreationExpression;
    final callback =
        (delegate.argumentList.arguments.last as NamedArgument)
                .argumentExpression
            as SimpleIdentifier;
    final helper = pureBuilderHelperFor(callback, callback.element)!;
    final lowering = ScalarCallbackLowering(
      capture: (_) => throw StateError('Unexpected capture'),
      contract: const ScalarCallbackContract(
        parameters: [
          ScalarCallbackParameter.widget,
          ScalarCallbackParameter.itemIndex,
        ],
      ),
      helperFor: (call) => pureBuilderHelperFor(call, call.methodName.element),
    );
    final slot = lowering.lowerDefinition(helper);
    final root =
        rfw
                .parseLibraryFile(
                  'import core; widget Root = Probe(callback:$slot);',
                )
                .widgets
                .single
                .root
            as rfw.ConstructorCall;
    final encoded =
        (root.arguments['callback']! as rfw.ConstructorCall)
                .arguments['program']!
            as String;
    final program = ValueProgram.decode(
      encoded,
      operations: kGridValueOperations,
    );
    expect(
      ValueEvaluator(
        program,
        captures: _Reader(),
        parameters: {'arg1': 4},
        operations: kGridValueOperations,
      ).evaluate(),
      2,
    );
    expect(
      ValueEvaluator(
        program,
        captures: _Reader(),
        parameters: {'arg1': 3},
        operations: kGridValueOperations,
      ).evaluate(),
      isNull,
    );
  });
  test(
    'contextual numeric literals preserve native double multiplication',
    () async {
      final widget =
          await parseExpressionFromSourceForTest("""
import 'package:flutter/widgets.dart';
Widget x(List<int> values)=>GridView.count(crossAxisCount:2,mainAxisExtent:values.length*10);
""", rootPackage: 'apps_examples')
              as InstanceCreationExpression;
      final expression =
          (widget.argumentList.arguments.last as NamedArgument)
                  .argumentExpression
              as BinaryExpression;
      final lowering = BuilderExpressionLowering(capture: (_) => 'data.values');
      final node = lowering.lower(expression);
      final program = lowering.program(node);
      expect(
        () => program.validate(),
        returnsNormally,
        reason:
            'result=${expression.staticType};left=${expression.leftOperand.staticType};right=${expression.rightOperand.staticType}',
      );
      expect(
        ValueEvaluator(
          program,
          captures: _Reader(),
          parameters: const {},
        ).evaluate(),
        100000.0,
      );
    },
  );
}
