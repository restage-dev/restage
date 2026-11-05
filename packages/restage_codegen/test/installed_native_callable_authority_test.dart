import 'package:analyzer/dart/ast/ast.dart';
import 'package:restage_codegen/src/builder_expression_lowering.dart';
import 'package:restage_codegen/src/installed_native_call.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import 'helpers.dart';
import 'support/intl_format_authoring.dart';

InstalledNativeCallPlan _plan(
  Expression expression, {
  bool Function(Expression)? declared,
}) => planInstalledNativeCall(
  expression,
  resultType: const ValueType.native('callback'),
  isDeclaredCallable: declared,
  captureFor: (_) => null,
  inputFor: (identifier) => identifier.name == 'key'
      ? const InstalledNativeInput(0, ValueType.string)
      : null,
);

void main() {
  test(
    'opaque callable origins refuse before installing translation adapters',
    () async {
      for (final (declaration, call) in [
        (
          'final lookup = i.Intl.message;',
          "lookup('fallback', name: lookupKey)",
        ),
        (
          'final dispatch = Function.apply;',
          "dispatch(i.Intl.message, ['fallback'], {#name: lookupKey})",
        ),
        (
          'class Alias { static final lookup = i.Intl.message; }',
          "Alias.lookup('fallback', name: lookupKey)",
        ),
        (
          'class Alias { static final dispatch = Function.apply; }',
          "Alias.dispatch(i.Intl.message, ['fallback'], {#name: lookupKey})",
        ),
        (
          'dynamic get lookup => i.Intl.message;',
          "lookup('fallback', name: lookupKey)",
        ),
      ]) {
        final result = await translateFormatting(
          'LayoutBuilder(builder: (context, constraints) { '
          "const String? lookupKey = true ? null : 'secret'; "
          "final label = i.Intl.message('fallback', name: 'outer', desc: $call); "
          'return Text(label); })',
          extraSource: declaration,
        );
        // The builder renders from the app, and the refusal is its reason.
        expect(result.issues, isEmpty, reason: call);
        expect(
          result.islands.map((island) => island.widget),
          ['LayoutBuilder'],
          reason: call,
        );
        expect(
          result.islands.single.reason?.message,
          contains('Native callable requires'),
          reason: call,
        );
        expect(
          result.hoisted.where((value) => value.nativeCall != null),
          isEmpty,
        );
      }
    },
  );

  test(
    'typed getters indexes factories and external finals are not authority',
    () async {
      for (final body in [
        'lookup()',
        'Holder.lookup()',
        'Holder().member()',
        'Holder().member',
        'coarse()',
        'getter()',
        'factory()()',
        'values[0]()',
        '(lookup as int Function())()',
        'lookup.call()',
        'optional?.call()',
        '() => lookup',
        'consume(lookup)',
        '() { final alias = getter; return alias(); }',
      ]) {
        final expression = await parseExpressionFromSourceForTest('''
int fixed() => 1;
final lookup = fixed;
int Function()? optional = fixed;
class Holder { static final lookup = fixed; final member = fixed; }
Function coarse = fixed;
int Function() get getter => fixed;
int Function() factory() => fixed;
final values = [fixed];
Object consume(Object value) => value;
dynamic x() => $body;
''');
        expect(
          () => _plan(expression),
          throwsA(isA<BuilderLoweringException>()),
          reason: body,
        );
      }
    },
  );

  test(
    'restricted lookup values cannot escape into helpers or containers',
    () async {
      for (final body in [
        'consume(i.Intl.message)',
        'consume(lookup)',
        'consume(lookups)',
        'consume(const [i.Intl.message])',
        'consume(const Box(i.Intl.message))',
        '() => i.Intl.message',
        '() { final alias = i.Intl.message; return alias; }',
      ]) {
        final expression = await parseExpressionFromSourceForTest('''
import 'package:intl/intl.dart' as i;
const lookup = i.Intl.message;
const lookups = [i.Intl.message];
class Box { const Box(this.value); final Object value; }
Object consume(Object value) => value;
dynamic x() => $body;
''', rootPackage: 'apps_examples');
        expect(
          () => _plan(expression),
          throwsA(
            isA<BuilderLoweringException>().having(
              (e) => e.reason,
              'reason',
              contains('fixed validated invocation'),
            ),
          ),
          reason: body,
        );
      }
    },
  );

  test(
    'every adapter root validates direct and constant Intl invocation metadata',
    () async {
      for (final callee in [
        'i.Intl.message',
        'lookup',
        '(lookup)',
        'lookup.call',
      ]) {
        for (final name in ['key', "'fixed'"]) {
          final expression = await parseExpressionFromSourceForTest('''
import 'package:intl/intl.dart' as i;
const lookup = i.Intl.message;
String Function() x(String key) => () => $callee('fallback', name: $name);
''', rootPackage: 'apps_examples');
          if (name == 'key') {
            expect(
              () => _plan(expression),
              throwsA(
                isA<BuilderLoweringException>().having(
                  (e) => e.reason,
                  'reason',
                  contains('fixed constant name'),
                ),
              ),
              reason: callee,
            );
          } else {
            expect(
              _plan(expression).source,
              contains('name: "fixed"'),
              reason: callee,
            );
          }
        }
      }
      final local = await parseExpressionFromSourceForTest('''
import 'package:intl/intl.dart' as i;
String Function() x() => () {
  const lookup = i.Intl.message;
  return lookup('fallback', name: 'fixed');
};
''', rootPackage: 'apps_examples');
      expect(() => _plan(local), returnsNormally);
    },
  );

  test(
    'fixed declarations inline closures and inspectable aliases retain authority',
    () async {
      for (final body in [
        'fixed()',
        'alias()',
        'Holder.fixed()',
        'Function.apply(3)',
        '() { final call = fixed; return call(); }',
        '() { final call = () => fixed(); final alias = call; return alias(); }',
        '() { int call() => fixed(); return call(); }',
      ]) {
        final expression = await parseExpressionFromSourceForTest('''
int fixed() => 1;
const alias = fixed;
class Holder { static int fixed() => 2; }
class Function { static int apply(int value) => value; }
dynamic x() => $body;
''');
        expect(() => _plan(expression), returnsNormally, reason: body);
      }
    },
  );

  test(
    'function annotations require actual existing native frame bindings',
    () async {
      final expression =
          await parseExpressionFromSourceForTest('''
int Function() x(int Function() callback) => () {
  final alias = callback;
  return alias();
};
''')
              as FunctionExpression;
      final declaration = expression
          .thisOrAncestorOfType<FunctionDeclaration>()!;
      final parameter = declaration
          .functionExpression
          .parameters!
          .parameters
          .single
          .declaredFragment!
          .element;
      final unbound = BuilderExpressionLowering(capture: (_) => 'unused');
      expect(
        () => unbound.lowerInstalledNativeCall(
          expression,
          resultType: const ValueType.native('callback'),
          install: (_) {},
        ),
        throwsA(isA<BuilderLoweringException>()),
      );
      final bound = BuilderExpressionLowering(capture: (_) => 'unused');
      bound.parameter(
        parameter,
        'callback',
        const ValueType.native('callback'),
      );
      final plans = <InstalledNativeCallPlan>[];
      bound.lowerInstalledNativeCall(
        expression,
        resultType: const ValueType.native('callback'),
        install: plans.add,
      );
      expect(plans.single.inputs, hasLength(1));
      expect(plans.single.source, contains('final alias = _restageInput0'));
    },
  );
}
