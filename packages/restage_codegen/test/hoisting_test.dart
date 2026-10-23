import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';

import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/hoisting.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import 'helpers.dart';

const _tokens = '''
import 'package:flutter/widgets.dart';

class Palette extends InheritedWidget {
  const Palette({super.key, required super.child, required this.ink});
  final Color ink;
  static Palette of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<Palette>()!;
  @override
  bool updateShouldNotify(Palette old) => ink != old.ink;

  Widget badge() => const SizedBox();
}

abstract final class Styles {
  static final TextStyle title = _sized(28);
  static TextStyle _sized(double size) => TextStyle(fontSize: size);
}

class Spacing {
  const Spacing(this.gap);
  final double gap;
  static Spacing of(BuildContext context) => const Spacing(8);
}

final class Ref {
  const Ref();
  Color watch(Color value) => value;
}

abstract final class Art {
  static Widget badge(BuildContext context) => const SizedBox();
}
''';

final Catalog _coreCatalog = requireNativeCatalog(
  decodeCatalog(
    File('../restage_core/lib/src/widget_catalog/catalog.json')
        .readAsStringSync(),
  ),
);

Future<TranslationResult> _translate(
  String body, {
  bool hoist = true,
}) async {
  final expr = await parseExpressionFromSourceForTest(
    '''
    import 'package:flutter/widgets.dart';
    import 'package:apps_examples/tokens.dart';
    class Probe extends StatelessWidget {
      const Probe({super.key});
      final Ref ref = const Ref();
      final Color tint = const Color(0xFF000000);
      final String font = 'Serif';
      @override
      Widget build(BuildContext context) => const SizedBox();
      Object x(BuildContext context) => $body;
    }
    ''',
    rootPackage: 'apps_examples',
    enclosingClassName: 'Probe',
    otherFiles: {'lib/tokens.dart': _tokens},
  );
  final method = expr.thisOrAncestorOfType<MethodDeclaration>()!;
  return ExpressionTranslator(catalog: _coreCatalog, helpers: HelperRegistry())
      .translate(
    expr,
    hoistInMount: hoist,
    buildContextParameter:
        method.declaredFragment!.element.formalParameters.first,
  );
}

const _inkTitle =
    "Text('Hi', style: Styles.title.copyWith(color: Palette.of(context).ink))";

/// The error messages one translation reports.
Future<List<String>> _messages(String body) async =>
    [for (final issue in (await _translate(body)).issues) issue.message];

