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
    File(
      '../restage_core/lib/src/widget_catalog/catalog.json',
    ).readAsStringSync(),
  ),
);

Future<TranslationResult> _translate(
  String body, {
  bool hoist = true,
  String parameters = '',
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
      Object x(BuildContext context$parameters) => $body;
    }
    ''',
    rootPackage: 'apps_examples',
    enclosingClassName: 'Probe',
    otherFiles: {'lib/tokens.dart': _tokens},
  );
  final method = expr.thisOrAncestorOfType<MethodDeclaration>()!;
  return ExpressionTranslator(
    catalog: _coreCatalog,
    helpers: HelperRegistry(),
  ).translate(
    expr,
    hoistInMount: hoist,
    buildContextParameter:
        method.declaredFragment!.element.formalParameters.first,
  );
}

const _inkTitle =
    "Text('Hi', style: Styles.title.copyWith(color: Palette.of(context).ink))";

void main() {
  group('device scalar root computations', () {
    for (final source in [
      'SizedBox(height: MediaQuery.viewInsetsOf(context).bottom)',
      "Text('Hi', softWrap: MediaQuery.boldTextOf(context))",
      "Text('Hi', softWrap: MediaQuery.disableAnimationsOf(context))",
      'SizedBox(height: MediaQuery.textScalerOf(context).scale(20))',
    ]) {
      test(source, () async {
        final result = await _translate(source);
        expect(result.issues, isEmpty, reason: '${result.issues}');
        expect(result.hoisted, hasLength(1));
        expect(result.hoisted.single.mountSource(_slot), contains('context'));
      });
    }
  });

  group('runtime lookups move into the mount', () {
    test('an inherited Color result crosses as the native object', () async {
      final result = await _translate(
        'ColoredBox(color: Palette.of(context).ink)',
      );
      expect(result.issues, isEmpty);
      expect(result.hoisted.single.kind, HoistValueKind.nativeBinding);
      expect(result.hoisted.single.nativeContract?.type, 'flutter.Color');
    });

    const scalar = 'MediaQuery.viewInsetsOf(context).bottom';
    // The app evaluates each occurrence, so each is recorded under its own key.
    test('each occurrence of an expression has its own key', () async {
      final result = await _translate(
        'Column(children: [SizedBox(height: $scalar), SizedBox(height: $scalar)])',
      );
      expect(result.issues, isEmpty, reason: '${result.issues}');
      expect(result.hoisted, hasLength(2));
      expect(result.hoisted.map((value) => value.key).toSet(), hasLength(2));
      for (final value in result.hoisted) {
        expect(value.kind, HoistValueKind.scalar);
        expect(value.label, scalar);
        expect(value.shape.toJson(), {'kind': 'double', 'label': scalar});
        expect(value.mountSource(_slot), scalar);
        expect(
          'SizedBox(height: data.context.${value.key})'.allMatches(result.dsl),
          hasLength(1),
        );
      }
    });

    test('keys are stable across builds', () async {
      final a = await _translate('SizedBox(height: $scalar)');
      final b = await _translate('SizedBox(height: $scalar)');
      for (final result in [a, b]) {
        expect(result.issues, isEmpty, reason: '${result.issues}');
        expect(result.hoisted, hasLength(1));
        expect(
          result.dsl,
          'SizedBox(height: data.context.${result.hoisted.single.key})',
        );
      }
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

    test(
      'a copyWith argument over an app style is never dropped silently',
      () async {
        final result = await _translate(
          "Text('Hi', style: Styles.title.copyWith(package: super.toString(), "
          'height: 2))',
        );
        // `super` exists only in the surface, so not even an island can carry it.
        expect(result.islands, isEmpty);
        const message =
            "copyWith argument 'package' has no flat property on "
            "'Text' to carry it.";
        expect(result.issues.map((issue) => issue.message), [message]);
      },
    );

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
    // A widget the mount can build becomes an island, and the surface's own
    // fields are read from an instance of it; `super` still refuses.
    for (final (body, island, refusal) in [
      ('Center(child: Palette.of(context).badge())', 'Probe.x/badge#0', null),
      ('SizedBox(width: Spacing.of(context))', 'Probe.x/SizedBox#0', null),
      (
        'ColoredBox(color: tint.withAlpha(Palette.of(context).ink.alpha))',
        null,
        null,
      ),
      ('ColoredBox(color: ref.watch(Color(0xFF000000)))', null, null),
      (
        'ColoredBox(color: tint.withAlpha(super.hashCode))',
        null,
        '`ColoredBox(color: tint.withAlpha(super.hashCode))` '
            '(lib/_expr_probe.dart:10:41): uses `super`, which only exists '
            "inside `Probe`. Try passing it in through the screen's "
            'constructor.',
      ),
    ]) {
      test(body, () async {
        final result = await _translate(body);
        expect(
          [for (final i in result.islands) i.id],
          [if (island != null) island],
        );
        expect(
          [for (final issue in result.issues) issue.message],
          refusal == null ? isEmpty : [refusal],
        );
      });
    }

    test('a widget built in place is not a lookup', () async {
      final result = await _translate(
        'Center(child: Art.badge(context), heightFactor: Spacing.of(context))',
      );
      expect(
        result.issues.map((issue) => issue.message),
        isNot(contains(startsWith("'Center("))),
      );
    });
  });
}

// Reads each mount slot by its name, and the build context as `context`.
String _slot(String name) => name == kRootContext ? 'context' : name;
