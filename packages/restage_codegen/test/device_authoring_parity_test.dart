import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:restage_codegen/src/build_body.dart';
import 'package:restage_codegen/src/capability_derivation.dart';
import 'package:restage_codegen/src/custom_widget_blueprint.dart';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/hoisting.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart' show parseLibraryFile;
import 'package:test/test.dart';

import 'helpers.dart';

final _catalog = requireNativeCatalog(
  decodeCatalog(
    File(
      '../restage_core/lib/src/widget_catalog/catalog.json',
    ).readAsStringSync(),
  ),
);

Future<TranslationResult> _translate(
  String body, {
  bool mount = true,
  String declarations = '',
  String prelude = '',
}) async {
  final expr = await parseExpressionFromSourceForTest(
    '''
import 'package:flutter/widgets.dart';
import 'package:flutter/widgets.dart' as f;
$declarations
class Probe extends StatelessWidget {
  const Probe({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox();
  Object source(BuildContext context, BuildContext local) {
    $prelude
    return $body;
  }
  Object x() => const SizedBox();
}
''',
    rootPackage: 'apps_examples',
    enclosingClassName: 'Probe',
  );
  final method = expr
      .thisOrAncestorOfType<ClassDeclaration>()!
      .body
      .members
      .whereType<MethodDeclaration>()
      .singleWhere((method) => method.name.lexeme == 'source');
  final bodySource = extractInlinableBuildBody(method.body)!;
  final definitions = inlinableHelperDefinitionsIn(expr);
  return ExpressionTranslator(
    catalog: _catalog,
    helpers: HelperRegistry(),
  ).translate(
    bodySource.expression,
    rootInlined: InlinedDefinitions(
      localBindings: withHelperLocals(
        bodySource.localBindings,
        definitions.values,
      ),
      helpers: definitions,
    ),
    hoistInMount: mount,
    buildContextParameter:
        method.declaredFragment!.element.formalParameters.first,
  );
}

