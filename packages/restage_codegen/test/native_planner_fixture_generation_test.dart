import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:dart_style/dart_style.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:restage_codegen/src/installed_native_call.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test('native planner fixture is generated from the resolved authored source',
      () async {
    final source =
        File('../restage_core/test/fixtures/native_planner_source.dart')
            .readAsStringSync();
    final output = StringBuffer("part of 'native_planner_source.dart';\n");
    for (final (function, type) in [
      ('Closure', 'callback'),
      ('Key', 'flutter.Key'),
      ('Color', 'flutter.Color'),
      ('Reassign', 'callback.reassign'),
      ('Nullable', 'flutter.Key'),
      ('Static', 'callback.static'),
      ('Interpolation', 'callback.interpolation'),
      ('SelectColor', 'flutter.Color'),
      ('CoalesceColor', 'flutter.Color'),
      ('SelectKey', 'flutter.Key'),
      ('SelectCallback', 'callback.selected'),
    ]) {
      final expression = await parseExpressionFromSourceForTest(source,
          rootPackage: 'apps_examples',
          functionName: 'authored$function',
          enclosingClassName:
              function == 'Static' ? 'NativePlannerStatics' : null);
      final inputs = <ValueNode>[];
      final parameters = <String, ValueType>{};
      final plan = planInstalledNativeCall(expression,
          resultType: ValueType.native(type, nullable: function == 'Nullable'),
          isDeclaredCallable: (reference) =>
              reference is SimpleIdentifier &&
              const {'seen', 'first', 'second'}.contains(reference.name),
          captureFor: (element) => switch (element.name) {
                'count' =>
                  const InstalledNativeCapture('counter', ValueType.integer),
                'value' => const InstalledNativeCapture(
                    'object', ValueType.native('dart.Object')),
                _ => null,
              },
          inputFor: (identifier) {
            final name = identifier.name;
            final type = switch (name) {
              'items' => const ValueType.native('dart.List<Object>'),
              'swatch' => const ValueType.native('dart.Map<int,Color>'),
              'seen' => const ValueType.native('callback.seen'),
              'index' => ValueType.integer,
              'flag' => ValueType.boolean,
              'first' ||
              'second' =>
                const ValueType.native('callback.selected'),
              'color' => const ValueType.native('flutter.Color'),
              'optional' =>
                const ValueType.native('flutter.Color', nullable: true),
              'key' => const ValueType.native('flutter.Key'),
              'replacement' => const ValueType.native('dart.Object'),
              'model' => const ValueType.native('dart.Object', nullable: true),
              _ => throw StateError(name),
            };
            parameters[name] = type;
            final index = inputs.length;
            inputs.add(ValueNode('parameter', type, name: name));
            return InstalledNativeInput(index, type);
          });
      final program = ValueProgram(
          nodes: [...inputs, plan.node],
          root: inputs.length,
          parameters: parameters,
          outerLocals: {
            if (function == 'Closure' || function == 'Interpolation')
              'counter': ValueType.integer,
            if (function == 'Reassign')
              'object': const ValueType.native('dart.Object'),
          });
      output.writeln(
          'const nativePlanner${function}Binding = ${jsonEncode(plan.key)};');
      output.writeln(
          'r.NativeCallAdapter nativePlanner${function}Adapter() => ${plan.adapterSource(core: 'r.', shared: 's.')};');
      output.writeln(
          's.ValueProgram nativePlanner${function}Program(Map<String, s.ValueOperation> operations, {s.ValueOperationContext? context}) => s.ValueProgram.decode(${jsonEncode(program.encode())}, operations: operations, context: context);');
    }
    final constant = await parseExpressionFromSourceForTest(source,
        rootPackage: 'apps_examples', functionName: 'authoredConstant');
    final binding = installedNativeConstant(
        constant as InstanceCreationExpression,
        type: 'flutter.Color');
    output.writeln(
        'f.MaterialColor nativePlannerConstant() => ${binding.mountSource((_) => throw StateError('input'))};');
    final generated = DartFormatter(languageVersion: Version(3, 5, 0))
        .format(output.toString());
    final file =
        File('../restage_core/test/fixtures/native_planner_source.g.dart');
    if (Platform.environment['WRITE_NATIVE_PLANNER_FIXTURE'] == '1')
      file.writeAsStringSync(generated);
    expect(file.readAsStringSync(), generated);
  });
}
