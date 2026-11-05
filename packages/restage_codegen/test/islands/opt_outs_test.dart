import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:restage_codegen/src/islands/opt_outs.dart';
import 'package:test/test.dart';

import '../helpers.dart';

const _imports = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';
''';

const _plain =
    '''
$_imports
class Plain extends StatelessWidget {
  const Plain({super.key});
  @override
  Widget build(BuildContext context) => const Text('plain');
}
''';

void main() {
  test('an opt-out keeps a widget as the app builds it', () async {
    // Each case: the source of `x()`, other files, and where the annotation
    // is, or null when nothing opts out.
    final cases = <(String, Map<String, String>, String?)>[
      ("$_imports\nWidget x() => const Text('a');", const {}, null),
      (
        '''
$_imports
@RenderInApp()
class Badge extends StatelessWidget {
  const Badge({super.key});
  @override
  Widget build(BuildContext context) => const Text('b');
}
Widget x() => const Badge();
''',
        const {},
        '`Badge`',
      ),
      (
        "$_imports\nimport 'ds/plain.dart';\nWidget x() => const Plain();",
        {
          'lib/ds/plain.dart': '@RenderInApp()\nlibrary;\n$_plain',
        },
        'package:apps_examples/ds/plain.dart',
      ),
      (
        "$_imports\nimport 'ds.dart';\nWidget x() => const Plain();",
        {
          'lib/ds.dart':
              "@RenderInApp()\nlibrary;\n$_imports\n"
              "export 'ds/plain.dart';\n",
          'lib/ds/plain.dart': _plain,
        },
        'package:apps_examples/ds.dart',
      ),
      (
        '''
$_imports
Widget x() => Builder(builder: (context) {
      @RenderInApp()
      final shown = const Text('kept');
      return shown;
    });
''',
        const {},
        'the variable that holds it',
      ),
    ];
    for (final (source, others, where) in cases) {
      final root = await parseExpressionFromSourceForTest(
        source,
        rootPackage: 'apps_examples',
        otherFiles: others,
      );
      final node = where == 'the variable that holds it'
          ? _initializer(root)
          : root;
      final issue = optOutOf(node, 'lib/_expr_probe.dart:1:1');
      expect(
        issue?.message,
        where == null
            ? isNull
            : "Designs can't change `${_name(node)}` "
                  '(lib/_expr_probe.dart:1:1) because `@RenderInApp` is on '
                  '$where.',
        reason: source,
      );
    }
  });
}

String _name(Expression node) => switch (node) {
  InstanceCreationExpression(:final constructorName) =>
    constructorName.type.name.lexeme,
  _ => node.toSource(),
};

Expression _initializer(Expression root) {
  Expression? found;
  root.accept(_Initializers((node) => found ??= node));
  return found!;
}

final class _Initializers extends RecursiveAstVisitor<void> {
  _Initializers(this.found);

  final void Function(Expression) found;

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    if (node.initializer case final initializer?) found(initializer);
    super.visitVariableDeclaration(node);
  }
}
