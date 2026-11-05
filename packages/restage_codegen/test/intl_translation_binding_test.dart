import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:dart_style/dart_style.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:restage_codegen/src/capability_derivation.dart';
import 'package:restage_codegen/src/installed_native_call.dart';
import 'package:restage_codegen/src/intl_format_recognition.dart';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart' as rfw;
import 'package:test/test.dart';

import 'helpers.dart';
import 'support/intl_format_authoring.dart';

void main() {
  test(
    'translated source installs fixed call adapters through the translator',
    () async {
      for (final source in [
        "i.Intl.message('hello', name: 'hello', args: [])",
        "i.Intl.message('date', name: 'date', args: [count, start])",
        "i.Intl.plural(count, other: 'items', name: 'items', args: [count])",
        "i.Intl.gender('male', other: 'they', name: 'person', args: ['male'])",
        "i.Intl.select(Status.active, {'active': 'yes', 'other': 'no'}, name: 'status', args: [Status.active, Status.active])",
      ]) {
        final result = await translateFormatting(
          'LayoutBuilder(builder: (context, constraints) { '
          'final label = $source; return Text(label); })',
          extraSource: 'enum Status { active }',
        );
        expect(
          result.issues.where((issue) => !issue.code.isBuildNotice),
          isEmpty,
          reason: result.issues.map((issue) => issue.message).join('; '),
        );
        expect(
          result.hoisted.where((value) => value.nativeCall != null),
          hasLength(1),
        );
        expect(result.dsl, contains('native.call'));
        final plan = result.hoisted
            .singleWhere((value) => value.nativeCall != null)
            .nativeCall!;
        expect(plan.contract.call!.result, ValueType.string);
        expect(plan.source, contains('name:'));
        expect(plan.source, contains('args:'));
        final catalog = decodeCatalog(
          File(
            '../restage_core/lib/src/widget_catalog/catalog.json',
          ).readAsStringSync(),
        );
        expect(
          deriveCapabilityManifest(
            rfw.parseLibraryFile(
              'import restage.core; widget Root = ${result.dsl};',
            ),
            catalog,
            hoisted: result.hoisted,
          ).manifest!.builtInFloor,
          24,
        );
      }
    },
  );

  test('lookup names and argument arity cannot be chosen by payloads', () async {
    for (final source in [
      "i.Intl.message('hello', name: locale, args: [])",
      "i.Intl.message(locale, args: [])",
      "i.Intl.message(locale, name: '', args: [])",
      "i.Intl.message('hello', name: null, meaning: locale)",
      "i.Intl.message('hello', name: 'hello', desc: i.Intl.message('nested', name: locale))",
      "i.Intl.plural(count, other: 'items', name: 'items', args: [for (final n in [count]) n])",
    ]) {
      final result = await translateFormatting(
        'LayoutBuilder(builder: (context, constraints) { '
        'final label = $source; return Text(label); })',
      );
      _expectCarried(result);
      expect(
        result.hoisted.where((value) => value.nativeCall != null),
        isEmpty,
      );
    }
  });

  test(
    'a changed constant lookup name changes the installed binding identity',
    () async {
      final identities = <String>[];
      for (final name in ['first', 'second']) {
        final result = await translateFormatting(
          'LayoutBuilder(builder: (context, constraints) { '
          "const messageName = '$name'; const suffix = 'Lookup'; "
          r"final label = i.Intl.message('fallback', name: '${messageName}$suffix', args: []); "
          'return Text(label); })',
        );
        expect(
          result.issues.where((issue) => !issue.code.isBuildNotice),
          isEmpty,
        );
        identities.add(
          result.hoisted.single.nativeCall!.contract.call!.implementation,
        );
        expect(result.hoisted.single.nativeCall!.inputs, isEmpty);
        expect(result.hoisted.single.nativeCall!.captures, isEmpty);
        expect(
          result.hoisted.single.nativeCall!.source,
          contains('${name}Lookup'),
        );
      }
      expect(identities.first, isNot(identities.last));
    },
  );

  test(
    'Function.apply cannot produce an installed translation adapter',
    () async {
      for (final call in [
        "i.Intl.message, ['fallback'], {#name: lookupKey}",
        "i.Intl.plural, [1], {#other: 'fallback', #meaning: lookupKey}",
        "i.Intl.gender, ['male'], {#other: 'fallback', #meaning: lookupKey}",
        "i.Intl.select, ['active', {'other': 'fallback'}], {#meaning: lookupKey}",
      ]) {
        for (final callee in [
          'Function.apply',
          'dispatch',
          '(Function.apply)',
        ]) {
          final result = await translateFormatting(
            'LayoutBuilder(builder: (context, constraints) { '
            "const String? lookupKey = true ? null : 'secret'; "
            "final label = i.Intl.message('fallback', name: 'outer', "
            'desc: $callee($call)); return Text(label); })',
            extraSource: 'const dispatch = Function.apply;',
          );
          _expectCarried(result);
          expect(
            result.hoisted.where((value) => value.nativeCall != null),
            isEmpty,
          );
        }
      }
    },
  );

  test(
    'meaning-only lookup authority is fixed for every family and nesting',
    () async {
      for (final call in [
        "i.Intl.plural(1, other: 'fallback', meaning: lookupKey",
        "i.Intl.gender('male', other: 'fallback', meaning: lookupKey",
        "i.Intl.select('active', {'other': 'fallback'}, meaning: lookupKey",
      ]) {
        for (final options in [
          '',
          ', name: null',
          ', args: null',
          ', name: null, args: null',
        ]) {
          for (final nested in [true, false]) {
            final inner = '$call$options)';
            final expression = nested
                ? "i.Intl.message('fallback', name: 'outer', desc: $inner)"
                : inner;
            final result = await translateFormatting(
              'LayoutBuilder(builder: (context, constraints) { '
              "var lookupKey = 'secret'; final label = $expression; "
              'return Text(label); })',
            );
            _expectCarried(result, reason: expression);
            expect(
              result.hoisted.where((value) => value.nativeCall != null),
              isEmpty,
            );
          }
        }
        final rootCall = call.replaceAll('lookupKey', 'locale');
        _expectCarried(await translateFormatting('Text($rootCall))'));
      }
    },
  );

  test(
    'fixed meaning-only calls install adapters and null meanings stay wire formatting',
    () async {
      for (final call in [
        "i.Intl.plural(1, other: 'fallback', meaning: lookupKey)",
        "i.Intl.gender('male', other: 'fallback', meaning: lookupKey)",
        "i.Intl.select('active', {'other': 'fallback'}, meaning: lookupKey)",
      ]) {
        final identities = <String>[];
        for (final key in ["'secret'", "'other'", 'null']) {
          final result = await translateFormatting(
            'LayoutBuilder(builder: (context, constraints) { '
            'const String? lookupKey = $key; final label = $call; '
            'return Text(label); })',
          );
          expect(
            result.issues.where((issue) => !issue.code.isBuildNotice),
            isEmpty,
          );
          final adapters = result.hoisted.where(
            (value) => value.nativeCall != null,
          );
          if (key == 'null') {
            expect(adapters, isEmpty);
            expect(result.dsl, isNot(contains('native.call')));
          } else {
            final plan = adapters.single.nativeCall!;
            expect(plan.captures, isEmpty);
            expect(plan.inputs, isEmpty);
            expect(
              plan.source,
              contains('meaning: ${key.replaceAll("'", '"')}'),
            );
            identities.add(plan.contract.call!.implementation);
          }
        }
        expect(identities.first, isNot(identities.last));
      }
    },
  );

  test(
    'constant null lookup names and args are fixed installed source',
    () async {
      final result = await translateFormatting(
        'LayoutBuilder(builder: (context, constraints) { '
        'const String? lookupName = null; const List<Object>? noArgs = null; '
        "final label = i.Intl.message('fallback', name: lookupName, args: noArgs); "
        'return Text(label); })',
      );
      expect(
        result.issues.where((issue) => !issue.code.isBuildNotice),
        isEmpty,
      );
      final plan = result.hoisted.single.nativeCall!;
      expect(plan.inputs, isEmpty);
      expect(plan.captures, isEmpty);
      expect(plan.source, contains('name: null'));
      expect(plan.source, contains('args: null'));
    },
  );

  test(
    'nested constant-null meaning cannot become a widened lookup input',
    () async {
      for (final call in [
        "i.Intl.plural(1, other: 'fallback', meaning: lookupKey)",
        "i.Intl.gender('male', other: 'fallback', meaning: lookupKey)",
        "i.Intl.select('active', {'other': 'fallback'}, meaning: lookupKey)",
      ]) {
        final result = await translateFormatting(
          'LayoutBuilder(builder: (context, constraints) { '
          "const String? lookupKey = true ? null : 'secret'; "
          "final label = i.Intl.message('fallback', name: 'noArgs', desc: $call); "
          'return Text(label); })',
        );
        expect(
          result.issues.where((issue) => !issue.code.isBuildNotice),
          isEmpty,
        );
        final plan = result.hoisted.single.nativeCall!;
        expect(plan.inputs, isEmpty);
        expect(plan.captures, isEmpty);
        expect(plan.source, contains('meaning: null'));
      }
    },
  );

  test(
    'constant Intl tear-offs retain the same closed lookup operands',
    () async {
      for (final (family, arguments) in [
        ('plural', "1, other: 'fallback'"),
        ('gender', "'male', other: 'fallback'"),
        ('select', "'active', {'other': 'fallback'}"),
      ]) {
        for (final callee in ['lookupAlias', '(i.Intl.$family)']) {
          final result = await translateFormatting(
            'LayoutBuilder(builder: (context, constraints) { '
            "const String? lookupKey = true ? null : 'secret'; "
            "final label = i.Intl.message('fallback', name: 'noArgs', "
            'desc: $callee($arguments, meaning: lookupKey)); '
            'return Text(label); })',
            extraSource: 'const lookupAlias = i.Intl.$family;',
          );
          expect(
            result.issues.where((issue) => !issue.code.isBuildNotice),
            isEmpty,
          );
          final plan = result.hoisted.single.nativeCall!;
          expect(plan.inputs, isEmpty);
          expect(plan.captures, isEmpty);
          expect(plan.source, contains('meaning: null'));
        }
        final dynamicResult = await translateFormatting(
          'LayoutBuilder(builder: (context, constraints) { '
          "var lookupKey = 'secret'; "
          "final label = i.Intl.message('fallback', name: 'noArgs', "
          'desc: lookupAlias($arguments, meaning: lookupKey)); '
          'return Text(label); })',
          extraSource: 'const lookupAlias = i.Intl.$family;',
        );
        _expectCarried(dynamicResult);
        expect(
          dynamicResult.hoisted.where((value) => value.nativeCall != null),
          isEmpty,
        );
      }
      for (final text in ['text', 'null as dynamic']) {
        final message = await translateFormatting(
          'LayoutBuilder(builder: (context, constraints) { '
          "var text = 'remoteSelected'; "
          "final label = i.Intl.message('fallback', name: 'noArgs', "
          'desc: lookupAlias($text, name: null)); return Text(label); })',
          extraSource: 'const lookupAlias = i.Intl.message;',
        );
        _expectCarried(message);
        expect(
          message.hoisted.where((value) => value.nativeCall != null),
          isEmpty,
        );
      }
    },
  );

  test('effectful translations require a staged callback initializer', () async {
    for (final source in [
      "Text(i.Intl.message('fallback', name: 'noArgs', args: []))",
      "LayoutBuilder(builder: (context, constraints) => Text(i.Intl.message('fallback', name: 'noArgs', args: [])))",
    ]) {
      final result = await translateFormatting(source);
      _expectCarried(result);
      expect(
        result.hoisted.where((value) => value.nativeCall != null),
        isEmpty,
      );
    }
  });

  test(
    'mutable projected locals cannot become native translation args',
    () async {
      for (final initializer in ['Status.active', 'DateTime.utc(2024)']) {
        final result = await translateFormatting(
          'LayoutBuilder(builder: (context, constraints) { '
          'var choice = $initializer; '
          "final label = i.Intl.select(choice, {'active': 'yes', 'other': 'no'}, "
          "name: 'status', args: [choice, choice]); return Text(label); })",
          extraSource: 'enum Status { active }',
        );
        _expectCarried(result);
        expect(
          result.hoisted.where((value) => value.nativeCall != null),
          isEmpty,
        );
      }
    },
  );

  test('staged translation args retain the callback mutable cell', () async {
    final result = await translateFormatting(
      'LayoutBuilder(builder: (context, constraints) { '
      'var localCount = 1; '
      "final label = i.Intl.message('fallback', name: 'items', args: [localCount++]); "
      'return Text(label); })',
    );
    expect(result.issues.where((issue) => !issue.code.isBuildNotice), isEmpty);
    final plan = result.hoisted.single.nativeCall!;
    expect(
      plan.captures.values.single.type.toJson(),
      ValueType.integer.toJson(),
    );
    expect(plan.source, contains('.value++'));
  });

  test('untranslated existing calls retain their operation spelling', () async {
    final result = await translateFormatting(
      "Text(i.Intl.plural(count, other: 'items', name: null, args: null))",
    );
    expect(result.issues.where((issue) => !issue.code.isBuildNotice), isEmpty);
    expect(result.hoisted, isEmpty);
    expect(result.dsl, contains('intl.plural'));
    expect(result.dsl, isNot(contains('native.call')));
  });

  test('translation fixture is generated from ordinary resolved Dart calls', () async {
    final source = File(
      '../restage_core/test/fixtures/intl_translation_source.dart',
    ).readAsStringSync();
    final output = StringBuffer(
      '// Direct-throw arguments leave the adapter return unreachable.\n'
      '// ignore_for_file: dead_code\n'
      "part of 'intl_translation_source.dart';\n",
    );
    for (final function in [
      'Message',
      'Plural',
      'Gender',
      'Select',
      'AbsentArgs',
      'NullArgs',
      'EmptyArgs',
      'Missing',
      'NullName',
      'ImplicitName',
      'EmptyName',
      'Meaning',
      'WrongArity',
      'WrongType',
      'Ordered',
      'UnusedFallback',
      'MetadataFailure',
      'LiveCount',
      'PluralMeaning',
      'GenderMeaning',
      'SelectMeaning',
      'PluralNullMeaningName',
      'GenderNullMeaningName',
      'SelectNullMeaningName',
      'NestedPluralMeaning',
      'NestedGenderMeaning',
      'NestedSelectMeaning',
    ]) {
      final expression = await parseExpressionFromSourceForTest(
        source,
        rootPackage: 'apps_examples',
        functionName: 'authored$function',
      );
      expect(isInstalledIntlTranslation(expression), isTrue);
      final inputs = <ValueNode>[];
      final parameters = <String, ValueType>{};
      final plan = planInstalledNativeCall(
        expression,
        resultType: ValueType.string,
        constantStrings: validateInstalledIntlTranslation(
          expression as MethodInvocation,
        ),
        captureFor: (element) =>
            function == 'LiveCount' && element.name == 'count'
            ? const InstalledNativeCapture('count', ValueType.integer)
            : null,
        inputFor: (identifier) {
          final name = identifier.name;
          final type = switch (name) {
            'user' || 'gender' => ValueType.string,
            'count' => ValueType.integer,
            'date' => const ValueType.native('dart.DateTime'),
            'token' => const ValueType.native('translation.Token'),
            'choice' => const ValueType.native('translation.Status'),
            _ => throw StateError(name),
          };
          parameters[name] = type;
          final node = inputs.length;
          inputs.add(ValueNode('parameter', type, name: name));
          return InstalledNativeInput(node, type);
        },
      );
      final program = ValueProgram(
        nodes: [...inputs, plan.node],
        root: inputs.length,
        parameters: parameters,
        outerLocals: {if (function == 'LiveCount') 'count': ValueType.integer},
      );
      output.writeln('const intl${function}Binding = ${jsonEncode(plan.key)};');
      output.writeln(
        'r.NativeCallAdapter intl${function}Adapter() => '
        '${plan.adapterSource(core: 'r.', shared: 's.')};',
      );
      output.writeln(
        's.ValueProgram intl${function}Program('
        'Map<String, s.ValueOperation> operations, {s.ValueOperationContext? context}) => '
        's.ValueProgram.decode(${jsonEncode(program.encode())}, operations: operations, context: context);',
      );
    }
    final catalog = decodeCatalog(
      File(
        '../restage_core/lib/src/widget_catalog/catalog.json',
      ).readAsStringSync(),
    );
    for (final (stem, function) in [
      ('Widget', 'authoredTranslatedWidget'),
      ('NullPlural', 'authoredNullPluralWidget'),
      ('NullGender', 'authoredNullGenderWidget'),
      ('NullSelect', 'authoredNullSelectWidget'),
      ('AliasNullPlural', 'authoredAliasNullPluralWidget'),
      ('AliasNullGender', 'authoredAliasNullGenderWidget'),
      ('AliasNullSelect', 'authoredAliasNullSelectWidget'),
    ]) {
      final widget = await parseExpressionFromSourceForTest(
        source,
        rootPackage: 'apps_examples',
        functionName: function,
      );
      final translated = ExpressionTranslator(
        catalog: catalog,
        helpers: HelperRegistry(),
      ).translate(widget, hoistInMount: true);
      expect(
        translated.issues.where((issue) => !issue.code.isBuildNotice),
        isEmpty,
      );
      final installed = translated.hoisted.single.nativeCall!;
      final root =
          rfw
                  .parseLibraryFile(
                    'import restage.core; widget Root = ${translated.dsl};',
                  )
                  .widgets
                  .single
                  .root
              as rfw.ConstructorCall;
      final builder = root.arguments['builder']! as rfw.ConstructorCall;
      final program = builder.arguments['program']! as String;
      output.writeln(
        'const intl${stem}Binding = ${jsonEncode(installed.key)};',
      );
      output.writeln(
        'r.NativeCallAdapter intl${stem}Adapter() => '
        '${installed.adapterSource(core: 'r.', shared: 's.')};',
      );
      output.writeln(
        's.BuilderProgram intl${stem}Program(Map<String, s.ValueOperation> operations) => '
        's.BuilderProgram.decode(${jsonEncode(program)}, operations: operations);',
      );
    }
    final generated = DartFormatter(
      languageVersion: Version(3, 5, 0),
    ).format(output.toString());
    final file = File(
      '../restage_core/test/fixtures/intl_translation_source.g.dart',
    );
    if (Platform.environment['WRITE_INTL_TRANSLATION_FIXTURE'] == '1') {
      file.writeAsStringSync(generated);
    }
    expect(file.readAsStringSync(), generated);
  });
}

// A construct the delivered design can't run is carried, never refused: it
// renders from the app as an island, or the mount records its value.
void _expectCarried(TranslationResult result, {String? reason}) {
  expect(
    result.issues.where((issue) => !issue.code.isBuildNotice),
    isEmpty,
    reason: reason,
  );
  expect(
    result.islands.isNotEmpty || result.hoisted.isNotEmpty,
    isTrue,
    reason: reason,
  );
}