void main() {
  test('new primitive paths require capability 18 only when referenced', () {
    for (final path in [
      'viewInsetsTop',
      'viewInsetsRight',
      'viewInsetsBottom',
      'viewInsetsLeft',
      'boldText',
      'disableAnimations',
      'accessibleNavigation',
      'highContrast',
    ]) {
      final result = deriveCapabilityManifest(
        parseLibraryFile('''
import restage.core;
widget Root = Text(text: "Hi", softWrap: data.device.$path);
'''),
        _catalog,
      );
      expect(result.manifest!.builtInFloor, 18, reason: path);
    }
  });

  test('device kinds accept only matching scalar slots', () {
    for (final type in PropertyType.values) {
      expect(
        propertyTypeAcceptsDeviceKind(type, DeviceContractValueKind.boolean),
        type == PropertyType.boolean,
        reason: type.name,
      );
    }
    expect(
      propertyTypeAcceptsDeviceKind(
        PropertyType.boolean,
        DeviceContractValueKind.size,
      ),
      isFalse,
    );
  });

  for (final source in [
    'SizedBox(height: MediaQuery.viewInsetsOf(context).bottom)',
    "Text('Hi', softWrap: MediaQuery.of(context).boldText)",
    "Text('Hi', softWrap: !MediaQuery.disableAnimationsOf(context))",
    "Text('Hi', softWrap: MediaQuery.accessibleNavigationOf(context) && MediaQuery.highContrastOf(context))",
    'SizedBox(height: MediaQuery.textScalerOf(context).scale(12))',
  ]) {
    test('resolved scalar $source', () async {
      final result = await _translate(source);
      expect(result.issues, isEmpty, reason: '${result.issues}');
      expect(result.dsl, isNotEmpty);
      final capability = deriveCapabilityManifest(
        parseLibraryFile('import restage.core; widget Root = ${result.dsl};'),
        _catalog,
      );
      expect(capability.manifest!.builtInFloor, lessThan(18));
    });
  }

  group('scalar helper provenance', () {
    const declarations =
        'bool bold(BuildContext c) => MediaQuery.boldTextOf(c); '
        'bool highContrast(BuildContext c) => MediaQuery.highContrastOf(c); '
        'bool composed(BuildContext c) => !bold(c) && highContrast(c); '
        'bool withLocal(BuildContext c) { final root = c; final flag = composed(root); return flag; }';
    for (final (expression, prelude) in [
      ("Text('Hi', softWrap: bold(context))", ''),
      ("Text('Hi', softWrap: composed(context))", ''),
      ("Text('Hi', softWrap: withLocal(context))", ''),
      (
        "Text('Hi', softWrap: !flag || highContrast(root))",
        'final root = context; final flag = bold(root);',
      ),
    ]) {
      test(expression, () async {
        final result = await _translate(
          expression,
          declarations: declarations,
          prelude: prelude,
        );
        expect(result.issues, isEmpty, reason: '${result.issues}');
        expect(result.hoisted, hasLength(1));
        expect(result.hoisted.single.kind, HoistValueKind.scalar);
        expect(
          result.dsl,
          contains('data.context.${result.hoisted.single.key}'),
        );
        expect(result.dsl, isNot(contains('data.device.')));
        final capability = deriveCapabilityManifest(
          parseLibraryFile('import restage.core; widget Root = ${result.dsl};'),
          _catalog,
        );
        expect(capability.manifest!.builtInFloor, lessThan(18));
      });
    }
    test(
      'same helper spelling without a native read stays in the payload',
      () async {
        final result = await _translate(
          "Text('Hi', softWrap: bold(context))",
          declarations: 'bool bold(BuildContext c) => false;',
        );
        expect(result.issues, isEmpty);
        expect(result.hoisted, isEmpty);
        expect(result.dsl, contains('softWrap: false'));
      },
    );
    test(
      'a helper reading an independent context cannot use the root binding',
      () async {
        final result = await _translate(
          "Text('Hi', softWrap: bold(local))",
          declarations: declarations,
        );
        expect(result.issues, isNotEmpty);
        expect(result.hoisted, isEmpty);
      },
    );
  });

  group('nested scalar helper provenance', () {
    const declarations =
        'bool pass(bool value) => value; '
        'bool ignore(bool value) => true;';
    for (final (expression, prelude) in [
      ("Text('Hi', softWrap: pass(pass(MediaQuery.boldTextOf(context))))", ''),
      (
        "Text('Hi', softWrap: pass(pass(value)))",
        'final value = MediaQuery.boldTextOf(context);',
      ),
      (
        "Text('Hi', softWrap: ignore(pass(MediaQuery.boldTextOf(context))))",
        '',
      ),
      (
        "Text('Hi', softWrap: pass(pass(false)) || pass(pass(value)))",
        'final value = MediaQuery.boldTextOf(context);',
      ),
    ]) {
      test(expression, () async {
        final result = await _translate(
          expression,
          declarations: declarations,
          prelude: prelude,
        );
        expect(result.issues, isEmpty, reason: '${result.issues}');
        final capability = deriveCapabilityManifest(
          parseLibraryFile('import restage.core; widget Root = ${result.dsl};'),
          _catalog,
        );
        expect(capability.manifest!.builtInFloor, lessThan(18));
        expect(result.hoisted, hasLength(1));
        expect(result.hoisted.single.kind, HoistValueKind.scalar);
        // The app evaluates the whole argument as written, in the mount's
        // context.
        final written = expression.substring(
          "Text('Hi', softWrap: ".length,
          expression.length - 1,
        );
        expect(
          result.hoisted.single.mountSource((name) => name),
          written.replaceAll('(context)', '(restageRootContext)'),
        );
        expect(result.dsl, isNot(contains('data.device.')));
      });
    }
    test('nested named arguments keep their caller bindings', () async {
      final result = await _translate(
        "Text('Hi', softWrap: pass(value: pass(value: MediaQuery.boldTextOf(context))))",
        declarations: 'bool pass({required bool value}) => value;',
      );
      expect(result.issues, isEmpty, reason: '${result.issues}');
      expect(result.hoisted, hasLength(1));
      expect(result.hoisted.single.kind, HoistValueKind.scalar);
      expect(result.dsl, isNot(contains('data.device.')));
    });
    test('negative helper chains stay in the payload', () async {
      for (final source in [
        'pass(pass(pass(false)))',
        'ignore(pass(pass(false)))',
      ]) {
        final result = await _translate(
          "Text('Hi', softWrap: $source)",
          declarations: declarations,
        );
        expect(result.issues, isEmpty, reason: '${result.issues}');
        expect(result.hoisted, isEmpty);
        expect(result.dsl, isNot(contains('data.device.')));
      }
    });
    test('a shadowing helper resolves to its own body', () async {
      final result = await _translate(
        "Text('Hi', softWrap: Other.pass(context))",
        declarations:
            'bool pass(BuildContext c) => MediaQuery.boldTextOf(c); '
            'class Other { static bool pass(BuildContext c) => false; }',
      );
      expect(result.issues, isEmpty);
      expect(result.hoisted, isEmpty);
      expect(result.dsl, contains('softWrap: false'));
    });
    test('nested arguments retain independent-context refusal', () async {
      final result = await _translate(
        "Text('Hi', softWrap: pass(pass(MediaQuery.boldTextOf(local))))",
        declarations: declarations,
      );
      expect(result.issues, isNotEmpty);
      expect(result.hoisted, isEmpty);
    });
  });

  for (final source in [
    "Text('Hi', textScaler: MediaQuery.textScalerOf(context))",
    "f.Text('Hi', textScaler: f.MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.8))",
    "Text.rich(TextSpan(text: 'Hi'), textScaler: MediaQuery.of(context).textScaler)",
  ]) {
    test('exact native scaler $source', () async {
      final result = await _translate(source);
      expect(result.issues, isEmpty, reason: '${result.issues}');
      expect(result.hoisted.single.kind, HoistValueKind.textScaler);
      final value = result.hoisted.single;
      expect(result.dsl, contains('textScaler: data.context.${value.key}'));
      expect(
        value.shape.toJson(),
        containsPair('fields', containsPair('key', {'kind': 'string'})),
      );
      final capability = deriveCapabilityManifest(
        parseLibraryFile('import restage.core; widget Root = ${result.dsl};'),
        _catalog,
      );
      expect(capability.manifest!.builtInFloor, 18);
    });
  }

  for (final (source, recipe) in [
    ('TextScaler.noScaling', '{kind: "none"}'),
    ('TextScaler.linear(1.4)', '{kind: "linear", factor: 1.4}'),
  ]) {
    test('literal recipe $source', () async {
      final result = await _translate("Text('Hi', textScaler: $source)");
      expect(result.issues, isEmpty, reason: '${result.issues}');
      expect(result.hoisted, isEmpty);
      expect(result.dsl, contains('textScaler: $recipe'));
    });
  }

  test(
    'an app-defined nonlinear scaler uses the same native binding',
    () async {
      final result = await _translate(
        "Text('Hi', textScaler: const CustomScaler())",
        declarations:
            'class CustomScaler extends f.TextScaler { const CustomScaler(); '
            'double scale(double size) => size + size * size / 100; '
            'double get textScaleFactor => 1.14; }',
      );
      expect(result.issues, isEmpty, reason: '${result.issues}');
      expect(result.hoisted.single.kind, HoistValueKind.textScaler);
      expect(
        result.hoisted.single.mountSource((name) => name),
        'const CustomScaler()',
      );
    },
  );

  test('a TextScaler lookalike cannot use the framework recipe', () async {
    final result = await _translate(
      "Text('Hi', textScaler: TextScaler.linear(1.4))",
      declarations:
          'class TextScaler { const TextScaler.linear(double factor); }',
    );
    // No framework recipe stands in for the app's own class: the Text renders
    // from the app.
    expect(result.dsl, isNot(contains('kind: "linear"')));
    expect(result.dsl, 'Probe_Text_0()');
    expect(result.islands, hasLength(1));
  });

  test('a descendant context never becomes the root snapshot', () async {
    for (final expression in [
      "Text('Hi', textScaler: MediaQuery.textScalerOf(local))",
      "Text('Hi', softWrap: MediaQuery.boldTextOf(local))",
      'SizedBox(height: MediaQuery.viewInsetsOf(local).bottom)',
    ]) {
      final result = await _translate(expression);
      expect(result.issues, isNotEmpty, reason: expression);
      expect(result.hoisted, isEmpty, reason: expression);
      expect(
        result.dsl,
        isNot(contains('context:device:')),
        reason: expression,
      );
    }
  });

  test('a native callback owns its same-named local context', () async {
    final result = await _translate(
      'LayoutBuilder(builder: (local, constraints) => '
      "Text('Hi', softWrap: MediaQuery.boldTextOf(local)))",
    );
    expect(result.issues, isEmpty);
    expect(result.hoisted, isEmpty);
    expect(result.dsl, contains('context:device:boldText'));
    expect(result.dsl, isNot(contains('data.device.boldText')));
    expect(
      () => parseLibraryFile(
        'import restage.core; widget Root = ${result.dsl};',
      ),
      returnsNormally,
    );
  });

  test('an ordinary scalar program may read the context-free platform', () async {
    final result = await _translate(
      'SizedBox(width: (defaultTargetPlatform == TargetPlatform.android ? 1 : 2) / 2)',
      mount: false,
      declarations: "import 'package:flutter/foundation.dart';",
    );
    expect(result.issues, isEmpty);
    expect(result.hoisted, isEmpty);
    expect(result.dsl, contains('context:device:defaultTargetPlatform'));
    expect(result.dsl, contains('program:'));
    expect(
      () => parseLibraryFile(
        'import restage.core; widget Root = ${result.dsl};',
      ),
      returnsNormally,
    );
  });

  test('native scaler needs its generated mount', () async {
    final result = await _translate(
      "Text('Hi', textScaler: MediaQuery.textScalerOf(context))",
      mount: false,
    );
    expect(result.issues, isNotEmpty);
    expect(result.hoisted, isEmpty);
  });

  // A value of the wrong kind never reaches the payload: the widget renders
  // from the app.
  test('primitive kind mismatch stays out of the payload', () async {
    for (final (source, island) in [
      ('SizedBox(width: MediaQuery.boldTextOf(context))', 'SizedBox'),
      ('SizedBox(width: !MediaQuery.boldTextOf(context))', 'SizedBox'),
      (
        'SizedBox(width: MediaQuery.boldTextOf(context) && MediaQuery.highContrastOf(context))',
        'SizedBox',
      ),
      (
        "Text('Hi', softWrap: MediaQuery.viewInsetsOf(context).bottom + 1)",
        'Text',
      ),
      ("Text('Hi', softWrap: MediaQuery.viewInsetsOf(context).bottom)", 'Text'),
    ]) {
      final result = await _translate(source);
      expect(result.dsl, 'Probe_${island}_0()', reason: source);
      expect(result.hoisted, isEmpty, reason: source);
      expect(result.islands, hasLength(1), reason: source);
    }
  });
}