void main() {
  group('runtime lookups move into the mount', () {
    test('an inherited color', () async {
      final result =
          await _translate('ColoredBox(color: Palette.of(context).ink)');
      expect(result.issues, isEmpty, reason: '${result.issues}');
      final value = result.hoisted.single;
      expect(value.label, 'Palette.of(context).ink');
      expect(value.shape.toJson(), {
        'kind': 'int',
        'label': 'Palette.of(context).ink',
      });
      expect(result.dsl, 'ColoredBox(color: data.context.${value.key})');
      expect(
        value.mountSource((name) => name),
        'Palette.of(context).ink',
      );
    });

    test('the same expression shares one key', () async {
      final result = await _translate(
        'Column(children: [ColoredBox(color: Palette.of(context).ink), '
        'ColoredBox(color: Palette.of(context).ink)])',
      );
      expect(result.issues, isEmpty, reason: '${result.issues}');
      expect(result.hoisted, hasLength(1));
    });

    test('keys are stable across builds', () async {
      final a = await _translate('ColoredBox(color: Palette.of(context).ink)');
      final b = await _translate('ColoredBox(color: Palette.of(context).ink)');
      expect(a.hoisted.single.key, b.hoisted.single.key);
      expect(a.hoisted.single.key, matches(RegExp(r'^_h[0-9a-f]{10}$')));
    });

    test('a lowerable value stays in the payload', () async {
      final result = await _translate('ColoredBox(color: Color(0xFF112233))');
      expect(result.issues, isEmpty, reason: '${result.issues}');
      expect(result.hoisted, isEmpty);
    });

    test('a static final style decomposes into reads of one value', () async {
      final result = await _translate(_inkTitle);
      expect(result.issues, isEmpty, reason: '${result.issues}');
      final value = result.hoisted.single;
      expect(
        value.label,
        'Styles.title.copyWith(color: Palette.of(context).ink)',
      );
      expect(
        result.dsl,
        contains('fontSize: data.context.${value.key}.fontSize'),
      );
      expect(result.dsl, contains('color: data.context.${value.key}.color'));
    });

    test('a style reads every field a text style carries', () async {
      final result = await _translate("Text('Hi', style: Styles.title)");
      expect(result.issues, isEmpty, reason: '${result.issues}');
      final key = result.hoisted.single.key;
      for (final field in kHoistedTextStyleFields.keys) {
        expect(result.dsl, contains('data.context.$key.$field'), reason: field);
      }
    });

    test('a style setting a paint says the paint is kept in part', () async {
      final result = await _translate(
        "Text('Hi', style: Styles.title.copyWith(foreground: "
        'Paint()..color = Palette.of(context).ink))',
      );
      expect(result.issues, isEmpty, reason: '${result.issues}');
      expect(result.hoisted.single.paints, ['foreground']);
    });

    test('a copyWith argument over an app style is never dropped silently',
        () async {
      final result = await _translate(
        "Text('Hi', style: Styles.title.copyWith(package: font, height: 2))",
      );
      expect(result.hoisted.single.label, 'Styles.title');
      const message = "copyWith argument 'package' has no flat property on "
          "'Text' to carry it.";
      expect(result.issues.map((issue) => issue.message), [message]);
    });

    test('a comment edit keeps the contract hash', () async {
      Future<String?> hash(String body) async {
        final result = await _translate(body);
        expect(result.issues, isEmpty, reason: '${result.issues}');
        final value = result.hoisted.single;
        return SurfaceScreenHostDataContractHash.hash(
          SurfaceScreenHostDataSchema({value.key: value.shape}),
        );
      }

      final plain = await hash(_inkTitle);
      final commented = await hash(
        "Text('Hi', style: Styles.title.copyWith(/* the brand ink */ "
        'color: Palette.of(context).ink))',
      );
      expect(commented, plain);
    });

    test('formatting changes neither the label nor the key', () async {
      final compact = await _translate(_inkTitle);
      final spread = await _translate('''
Text('Hi', style: Styles.title.copyWith(
  color: Palette.of(context).ink,
))''');
      expect(spread.issues, isEmpty, reason: '${spread.issues}');
      expect(spread.hoisted.single.label, compact.hoisted.single.label);
      expect(spread.hoisted.single.key, compact.hoisted.single.key);
    });

    test('without a mount nothing moves', () async {
      final result = await _translate(
        'ColoredBox(color: Palette.of(context).ink)',
        hoist: false,
      );
      expect(result.hoisted, isEmpty);
      expect(result.issues, isNotEmpty);
    });
  });

  group('what the mount cannot compute', () {
    test('a lookup that returns a widget', () async {
      const message = "'Palette.of(context).badge()' returns a widget. "
          'Register that widget as a custom widget to use it here.';
      expect(
        await _messages('Center(child: Palette.of(context).badge())'),
        [message],
      );
    });

    test('a value only the surface has', () async {
      const message = "'tint.withAlpha(Palette.of(context).ink.alpha)' "
          "depends on 'tint', which exists only inside this surface. Pass the "
          'value in as a constructor input.';
      expect(
        await _messages(
          'ColoredBox(color: tint.withAlpha(Palette.of(context).ink.alpha))',
        ),
        [message],
      );
    });

    test('a ref the build does not receive', () async {
      const message = "'ref' needs this screen to extend a widget whose "
          'build receives it, such as ConsumerWidget.';
      expect(
        await _messages('ColoredBox(color: ref.watch(Color(0xFF000000)))'),
        [message],
      );
    });

    test('a widget built in place is not a lookup', () async {
      final result = await _translate(
        'Center(child: Art.badge(context), heightFactor: Spacing.of(context))',
      );
      expect(
        result.issues.map((issue) => issue.message),
        isNot(contains(startsWith("'Center("))),
      );
    });

    test('a value of a type that cannot cross', () async {
      const message = "'Spacing.of(context)' is a Spacing, which a surface "
          "can't receive. Pass a color, number, string, text style or enum.";
      expect(await _messages('SizedBox(width: Spacing.of(context))'), [
        message,
      ]);
    });
  });
}
