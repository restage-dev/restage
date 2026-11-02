import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:dart_style/dart_style.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:restage_codegen/src/builder_expression_lowering.dart';
import 'package:restage_codegen/src/installed_native_call.dart';
import 'package:restage_codegen/src/widget_builder_lowering.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import 'helpers.dart';

// A small native caller exercises the production callback lowerer and renderer.
// ContextProbe only exposes a compiled closure; it performs no context lookup.
void main() {
  test(
    'actual callback contexts lower from source to compiled native closures',
    () async {
      final source = File(
        '../restage_core/test/fixtures/callback_context_source.dart',
      ).readAsStringSync();
      final output = StringBuffer("part of 'callback_context_source.dart';\n");
      for (final name in ['Direct', 'Alias', 'Helper', 'Nested']) {
        final expression = await parseExpressionFromSourceForTest(
          source,
          rootPackage: 'apps_examples',
          functionName: 'authored$name',
          libraryPath: 'lib/callback_context_source.dart',
        );
        final emissionLibrary =
            (expression.root as CompilationUnit).declaredFragment!.element;
        final plans = <String, InstalledNativeCallPlan>{};
        var scopes = 0;
        String widget(Expression value, WidgetBuilderLowering? parent) {
          if (value is! InstanceCreationExpression) throw StateError('$value');
          final type = value.constructorName.type.name.lexeme;
          final args = value.argumentList.arguments;
          if (type == 'LayoutBuilder' || type == 'Builder') {
            final callback =
                args.single.argumentExpression as FunctionExpression;
            late WidgetBuilderLowering builder;
            final expressions = BuilderExpressionLowering(
              parent: parent?.expressions,
              capture: (value) => parent!.captureValue(value),
              extension: (value, current) => value is FunctionExpression
                  ? current.lowerInstalledNativeCall(
                      value,
                      resultType: const ValueType.native('context.callback'),
                      emissionLibrary: emissionLibrary,
                      install: (plan) => plans[plan.key] = plan,
                    )
                  : null,
            );
            builder = WidgetBuilderLowering(
              expressions: expressions,
              contract: WidgetBuilderContract(
                parameters: [
                  WidgetBuilderParameter.buildContext,
                  if (type == 'LayoutBuilder')
                    WidgetBuilderParameter.boxConstraints,
                ],
              ),
              scope: 'b${scopes++}',
              translateBody: (body) => widget(body, builder),
              helperFor: (call) =>
                  pureBuilderHelperFor(call, call.methodName.element),
            );
            return '$type(builder: ${builder.lower(callback)})';
          }
          if (type != 'ContextProbe' || parent == null) throw StateError(type);
          final callback = parent.nativeValue(
            args[1].argumentExpression,
            (value, current) => current.lower(value),
          );
          final children = args.where(
            (arg) => arg is NamedArgument && arg.name.lexeme == 'child',
          );
          return 'ContextProbe(name: ${args[0].toSource()}, callback: $callback'
              '${children.isEmpty ? '' : ', child: ${widget(children.single.argumentExpression, parent)}'})';
        }

        final dsl =
            'import restage.core; widget Root = ${widget(expression, null)};';
        output.writeln('const context${name}Dsl = ${jsonEncode(dsl)};');
        // Match production mounting: fixed expressions live in top-level factories,
        // outside the lexical scope of generated mount parameters and locals.
        for (final plan in plans.values) {
          expect(plan.emissionLibraryIdentity, emissionLibrary.identifier);
          output.writeln(
            'r.NativeCallAdapter _context$name${plan.key}Native() => '
            '${plan.adapterSource(core: 'r.', shared: 's.')};',
          );
        }
        output.writeln(
          'Map<String, r.NativeBinding<Object?>> context${name}Bindings() => {',
        );
        for (final plan in plans.values) {
          output.writeln(
            '${jsonEncode(plan.key)}: r.NativeBinding<Object?>(contract: ${nativeContractSource(plan.contract, 's.')}, value: _context$name${plan.key}Native()),',
          );
        }
        output.writeln('};');
        expect(plans.values, isNotEmpty);
        expect(
          plans.values
              .expand((p) => p.contract.call!.inputs)
              .where((t) => t == builderContextNativeValueType),
          isNotEmpty,
        );
      }
      final generated = DartFormatter(
        languageVersion: Version(3, 5, 0),
      ).format(output.toString());
      final file = File(
        '../restage_core/test/fixtures/callback_context_source.g.dart',
      );
      if (Platform.environment['WRITE_CALLBACK_CONTEXT_FIXTURE'] == '1')
        file.writeAsStringSync(generated);
      expect(file.readAsStringSync(), generated);
    },
  );
}
