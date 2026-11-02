import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:dart_style/dart_style.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:restage_codegen/src/installed_native_call.dart';
import 'package:restage_codegen/src/builder_expression_lowering.dart';
import 'package:restage_codegen/src/intl_format_recognition.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test(
    'callable cell fixture is produced by the shared native planner',
    () async {
      final expression = await parseExpressionFromSourceForTest(
        File(
          '../restage_core/test/fixtures/callable_authority_source.dart',
        ).readAsStringSync(),
        rootPackage: 'apps_examples',
        functionName: 'authoredCallable',
      );
      const type = ValueType.native('callback.context');
      final plan = planInstalledNativeCall(
        expression,
        resultType: type,
        isDeclaredCallable: (reference) =>
            reference is SimpleIdentifier &&
            const {'callback', 'replacement'}.contains(reference.name),
        captureFor: (element) => element.name == 'callback'
            ? const InstalledNativeCapture('callback', type)
            : null,
        inputFor: (identifier) => identifier.name == 'replacement'
            ? const InstalledNativeInput(0, type)
            : null,
      );
      expect(plan.captures.values.single.slot, 'callback');
      expect(plan.inputs, hasLength(1));
      final nullable =
          await parseExpressionFromSourceForTest(
                File(
                  '../restage_core/test/fixtures/callable_authority_source.dart',
                ).readAsStringSync(),
                rootPackage: 'apps_examples',
                functionName: 'authoredNullableCallable',
              )
              as FunctionExpression;
      final declaration = nullable.thisOrAncestorOfType<FunctionDeclaration>()!;
      final lastCall =
          ((nullable.body as BlockFunctionBody).block.statements.last
                      as ExpressionStatement)
                  .expression
              as FunctionExpressionInvocation;
      final read = (lastCall.function as PostfixExpression).operand;
      final lowering = BuilderExpressionLowering(capture: (_) => 'unused');
      for (final parameter
          in declaration.functionExpression.parameters!.parameters) {
        final element = parameter.declaredFragment!.element;
        final shape = ValueType.native(
          element.name == 'acquire' ? 'callback.acquire' : 'callback.context',
          nullable: element.name == 'callback',
        );
        final node = lowering.parameter(element, element.name!, shape);
        if (element.name == 'callback') {
          lowering.bindValue(element, node, read, mutable: true);
        }
      }
      final plans = <InstalledNativeCallPlan>[];
      lowering.lowerInstalledNativeCall(
        nullable,
        resultType: type,
        install: plans.add,
      );
      final nullablePlan = plans.single;
      expect(nullablePlan.captures.values.single.type.nullable, isTrue);
      expect(nullablePlan.source, contains('.value ??='));
      expect(nullablePlan.inputs.map((input) => input.type.nativeType), [
        'callback.acquire',
        'callback.context',
      ]);
      final lookup = await parseExpressionFromSourceForTest(
        File(
          '../restage_core/test/fixtures/callable_authority_source.dart',
        ).readAsStringSync(),
        rootPackage: 'apps_examples',
        functionName: 'authoredAliasedLookup',
      );
      expect(isInstalledIntlTranslation(lookup), isTrue);
      final lookupPlan = planInstalledNativeCall(
        lookup,
        resultType: ValueType.string,
        captureFor: (_) => null,
        inputFor: (_) => null,
      );
      final generated = DartFormatter(languageVersion: Version(3, 5, 0)).format(
        '''
part of 'callable_authority_source.dart';
r.NativeCallAdapter callableAuthorityAdapter() => ${plan.adapterSource(core: 'r.', shared: 's.')};
const nullableCallableSlot = '${nullablePlan.captures.values.single.slot}';
r.NativeCallAdapter nullableCallableAdapter() => ${nullablePlan.adapterSource(core: 'r.', shared: 's.')};
r.NativeCallAdapter aliasedLookupAdapter() => ${lookupPlan.adapterSource(core: 'r.', shared: 's.')};
''',
      );
      final file = File(
        '../restage_core/test/fixtures/callable_authority_source.g.dart',
      );
      if (Platform.environment['WRITE_CALLABLE_AUTHORITY_FIXTURE'] == '1') {
        file.writeAsStringSync(generated);
      }
      expect(file.readAsStringSync(), generated);
    },
  );
}
