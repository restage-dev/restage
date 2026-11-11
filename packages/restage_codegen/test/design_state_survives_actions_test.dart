import 'dart:convert';
import 'dart:io';

import 'package:build/build.dart';
import 'package:restage_codegen/src/surface_publication/compiler_handoff.dart';
import 'package:restage_codegen/src/surface_publication/package_surface_compiler_builder.dart';
import 'package:test/test.dart';

import 'helpers.dart';

// A plan picker whose State the design owns, with a Continue action.
String _source(
  String continueTap, {
  String annotation = '@rs.Paywall()',
  String extraParams = '',
  String extraFields = '',
  String extraMembers = '',
  String selectAnnual = 'setState(() => annualSelected = true);',
  String extraChildren = '',
  String library = 'widgets',
}) =>
    '''
import 'package:flutter/$library.dart';
import 'package:restage/restage.dart' as rs;
import 'package:restage/restage.dart' show SurfaceEventContext;
part 'restage.generated/entry.restage.g.dart';

$annotation
class PlanPicker extends StatefulWidget {
  static const continueFlow = rs.SurfaceEvent<Map<String, Object?>>('continue');
  const PlanPicker({super.key, this.onContinue, this.onChoose, this.onClose$extraParams});
  final void Function(String plan)? onContinue;
  final void Function(bool annual)? onChoose;
  final void Function()? onClose;
  $extraFields
  @override
  State<PlanPicker> createState() => _PlanPickerState();
}

class _PlanPickerState extends State<PlanPicker> {
  bool annualSelected = true;
  void selectAnnual() { $selectAnnual }
  void selectMonthly() => setState(() => annualSelected = false);
  $extraMembers
  @override
  Widget build(BuildContext context) => Column(children: [
        GestureDetector(
          onTap: selectAnnual,
          child: Text(annualSelected ? 'Annual (selected)' : 'Annual'),
        ),
        GestureDetector(
          onTap: selectMonthly,
          child: Text(annualSelected ? 'Monthly' : 'Monthly (selected)'),
        ),
        GestureDetector(onTap: $continueTap, child: const Text('Continue')),
        $extraChildren
      ]);
}
''';

typedef _Built = ({
  bool succeeded,
  List<String> errors,
  List<String> warnings,
  String rfwtxt,
  String mount,
  String capabilities,
});

Future<_Built> _build(String source) async {
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: 'apps_examples',
  );
  final warnings = <String>[];
  final result = await testBuilder(
    const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
    {'apps_examples|lib/entry.dart': source},
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
    flattenOutput: true,
    onLog: (record) {
      if (record.level.name == 'WARNING' &&
          record.message.contains("stays in your app's code")) {
        warnings.add(record.message);
      }
    },
  );
  final bundle = RestageSurfacePublicationBundle.fromJson(
    jsonDecode(
      readerWriter.testing.readString(
        AssetId('apps_examples', kRestageSurfacePublicationCompilerBundlePath),
      ),
    ),
  );
  String output(bool Function(String path) matches) => [
    for (final entry in bundle.ownedOutputs.entries)
      if (matches(entry.key)) utf8.decode(entry.value),
  ].join('\n');
  return (
    succeeded: result.succeeded,
    errors: result.errors.toList(),
    warnings: warnings,
    rfwtxt: output((path) => path.endsWith('.rfwtxt')),
    mount: output((path) => path.endsWith('.dart')),
    capabilities: output((path) => path.endsWith('.capability.json')),
  );
}

const _toggles =
    'GestureDetector(onTap: [set state.annualSelected = true, '
    'event "__restage_measurement_tap_v1" {}], child: Text(text: switch '
    'state.annualSelected { true: "Annual (selected)", false: "Annual" })), '
    'GestureDetector(onTap: [set state.annualSelected = false, '
    'event "__restage_measurement_tap_v1" {}], child: Text(text: switch '
    'state.annualSelected { true: "Monthly", false: "Monthly (selected)" }))';

void _expectDesignOwnsState(_Built built, {bool recorded = true}) {
  expect(built.errors, isEmpty);
  expect(built.succeeded, isTrue);
  expect(built.rfwtxt, contains('{ annualSelected: true }'));
  expect(built.rfwtxt, contains(_toggles));
  expect(built.rfwtxt, isNot(contains('_restageRecording')));
  // The mount's copy keeps State for the compiled original only.
  if (recorded) expect(built.mount, contains('bool annualSelected = true;'));
  expect(built.mount, isNot(contains("_restageRecording.value(")));
}

const _buyButton = '''
class BuyButton extends StatelessWidget {
  const BuyButton({super.key, this.onPressed});
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) =>
      GestureDetector(onTap: onPressed, child: const Text('Buy'));
}
''';

final _program = RegExp(
  r'onTap: \{nativeEvent: \{ version: 1, program: ".*?", '
  r'captures: \{c0: data\.context\._h[0-9a-f]{10}, c1: (.*?) \} \}, measurement',
);

void main() {
  test(
    'a callback action with a state argument keeps the design state',
    () async {
      final built = await _build(
        _source(
          "() => widget.onContinue?.call(annualSelected ? 'annual' : 'monthly')",
        ),
      );
      _expectDesignOwnsState(built);
      final action = _program.firstMatch(built.rfwtxt);
      expect(action, isNotNull, reason: built.rfwtxt);
      expect(
        action!.group(1),
        'switch state.annualSelected { true: "annual", false: "monthly" }',
      );
      expect(built.mount, contains('_restageInput0?.call(_restageInput1)'));
      expect(built.warnings, isEmpty);
    },
  );

  test('a bare state argument is captured as the state read', () async {
    final built = await _build(
      _source('() => widget.onChoose?.call(annualSelected)'),
    );
    _expectDesignOwnsState(built);
    expect(
      _program.firstMatch(built.rfwtxt)?.group(1),
      'state.annualSelected',
      reason: built.rfwtxt,
    );
  });

  test(
    'a typed event with a state argument keeps the design state',
    () async {
      final built = await _build(
        _source(
          'context.surfaceEvent(PlanPicker.continueFlow, '
          "{'plan': annualSelected ? 'annual' : 'monthly'})",
        ),
      );
      _expectDesignOwnsState(built, recorded: false);
      expect(
        built.rfwtxt,
        contains(
          'event "continue" {plan: switch state.annualSelected '
          '{ true: "annual", false: "monthly" }',
        ),
      );
    },
  );

  test('a constant argument keeps the design state', () async {
    final built = await _build(
      _source("() => widget.onContinue?.call('annual')"),
    );
    _expectDesignOwnsState(built);
    expect(
      built.rfwtxt,
      matches(RegExp(r'onTap: \{nativeEvent: data\.context\._h[0-9a-f]{10}')),
    );
  });

  test('a widget field argument keeps the design state', () async {
    final built = await _build(
      _source(
        '() => widget.onContinue?.call(widget.planId)',
        extraParams: ", this.planId = 'annual'",
        extraFields: 'final String planId;',
      ),
    );
    _expectDesignOwnsState(built);
    expect(
      built.rfwtxt,
      matches(RegExp(r'onTap: \{nativeEvent: data\.context\._h[0-9a-f]{10}')),
    );
  });

  test('a general screen lowers the same callback action', () async {
    final built = await _build(
      _source(
        "() => widget.onContinue?.call(annualSelected ? 'annual' : 'monthly')",
        annotation:
            "@rs.Screen(id: 'plan_picker', surface: rs.Surface.general)",
      ),
    );
    expect(built.errors, isEmpty);
    expect(built.succeeded, isTrue);
    expect(built.rfwtxt, contains('{ annualSelected: true }'));
    expect(built.rfwtxt, contains(_toggles));
    expect(
      _program.firstMatch(built.rfwtxt)?.group(1),
      'switch state.annualSelected { true: "annual", false: "monthly" }',
      reason: built.rfwtxt,
    );
  });

  test('a typed event beside a plain callback reads the design state', () async {
    final built = await _build(
      _source(
        'context.surfaceEvent(PlanPicker.continueFlow, '
        "{'term': annualSelected ? 'annual' : 'monthly'})",
        extraChildren:
            "GestureDetector(onTap: widget.onClose, child: const Text('Close')),",
      ),
    );
    _expectDesignOwnsState(built);
    expect(
      built.rfwtxt,
      contains(
        'event "continue" {term: switch state.annualSelected '
        '{ true: "annual", false: "monthly" }',
      ),
    );
  });

  for (final (name, handler) in [
    ('in the design', 'setState(() => annualSelected = true);'),
    ('kept in the app', 'annualSelected = true; setState(() {});'),
  ]) {
    test(
      'a typed event in a sheet reading State $name gives valid output',
      () async {
        final built = await _build(
          _source(
            '() => showModalBottomSheet<void>(context: context, '
            'builder: (_) => GestureDetector('
            'onTap: context.surfaceEvent(PlanPicker.continueFlow, '
            "{'term': annualSelected ? 'annual' : 'monthly'}), "
            "child: const Text('Start')))",
            library: 'material',
            selectAnnual: handler,
            extraChildren:
                "GestureDetector(onTap: widget.onClose, child: const Text('Close')),",
          ),
        );
        expect(built.succeeded, isTrue);
        expect(built.rfwtxt, contains('event "continue" {term: '));
        expect(
          built.rfwtxt.contains('set state.annualSelected'),
          handler.startsWith('setState'),
        );
        expect(
          built.errors.where(
            (error) => error.contains('malformedTranslatorOutput'),
          ),
          isEmpty,
        );
      },
    );
  }

  test('an app object in an argument is called when the action runs', () async {
    final built = await _build(
      _source(
            '() => widget.onContinue?.call(widget.plans.pick(annualSelected))',
            extraParams: ', this.plans = const Plans()',
            extraFields: 'final Plans plans;',
          ) +
          '''
class Plans {
  const Plans();
  String pick(bool annual) => annual ? 'annual' : 'monthly';
}
''',
    );
    _expectDesignOwnsState(built);
    expect(built.warnings, isEmpty);
    expect(
      built.rfwtxt,
      matches(
        RegExp(
          r'captures: \{c0: data\.context\._h[0-9a-f]{10}, '
          r'c1: data\.context\._h[0-9a-f]{10}, c2: state\.annualSelected \}',
        ),
      ),
    );
    expect(built.mount, contains('_restageInput1.pick(_restageInput2)'));
  });

  test(
    'a computed State getter keeps State in the app and says why',
    () async {
      final built = await _build(
        _source(
          '() => widget.onContinue?.call(plan)',
          extraMembers:
              "String get plan => annualSelected ? 'annual' : 'monthly';",
        ),
      );
      expect(built.errors, isEmpty);
      expect(built.succeeded, isTrue);
      expect(built.rfwtxt, contains('widget Paywall = '));
      expect(built.rfwtxt, isNot(contains('set state.')));
      expect(built.warnings, hasLength(1));
      expect(
        built.warnings.single,
        allOf(
          contains("`_PlanPickerState` stays in your app's code"),
          contains(
            '`plan` is a getter your app computes from the State the design '
            'keeps',
          ),
          contains(
            'Try reading the State fields it computes from in the design',
          ),
        ),
      );
    },
  );

  test('a required callback splits like a nullable one', () async {
    final built = await _build(
      _source(
        "() => widget.onPlan(annualSelected ? 'annual' : 'monthly', "
        'widget.planId)',
        extraParams: ", required this.onPlan, this.planId = 'spring'",
        extraFields:
            'final void Function(String plan, String id) onPlan;\n'
            '  final String planId;',
      ),
    );
    _expectDesignOwnsState(built);
    expect(built.warnings, isEmpty);
    expect(
      built.rfwtxt,
      contains(
        'c1: switch state.annualSelected { true: "annual", false: "monthly" }',
      ),
    );
    expect(
      built.mount,
      contains('_restageInput0(_restageInput1, _restageInput2)'),
    );
  });

  test('a mixed argument list captures the widget field too', () async {
    final built = await _build(
      _source(
        "() => widget.onPlan?.call(annualSelected ? 'annual' : 'monthly', "
        'widget.planId)',
        extraParams: ", this.onPlan, this.planId = 'spring'",
        extraFields:
            'final void Function(String plan, String id)? onPlan;\n'
            '  final String planId;',
      ),
    );
    _expectDesignOwnsState(built);
    expect(built.warnings, isEmpty);
    expect(
      built.rfwtxt,
      matches(RegExp(r'c2: data\.context\._h[0-9a-f]{10} \}')),
    );
  });

  for (final (name, field) in [
    (
      'a callback with an implicit result type',
      'final Function(String)? onPick;',
    ),
    (
      'a callback taking a record',
      'final void Function((String, int))? onPick;',
    ),
  ]) {
    test('$name falls back instead of failing the build', () async {
      final argument = field.contains('(String, int)')
          ? "(annualSelected ? 'annual' : 'monthly', 1)"
          : "annualSelected ? 'annual' : 'monthly'";
      final built = await _build(
        _source(
          '() => widget.onPick?.call($argument)',
          extraParams: ', this.onPick',
          extraFields: field,
        ),
      );
      expect(built.errors, isEmpty);
      expect(built.succeeded, isTrue);
      expect(built.rfwtxt, isNot(contains('set state.')));
      expect(
        built.warnings.single,
        allOf(
          contains('`widget.onPick` has the type'),
          contains('which a published design has no name for'),
          contains(
            field.contains('(String, int)')
                ? 'Try taking each value as its own parameter'
                : 'Try declaring its parameter and result types, as in '
                      '`final void Function(String plan)? onPick;`',
          ),
        ),
      );
    });
  }

  for (final (name, declaration, field, fix) in [
    (
      'an enum',
      'PlanKind plan = PlanKind.annual;',
      'final void Function(PlanKind plan)? onPick;',
      "Try declaring `plan` as a `String` that holds the value's name",
    ),
    (
      'a nullable bool',
      'bool? plan = true;',
      'final void Function(bool? plan)? onPick;',
      'Try declaring `plan` as a non-null `bool` with a starting value',
    ),
    (
      'a num',
      'num plan = 1;',
      'final void Function(num plan)? onPick;',
      'Try declaring `plan` as a `double` or an `int`',
    ),
  ]) {
    test(
      '$name State field passed to a callback says how to pass it',
      () async {
        final built = await _build(
          _source(
                '() => widget.onPick?.call(plan)',
                extraParams: ', this.onPick',
                extraFields: field,
                extraMembers: declaration,
              ) +
              'enum PlanKind { annual, monthly }\n',
        );
        expect(built.errors, isEmpty);
        expect(built.rfwtxt, isNot(contains('set state.')));
        expect(
          built.warnings.single,
          allOf(
            contains(
              'a value the design passes to a callback is a non-null '
              'bool, int, double or String',
            ),
            contains(fix),
          ),
        );
      },
    );
  }

  test('a loop item a callback reads says what the design can pass', () async {
    final built = await _build(
      _source(
        '() {}',
        extraParams: ", this.onPick, this.tiers = const ['pro']",
        extraFields:
            'final void Function(String id)? onPick;\n'
            '  final List<String> tiers;',
        extraChildren:
            'for (final tier in widget.tiers) GestureDetector('
            "onTap: () => widget.onPick?.call(annualSelected ? tier : ''), "
            'child: Text(tier)),',
      ),
    );
    expect(built.errors, isEmpty);
    expect(built.rfwtxt, isNot(contains('set state.')));
    expect(
      built.warnings.single,
      allOf(
        contains('the callback reads `tier`'),
        contains('Try passing only State fields, constants and widget fields'),
      ),
    );
  });

  test("Flutter's own State members don't keep State in the app", () async {
    final built = await _build(
      _source(
        "() => widget.onContinue?.call(annualSelected ? 'annual' : 'monthly')",
        extraMembers:
            'Widget _help() => GestureDetector('
            'onTap: () { if (!mounted) return; '
            'Navigator.of(context).maybePop(); }, '
            "child: const Text('Help'));",
        extraChildren: '_help(),',
      ),
    );
    expect(built.errors, isEmpty);
    expect(built.rfwtxt, contains(_toggles));
    expect(built.warnings, isEmpty);
  });

  test('a this. read in a build local keeps State in the app', () async {
    final built = await _build(
      _source(
            '() => widget.onContinue?.call(plan)',
          )
          .replaceFirst(
            '  @override\n  Widget build(BuildContext context) => Column(',
            '  @override\n  Widget build(BuildContext context) {\n'
                "    final plan = this.annualSelected ? 'annual' : 'monthly';\n"
                '    return Column(',
          )
          .replaceFirst('      ]);\n}', '      ]);\n  }\n}'),
    );
    expect(built.errors, isEmpty);
    expect(built.rfwtxt, isNot(contains('set state.')));
    expect(
      built.warnings.single,
      allOf(
        contains('runs in your app and reads `annualSelected`'),
        contains(
          "Try reading `annualSelected` in the callback's arguments "
          'rather than through a build local or helper',
        ),
      ),
    );
  });

  for (final (name, child) in [
    (
      'a value under a State condition',
      "Text(annualSelected ? widget.prices.annual() : widget.prices.monthly()),",
    ),
    (
      'a widget under a State collection-if',
      'if (annualSelected) Text(widget.prices.annual()) '
          'else Text(widget.prices.monthly()),',
    ),
  ]) {
    test('$name keeps State in the app and says why', () async {
      final built = await _build(
        _source(
              "() => widget.onContinue?.call(annualSelected ? 'annual' : 'monthly')",
              extraParams: ', this.prices = const Prices()',
              extraFields: 'final Prices prices;',
              extraChildren: child,
            ) +
            '''
class Prices {
  const Prices();
  String annual() => '39.99';
  String monthly() => '4.99';
}
''',
      );
      expect(built.errors, isEmpty);
      expect(built.rfwtxt, isNot(contains('set state.')));
      expect(
        built.warnings.single,
        allOf(
          contains('is computed by your app under `annualSelected`'),
          contains(
            'Try showing each value in its own widget and hiding the other '
            'one, as in `Offstage(offstage: !annualSelected, '
            'child: Text(annual))`',
          ),
        ),
      );
    });
  }

  test("a member inherited from Object doesn't keep State in the app", () async {
    final built = await _build(
      _source(
        "() => widget.onContinue?.call(annualSelected ? 'annual' : 'monthly')",
        extraChildren: 'Text(hashCode.toString()),',
      ),
    );
    expect(built.errors, isEmpty);
    expect(built.rfwtxt, contains('{ annualSelected: true }'));
    expect(built.rfwtxt, contains(_toggles));
    expect(built.warnings, isEmpty);
  });

  test(
    'a field written outside setState keeps State in the app and says why',
    () async {
      final built = await _build(
        _source(
          "() => widget.onContinue?.call(annualSelected ? 'annual' : 'monthly')",
          selectAnnual: 'annualSelected = true; setState(() {});',
        ),
      );
      expect(built.errors, isEmpty);
      expect(built.rfwtxt, contains('widget Paywall = '));
      expect(built.rfwtxt, isNot(contains('set state.')));
      expect(built.warnings, hasLength(1));
      expect(
        built.warnings.single,
        allOf(
          contains("`_PlanPickerState` stays in your app's code"),
          contains("in 'selectAnnual'"),
          contains('Try writing selectAnnual as one'),
        ),
      );
    },
  );

  test('Ascend with a plain close callback emits valid output', () async {
    // The example with only its close as a plain callback: its continue fires
    // a typed event that reads the plan State.
    final source =
        File(
              '../../apps/examples/lib/paywalls/ascend_premium.dart',
            )
            .readAsStringSync()
            .replaceFirst(
              "part 'restage.generated/ascend_premium.restage.g.dart';",
              "part 'restage.generated/entry.restage.g.dart';",
            )
            .replaceFirst(
              'class AscendPremiumPaywall extends StatefulWidget {',
              'class AscendPremiumPaywall extends StatefulWidget {\n'
                  '  static const continueFlow =\n'
                  "      SurfaceEvent<Map<String, Object?>>('continue');",
            )
            .replaceFirst(
              "() => widget.onContinue\n"
                  "                                  ?.call(annualSelected ? 'annual' : 'monthly')",
              'context.surfaceEvent(AscendPremiumPaywall.continueFlow, '
                  "{'term': annualSelected ? 'annual' : 'monthly'})",
            );
    expect(source, contains('onTap: widget.onClose'));
    expect(source, contains('AscendPremiumPaywall.continueFlow, '));
    expect(source, contains("part 'restage.generated/entry.restage.g.dart';"));
    final built = await _build(source);
    expect(built.errors, isEmpty);
    expect(built.rfwtxt, contains('set state.plansExpanded = true'));
    expect(
      built.rfwtxt,
      contains(
        'event "continue" {term: switch state.annualSelected '
        '{ true: "annual", false: "monthly" }}',
      ),
    );
  });

  test(
    'a double field seeded with an integer is captured as a double',
    () async {
      final built = await _build(
        _source(
          '() => widget.onPrice?.call(price)',
          extraParams: ', this.onPrice',
          extraFields: 'final void Function(double price)? onPrice;',
          extraMembers: 'double price = 0;',
        ),
      );
      expect(built.errors, isEmpty);
      expect(built.succeeded, isTrue);
      expect(built.rfwtxt, contains('price: 0.0'));
      expect(built.rfwtxt, contains('c1: state.price }'));
      expect(built.warnings, isEmpty);
    },
  );

  test('an int literal in a double argument is evaluated by the app', () async {
    final built = await _build(
      _source(
        '() => widget.onPrice?.call(annualSelected ? 1 : 2.5)',
        extraParams: ', this.onPrice',
        extraFields: 'final void Function(double price)? onPrice;',
      ),
    );
    _expectDesignOwnsState(built);
    expect(built.rfwtxt, contains('c1: state.annualSelected }'));
    expect(built.mount, contains('_restageInput1 ? 1 : 2.5'));
  });

  const appWidgets = '''
class Banner extends StatelessWidget {
  const Banner(this.text, {super.key, this.loud = false});
  final String text;
  final bool loud;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) => Text(loud ? text.toUpperCase() : text),
      );
}

class PlanScope extends InheritedWidget {
  const PlanScope({super.key, required this.annual, required super.child});
  final bool annual;
  @override
  bool updateShouldNotify(PlanScope old) => annual != old.annual;
}
''';

  test(
    'an app widget given a value computed from State keeps State in the app',
    () async {
      final built = await _build(
        _source(
              "() => widget.onContinue?.call(annualSelected ? 'annual' : 'monthly')",
              extraChildren:
                  "Banner(annualSelected ? 'Best value' : 'Flexible'),",
            ) +
            appWidgets,
      );
      expect(built.errors, isEmpty);
      expect(built.rfwtxt, contains('widget Paywall'));
      expect(built.rfwtxt, isNot(contains('set state.')));
      expect(
        built.warnings.single,
        allOf(
          contains("`_PlanPickerState` stays in your app's code"),
          contains(
            "`Banner(annualSelected ? 'Best value' : 'Flexible')` is a widget "
            'your app builds, and it reads `annualSelected`',
          ),
          contains('Try promoting it with `restage widget promote '),
        ),
      );
    },
  );

  test(
    'a wrapper the app keeps that reads State keeps State in the app',
    () async {
      final built = await _build(
        _source(
                  "() => widget.onContinue?.call(annualSelected ? 'annual' : 'monthly')",
                )
                .replaceFirst(
                  'Widget build(BuildContext context) => Column(',
                  'Widget build(BuildContext context) => '
                      'PlanScope(annual: annualSelected, child: Column(',
                )
                .replaceFirst(
                  '      ]);\n}',
                  '      ]));\n}',
                ) +
            appWidgets,
      );
      expect(built.errors, isEmpty);
      expect(built.rfwtxt, contains('widget Paywall'));
      expect(built.rfwtxt, isNot(contains('set state.')));
      expect(
        built.warnings.single,
        allOf(
          contains("`_PlanPickerState` stays in your app's code"),
          contains('wraps the design'),
          contains('`annualSelected`'),
        ),
      );
    },
  );

  test('a build local read by a callback keeps State in the app', () async {
    final built = await _build(
      _source('() => widget.onContinue?.call(plan)')
          .replaceFirst(
            '  @override\n  Widget build(BuildContext context) => Column(',
            '  @override\n  Widget build(BuildContext context) {\n'
                "    final plan = annualSelected ? 'annual' : 'monthly';\n"
                '    return Column(',
          )
          .replaceFirst('      ]);\n}', '      ]);\n  }\n}'),
    );
    expect(built.errors, isEmpty);
    expect(built.rfwtxt, isNot(contains('set state.')));
    expect(
      built.warnings.single,
      allOf(
        contains(
          '`() => widget.onContinue?.call(plan)` runs in your app and '
          'reads `annualSelected`',
        ),
        contains("Try reading `annualSelected` in the callback's arguments"),
      ),
    );
  });

  test('a handler a helper calls keeps State in the app', () async {
    final built = await _build(
      _source(
        "() => widget.onContinue?.call(annualSelected ? 'annual' : 'monthly')",
        extraMembers:
            'Widget _row(String label, VoidCallback onTap) => '
            'GestureDetector(onTap: () { debugPrint(label); onTap(); }, '
            'child: Text(label));',
        extraChildren: "_row('Later', selectMonthly),",
      ),
    );
    expect(built.errors, isEmpty);
    expect(built.rfwtxt, isNot(contains('set state.')));
    expect(
      built.warnings.single,
      allOf(
        contains('runs in your app and calls `selectMonthly`'),
        contains(
          'Try passing `selectMonthly` straight to the widget that '
          'fires it, as in `onTap: selectMonthly`',
        ),
      ),
    );
  });

  for (final (name, declaration, field, argument) in [
    (
      'an enum',
      "String plan = 'annual';",
      'final void Function(String plan)? onPick;',
      'plan',
    ),
    (
      'a nullable bool',
      'bool plan = true;',
      'final void Function(bool plan)? onPick;',
      'plan',
    ),
    (
      'a num',
      'double plan = 1;',
      'final void Function(double plan)? onPick;',
      'plan',
    ),
  ]) {
    test(
      '$name State field passed as the advice says keeps the design state',
      () async {
        final built = await _build(
          _source(
                '() => widget.onPick?.call($argument)',
                extraParams: ', this.onPick',
                extraFields: field,
                extraMembers: declaration,
              ) +
              'enum PlanKind { annual, monthly }\n',
        );
        expect(built.errors, isEmpty);
        expect(built.warnings, isEmpty);
        expect(built.rfwtxt, contains(_toggles));
      },
    );
  }

  test(
    'a held build local that calls app code keeps State in the app',
    () async {
      final built = await _build(
        _source(
                  '() => widget.onBuy?.call(sku)',
                  extraParams: ', this.onBuy, this.store = const Store()',
                  extraFields:
                      'final void Function(String sku)? onBuy;\n'
                      '  final Store store;',
                )
                .replaceFirst(
                  '  @override\n  Widget build(BuildContext context) => Column(',
                  '  @override\n  Widget build(BuildContext context) {\n'
                      '    final sku = widget.store.skuFor(annualSelected);\n'
                      '    return Column(',
                )
                .replaceFirst('      ]);\n}', '      ]);\n  }\n}') +
            '''
class Store {
  const Store();
  String skuFor(bool annual) => annual ? 'pro.annual' : 'pro.monthly';
}
''',
      );
      expect(built.errors, isEmpty);
      expect(built.rfwtxt, isNot(contains('set state.')));
      expect(
        built.warnings.single,
        contains(
          '`() => widget.onBuy?.call(sku)` runs in your app and reads '
          '`annualSelected`',
        ),
      );
    },
  );

  test(
    'a State method called on this keeps the design state like a helper',
    () async {
      final built = await _build(
        _source(
          "() => widget.onContinue?.call(annualSelected ? 'annual' : 'monthly')",
          extraMembers: "String label() => annualSelected ? 'A' : 'M';",
          extraChildren: 'Text(this.label()),',
        ),
      );
      expect(built.errors, isEmpty);
      expect(built.warnings, isEmpty);
      expect(built.rfwtxt, contains(_toggles));
    },
  );

  test('a value computed in a build local, as the advice says, builds', () async {
    final built = await _build(
      _source(
            "() => widget.onContinue?.call(annualSelected ? 'annual' : 'monthly')",
            extraChildren: 'Text(label),',
          )
          .replaceFirst(
            '  @override\n  Widget build(BuildContext context) => Column(',
            '  @override\n  Widget build(BuildContext context) {\n'
                "    final label = annualSelected ? 'A' : 'M';\n"
                '    return Column(',
          )
          .replaceFirst('      ]);\n}', '      ]);\n  }\n}'),
    );
    expect(built.errors, isEmpty);
    expect(built.warnings, isEmpty);
    expect(built.rfwtxt, contains(_toggles));
  });

  test('a handler that calls this.setState lowers like setState', () async {
    final built = await _build(
      _source(
        "() => widget.onContinue?.call(annualSelected ? 'annual' : 'monthly')",
        selectAnnual: 'this.setState(() => annualSelected = true);',
      ),
    );
    expect(built.errors, isEmpty);
    expect(built.warnings, isEmpty);
    expect(built.rfwtxt, contains(_toggles));
  });

  for (final (name, build) in [
    (
      'a build that switches on State',
      'switch (annualSelected) { '
          "true => GestureDetector(onTap: selectMonthly, child: const Text('Annual')), "
          "false => GestureDetector(onTap: selectAnnual, child: const Text('Monthly')) }",
    ),
    (
      'a build whose switch guard reads State',
      "switch (widget.tier) { 'pro' when annualSelected => Column(children: ["
          "GestureDetector(onTap: selectMonthly, child: const Text('Monthly')), "
          'Text(widget.prices.annual())]), '
          "_ => Column(children: [GestureDetector(onTap: selectAnnual, child: const Text('Annual')), "
          'Text(widget.prices.monthly())]) }',
    ),
  ]) {
    test('$name keeps State in the app', () async {
      final source =
          _source(
            "() => widget.onContinue?.call(annualSelected ? 'annual' : 'monthly')",
            extraParams: ", this.prices = const Prices(), this.tier = 'pro'",
            extraFields: 'final Prices prices;\n  final String tier;',
          ) +
          '''
class Prices {
  const Prices();
  String annual() => '39.99';
  String monthly() => '4.99';
}
''';
      final start = source.indexOf('  @override\n  Widget build(');
      final built = await _build(
        '${source.substring(0, start)}  @override\n'
        '  Widget build(BuildContext context) => $build;\n}\n'
        '${source.substring(source.indexOf('class Prices'))}',
      );
      expect(built.errors, isEmpty);
      expect(built.rfwtxt, isNot(contains('set state.')));
      expect(
        built.warnings.single,
        allOf(
          contains('`PlanPicker.build` picks the widget it returns with '),
          contains(
            'Try choosing between the widgets with a conditional '
            'expression',
          ),
        ),
      );
    });
  }

  test('this passed to a function keeps State in the app', () async {
    final built = await _build(
      _source(
            "() => widget.onContinue?.call(annualSelected ? 'annual' : 'monthly')",
            extraChildren: 'Text(describe(this)),',
          ) +
          'String describe(State<PlanPicker> state) => state.toString();\n',
    );
    expect(built.errors, isEmpty);
    expect(built.rfwtxt, isNot(contains('set state.')));
    expect(
      built.warnings.single,
      allOf(
        contains("`_PlanPickerState` stays in"),
        contains('uses `this`, the State the design keeps'),
        contains('Try passing the State fields it needs instead of the State'),
      ),
    );
  });

  test('values shown in both branches keep the design state', () async {
    final built = await _build(
      _source(
            "() => widget.onContinue?.call(annualSelected ? 'annual' : 'monthly')",
            extraParams: ', this.prices = const Prices()',
            extraFields: 'final Prices prices;',
            extraChildren:
                'Offstage(offstage: !annualSelected, '
                'child: Text(widget.prices.annual())), '
                'Offstage(offstage: annualSelected, '
                'child: Text(widget.prices.monthly())),',
          ) +
          '''
class Prices {
  const Prices();
  String annual() => '39.99';
  String monthly() => '4.99';
}
''',
    );
    expect(built.errors, isEmpty);
    expect(built.warnings, isEmpty);
    expect(built.rfwtxt, contains(_toggles));
  });

  test(
    'a State field the design keeps but app code reshapes says so',
    () async {
      final built = await _build(
        _source(
              '() => widget.onPick?.call(plan.name)',
              extraParams: ', this.onPick',
              extraFields: 'final void Function(String plan)? onPick;',
              extraMembers: 'PlanKind plan = PlanKind.annual;',
            ) +
            'enum PlanKind { annual, monthly }\n',
      );
      expect(built.errors, isEmpty);
      expect(
        built.warnings.single,
        allOf(
          contains('the callback works out `plan.name` from `plan`'),
          contains(
            "Try declaring `plan` as a `String` that holds the value's name",
          ),
        ),
      );
    },
  );

  test('an app widget given a handler is told to promote it', () async {
    final built = await _build(
      _source(
            "() => widget.onContinue?.call(annualSelected ? 'annual' : 'monthly')",
            extraChildren: 'Toggle(onChanged: selectMonthly),',
          ) +
          '''
class Toggle extends StatelessWidget {
  const Toggle({super.key, required this.onChanged});
  final VoidCallback onChanged;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) =>
            GestureDetector(onTap: onChanged, child: const Text('Toggle')),
      );
}
''',
    );
    expect(built.errors, isEmpty);
    expect(
      built.warnings.single,
      allOf(
        contains('is a widget your app builds'),
        contains('Try promoting it with `restage widget promote'),
      ),
    );
  });

  test('a held local after another statement keeps State in the app', () async {
    final built = await _build(
      _source(
                '() => widget.onBuy?.call(sku)',
                extraParams: ', this.onBuy, this.store = const Store()',
                extraFields:
                    'final void Function(String sku)? onBuy;\n'
                    '  final Store store;',
              )
              .replaceFirst(
                '  @override\n  Widget build(BuildContext context) => Column(',
                '  @override\n  Widget build(BuildContext context) {\n'
                    "    debugPrint('plans');\n"
                    '    final sku = widget.store.skuFor(annualSelected);\n'
                    '    return Column(',
              )
              .replaceFirst('      ]);\n}', '      ]);\n  }\n}') +
          '''
class Store {
  const Store();
  String skuFor(bool annual) => annual ? 'pro.annual' : 'pro.monthly';
}
''',
    );
    expect(built.errors, isEmpty);
    // A build with statements keeps its State in the app, so the design
    // can't send a stale product.
    expect(built.rfwtxt, isNot(contains('set state.')));
    expect(built.rfwtxt, isNot(contains('annualSelected')));
  });

  test('a torn-off callback method is told to call back inline', () async {
    final built = await _build(
      _source(
        '_onContinue',
        extraMembers:
            'void _onContinue() => '
            "widget.onContinue?.call(annualSelected ? 'annual' : 'monthly');",
      ),
    );
    expect(built.errors, isEmpty);
    expect(built.rfwtxt, isNot(contains('set state.')));
    expect(
      built.warnings.single,
      allOf(
        contains("the build passes '_onContinue', a method of the State"),
        contains('Try writing the call inline as a closure'),
        isNot(contains('setState(() => field = value)')),
        isNot(contains('build local')),
      ),
    );
  });

  for (final (name, build, expected) in [
    (
      'a conditional between widgets, as the advice says,',
      "annualSelected ? GestureDetector(onTap: selectMonthly, child: const Text('Annual')) "
          ": GestureDetector(onTap: selectAnnual, child: const Text('Monthly'))",
      'set state.annualSelected = false',
    ),
    (
      'a switch on a widget field',
      "switch (widget.tier) { 'pro' => GestureDetector(onTap: selectMonthly, "
          "child: Text(annualSelected ? 'Annual' : 'Monthly')), "
          "_ => GestureDetector(onTap: selectAnnual, child: const Text('Basic')) }",
      'set state.annualSelected = false',
    ),
  ]) {
    test('$name at the root keeps the design state', () async {
      final source = _source(
        "() => widget.onContinue?.call(annualSelected ? 'annual' : 'monthly')",
        extraParams: ", this.tier = 'pro'",
        extraFields: 'final String tier;',
      );
      final start = source.indexOf('  @override\n  Widget build(');
      final built = await _build(
        '${source.substring(0, start)}  @override\n'
        '  Widget build(BuildContext context) => $build;\n}\n',
      );
      expect(built.errors, isEmpty);
      expect(built.warnings, isEmpty);
      expect(built.rfwtxt, contains('{ annualSelected: true }'));
      expect(built.rfwtxt, contains(expected));
    });
  }

  test('a torn-off async callback is told to call back inline', () async {
    final built = await _build(
      '${_source('_purchase', extraMembers: 'Future<void> _purchase() async { '
          "widget.onContinue?.call(annualSelected ? 'annual' : 'monthly'); }")}'
      '''
void configureApp() {
  rs.Restage.configure(apiKey: 'rs_pk_test', measurementEnabled: false);
}
''',
    );
    expect(
      built.warnings.single,
      allOf(
        contains("the build passes '_purchase', a method of the State"),
        contains('Try writing the call inline as a closure'),
        isNot(contains('build local')),
      ),
    );
  });

  // A handler's return type never decides measurement: Flutter discards it
  // on a void slot.
  const call = "widget.onContinue?.call(annualSelected ? 'annual' : 'monthly')";
  const tap = 'measurement: event "__restage_measurement_tap_v1" {}';
  const buy = ', child: Text(text: "Buy"))';
  for (final (name, method, library, child, (before, after)) in [
    (
      'an async method on a VoidCallback slot',
      'Future<void> _purchase() async { $call; }',
      'widgets',
      "GestureDetector(onTap: _purchase, child: const Text('Buy')),",
      ('GestureDetector(onTap: ', buy),
    ),
    (
      'an async arrow method on a VoidCallback slot',
      'Future<void> _purchase() async => $call;',
      'widgets',
      "GestureDetector(onTap: _purchase, child: const Text('Buy')),",
      ('GestureDetector(onTap: ', buy),
    ),
    (
      'a value-returning method on a VoidCallback slot',
      'bool _purchase() { $call; return true; }',
      'widgets',
      "GestureDetector(onTap: _purchase, child: const Text('Buy')),",
      ('GestureDetector(onTap: ', buy),
    ),
    (
      'an async method on a button',
      'Future<void> _purchase() async { $call; }',
      'material',
      "TextButton(onPressed: _purchase, child: const Text('Buy')),",
      ('TextButton(onPressed: ', buy),
    ),
    (
      'an async method on a ValueChanged slot',
      'Future<void> _purchase(bool annual) async '
          '{ widget.onChoose?.call(annual); }',
      'material',
      'Switch(value: annualSelected, onChanged: _purchase),',
      ('onChanged: ', ')'),
    ),
    (
      'an awaiting async method on a VoidCallback slot',
      'Future<void> _purchase() async '
          '{ await Future<void>.value(); $call; }',
      'widgets',
      "GestureDetector(onTap: _purchase, child: const Text('Buy')),",
      ('GestureDetector(onTap: ', buy),
    ),
    (
      'an async method on a span recognizer',
      'Future<void> _purchase() async { $call; }',
      'widgets',
      "Text.rich(TextSpan(text: 'Buy', "
          'recognizer: TapGestureRecognizer()..onTap = _purchase)),',
      ('recognizer: { kind: "tap", onTap: ', ' }'),
    ),
    (
      'a sync* setState method, which never runs, on a VoidCallback slot',
      'Iterable<void> _purchase() sync* '
          '{ setState(() => annualSelected = false); }',
      'widgets',
      "GestureDetector(onTap: _purchase, child: const Text('Buy')),",
      ('GestureDetector(onTap: ', buy),
    ),
    (
      'an async method forwarded through an app widget',
      'Future<void> _purchase() async { $call; }',
      'widgets',
      'BuyButton(onPressed: _purchase),',
      ('BuyButton(onPressed: ', ')'),
    ),
  ]) {
    test('$name is measured', () async {
      final built = await _build(
        _source(
              'null',
              extraMembers: method,
              library: library,
              extraChildren: child,
            ).replaceFirst(
              "import 'package:restage/restage.dart' as rs;",
              "import 'package:flutter/gestures.dart';\n"
                  "import 'package:restage/restage.dart' as rs;",
            ) +
            _buyButton,
      );
      expect(built.errors, isEmpty);
      expect(built.succeeded, isTrue);
      final handler = RegExp(
        '${RegExp.escape(before)}'
        r'\{nativeEvent: data\.context\.(_h[0-9a-f]{10}), '
        '${RegExp.escape(tap)}\\}${RegExp.escape(after)}',
      ).firstMatch(built.rfwtxt);
      expect(handler, isNotNull, reason: built.rfwtxt);
      expect(built.mount, contains("'${handler!.group(1)}': '_purchase'"));
    });
  }

  test('an async closure without await lowers like a sync one', () async {
    final built = await _build(_source('() async { $call; }'));
    _expectDesignOwnsState(built);
    final action = _program.firstMatch(built.rfwtxt);
    expect(action, isNotNull, reason: built.rfwtxt);
    expect(
      action!.group(1),
      'switch state.annualSelected { true: "annual", false: "monthly" }',
    );
    expect(built.warnings, isEmpty);
  });

  test(
    'an async setState handler without await keeps the design state',
    () async {
      const body = '{ setState(() => annualSelected = false); }';
      final built = await _build(
        _source('_pick', extraMembers: 'Future<void> _pick() async $body'),
      );
      final sync = await _build(
        _source('_pick', extraMembers: 'void _pick() $body'),
      );
      _expectDesignOwnsState(built, recorded: false);
      expect(built.rfwtxt, sync.rfwtxt);
      expect(
        built.rfwtxt,
        contains(
          'GestureDetector(onTap: [set state.annualSelected = false, '
          'event "__restage_measurement_tap_v1" {}], '
          'child: Text(text: "Continue"))',
        ),
      );
    },
  );

  test(
    'an awaiting closure runs in the app and is measured',
    () async {
      final built = await _build(
        _source('() async { await Future<void>.value(); $call; }'),
      );
      expect(built.errors, isEmpty);
      expect(built.succeeded, isTrue);
      expect(
        built.rfwtxt,
        matches(
          RegExp(
            r'GestureDetector\(onTap: \{nativeEvent: '
            r'data\.context\._h[0-9a-f]{10}, '
            '${RegExp.escape(tap)}\\}, child: Text\\(text: "Continue"\\)\\)',
          ),
        ),
      );
      expect(built.warnings.single, contains('runs in your app'));
    },
  );

  // A generator body runs only when its result is iterated, so a tap never
  // runs it; the app's own closure is bound, as Flutter would call it.
  for (final keyword in ['sync*', 'async*']) {
    for (final (what, body) in [
      ('callback', call),
      ('setState', 'setState(() => annualSelected = false)'),
    ]) {
      test('a $keyword $what closure stays in the app', () async {
        final built = await _build(_source('() $keyword { $body; }'));
        expect(built.errors, isEmpty);
        expect(built.succeeded, isTrue);
        expect(_program.hasMatch(built.rfwtxt), isFalse, reason: built.rfwtxt);
        expect(built.rfwtxt, isNot(contains('native.call')));
        expect(
          built.rfwtxt,
          matches(
            RegExp(
              r'GestureDetector\(onTap: \{nativeEvent: '
              r'data\.context\._h[0-9a-f]{10}, '
              '${RegExp.escape(tap)}\\}, child: Text\\(text: "Continue"\\)\\)',
            ),
          ),
        );
      });
    }
  }

  test('a sync* value callback stays in the app', () async {
    final built = await _build(
      _source(
        'null',
        library: 'material',
        extraChildren:
            'Switch(value: annualSelected, '
            'onChanged: (v) sync* { setState(() => annualSelected = v); }),',
      ),
    );
    expect(built.errors, isEmpty);
    expect(built.succeeded, isTrue);
    expect(
      built.rfwtxt,
      matches(
        RegExp(
          r'onChanged: \{nativeEvent: data\.context\._h[0-9a-f]{10}, '
          '${RegExp.escape(tap)}\\}',
        ),
      ),
    );
    expect(built.rfwtxt, isNot(contains('set state.annualSelected = v')));
  });
}
