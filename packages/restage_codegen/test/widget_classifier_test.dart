import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/paywall_helpers.dart';
import 'package:restage_codegen/src/widget_classification.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Catalog entries for the stub `Container` / `Text` widgets the fixtures
/// declare — `flutterType` matches the `<library URI>#<Class>` the classifier
/// computes for a composed widget, so they read as catalog composition.
Catalog _stubCatalog({String file = 'card.dart'}) => catalogWith([
      entry(
        name: 'Container',
        properties: [prop('child', PropertyType.widget)],
        flutterType: 'package:apps_examples/$file#Container',
      ),
      entry(
        name: 'Text',
        properties: [prop('text', PropertyType.string, positional: true)],
        flutterType: 'package:apps_examples/$file#Text',
      ),
    ]);

void main() {
  group('WidgetClassifier — pure composition', () {
    test(
        'a pure-composition StatelessWidget is ComposableWidget with no '
        'mechanisms', () async {
      final result = await classifyFixture(
        {
          'lib/card.dart': '''
$kClassifierStubs

class Container extends StatelessWidget {
  const Container({this.child});
  final Widget? child;
  Widget build(BuildContext context) => const Widget();
}

class Text extends StatelessWidget {
  const Text(this.data);
  final String? data;
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(
  name: 'AcmeCard',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'card',
)
class AcmeCard extends StatelessWidget {
  const AcmeCard({this.label});
  final String? label;
  Widget build(BuildContext context) => Container(child: Text(label));
}
''',
        },
        inputPath: 'lib/card.dart',
        widgetName: 'AcmeCard',
        catalog: _stubCatalog(),
      );

      expect(result, isA<ComposableWidget>());
      final composable = result as ComposableWidget;
      expect(composable.requiredMechanisms, isEmpty);
      expect(composable.composedCustomWidgets, isEmpty);
      expect(composable.classKey, 'package:apps_examples/card.dart#AcmeCard');
    });
  });

  group('WidgetClassifier — imperative', () {
    test('a CustomPaint in build() is ImperativeWidget / customPainter',
        () async {
      final result = await classifyFixture(
        {
          'lib/chart.dart': '''
$kClassifierStubs

class CustomPainter { const CustomPainter(); }

class CustomPaint extends StatelessWidget {
  const CustomPaint({this.painter});
  final CustomPainter? painter;
  Widget build(BuildContext context) => const Widget();
}

class ChartPainter extends CustomPainter {
  const ChartPainter();
}

@RestageWidget(
  name: 'AcmeChart',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.display,
  description: 'chart',
)
class AcmeChart extends StatelessWidget {
  const AcmeChart();
  Widget build(BuildContext context) =>
      CustomPaint(painter: ChartPainter());
}
''',
        },
        inputPath: 'lib/chart.dart',
        widgetName: 'AcmeChart',
      );

      expect(result, isA<ImperativeWidget>());
      final blocker = (result as ImperativeWidget).blockers.first;
      expect(blocker.kind, BlockerKind.customPainter);
      expect(blocker.detail, contains('CustomPaint'));
      expect(
        blocker.location,
        startsWith('package:apps_examples/chart.dart#AcmeChart@'),
      );
    });

    test('a call into a Dart package is ImperativeWidget / dartCall', () async {
      final result = await classifyFixture(
        {
          'lib/price.dart': '''
$kClassifierStubs

class Container extends StatelessWidget {
  const Container({this.child});
  final Widget? child;
  Widget build(BuildContext context) => const Widget();
}

class Text extends StatelessWidget {
  const Text(this.data);
  final String? data;
  Widget build(BuildContext context) => const Widget();
}

class NumberFormat {
  NumberFormat.currency();
  String format(num? value) => '';
}

@RestageWidget(
  name: 'PriceLabel',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.display,
  description: 'price',
)
class PriceLabel extends StatelessWidget {
  const PriceLabel({this.amount});
  final num? amount;
  Widget build(BuildContext context) =>
      Text(NumberFormat.currency().format(amount));
}
''',
        },
        inputPath: 'lib/price.dart',
        widgetName: 'PriceLabel',
        catalog: _stubCatalog(file: 'price.dart'),
      );

      expect(result, isA<ImperativeWidget>());
      final blocker = (result as ImperativeWidget).blockers.first;
      expect(blocker.kind, BlockerKind.dartCall);
      expect(blocker.detail, contains('format'));
      // The stub `NumberFormat` resolves to the fixture library, not
      // `package:intl/` — the element gate withholds the formatting
      // adopt-target (the look-alike defense), so the detail is the generic
      // truncated source, never the intl-specific catalog widget.
      expect(blocker.detail, isNot(contains('RestagePrice')));
    });

    test(
        'a real intl NumberFormat.format() names the catalog adopt-target on '
        'its dartCall deferral', () async {
      final result = await classifyFixture(
        {
          'lib/price.dart': '''
import 'package:intl/intl.dart';
$kClassifierStubs

class Text extends StatelessWidget {
  const Text(this.data);
  final String? data;
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(
  name: 'PriceLabel',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.display,
  description: 'price',
)
class PriceLabel extends StatelessWidget {
  const PriceLabel({this.amount});
  final num? amount;
  Widget build(BuildContext context) =>
      Text(NumberFormat.currency(locale: 'en_US', symbol: 'USD').format(amount));
}
''',
        },
        inputPath: 'lib/price.dart',
        widgetName: 'PriceLabel',
        catalog: _stubCatalog(file: 'price.dart'),
      );

      expect(result, isA<ImperativeWidget>());
      final blocker = (result as ImperativeWidget).blockers.first;
      expect(blocker.kind, BlockerKind.dartCall);
      // The same single-sourced adopt-target the direct-paywall translator
      // names — reducible deferral, pointed at the catalog widget.
      expect(blocker.detail, contains('RestagePrice'));
    });
  });

  group('WidgetClassifier — mechanisms', () {
    test('a Theme.of(context) read marks the themeAsData mechanism', () async {
      // Uses real `package:flutter/material.dart` `Theme` — the strict
      // recognizer rejects a stub `class Theme` because its resolved
      // library URI is not `package:flutter/`. A local `Box` widget plays
      // the catalog-widget role so the test stays decoupled from Flutter's
      // internal `Container` library path.
      final result = await classifyFixture(
        {
          'lib/banner.dart': '''
$kFlutterClassifierStubs

class Box extends StatelessWidget {
  const Box({this.color, super.key});
  final Color? color;
  @override
  Widget build(BuildContext context) => const SizedBox();
}

@RestageWidget(
  name: 'AcmeBanner',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'banner',
)
class AcmeBanner extends StatelessWidget {
  const AcmeBanner({super.key});
  @override
  Widget build(BuildContext context) =>
      Box(color: Theme.of(context).colorScheme.primary);
}
''',
        },
        inputPath: 'lib/banner.dart',
        widgetName: 'AcmeBanner',
        catalog: catalogWith([
          entry(
            name: 'Box',
            properties: const [],
            flutterType: 'package:apps_examples/banner.dart#Box',
          ),
        ]),
      );

      expect(result, isA<ComposableWidget>());
      expect(
        (result as ComposableWidget).requiredMechanisms,
        contains(InliningMechanism.themeAsData),
      );
    });

    test('a structured value with literal args is plain composition', () async {
      final result = await classifyFixture(
        _mechanismsFixture,
        inputPath: 'lib/mechanisms.dart',
        widgetName: 'AcmePanel',
        catalog: _mechanismsCatalog,
      );
      expect(result, isA<ComposableWidget>());
      expect((result as ComposableWidget).requiredMechanisms, isEmpty);
    });

    test('a const reference marks the constantFolding mechanism', () async {
      final result = await classifyFixture(
        _mechanismsFixture,
        inputPath: 'lib/mechanisms.dart',
        widgetName: 'AcmeGap',
        catalog: _mechanismsCatalog,
      );
      expect(result, isA<ComposableWidget>());
      expect(
        (result as ComposableWidget).requiredMechanisms,
        contains(InliningMechanism.constantFolding),
      );
    });

    test(
        'compute over a runtime field is ImperativeWidget / '
        'runtimeComputedValue', () async {
      final result = await classifyFixture(
        _mechanismsFixture,
        inputPath: 'lib/mechanisms.dart',
        widgetName: 'AcmeBox',
        catalog: _mechanismsCatalog,
      );
      expect(result, isA<ImperativeWidget>());
      expect(
        (result as ImperativeWidget).blockers.first.kind,
        BlockerKind.runtimeComputedValue,
      );
    });
  });

  group('WidgetClassifier — declarative state', () {
    test('a StatefulWidget with simple state marks declarativeState', () async {
      final result = await classifyFixture(
        {
          'lib/toggle.dart': '''
$kClassifierStubs

class GestureDetector extends StatelessWidget {
  const GestureDetector({this.onTap, this.child});
  final void Function()? onTap;
  final Widget? child;
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(
  name: 'AcmeToggle',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.input,
  description: 'toggle',
)
class AcmeToggle extends StatefulWidget {
  const AcmeToggle({this.onChild, this.offChild});
  final Widget? onChild;
  final Widget? offChild;
  _AcmeToggleState createState() => _AcmeToggleState();
}

class _AcmeToggleState extends State<AcmeToggle> {
  bool on = false;
  void toggle() => setState(() => on = !on);
  Widget build(BuildContext context) => GestureDetector(
        onTap: toggle,
        child: on ? widget.onChild : widget.offChild,
      );
}
''',
        },
        inputPath: 'lib/toggle.dart',
        widgetName: 'AcmeToggle',
        catalog: catalogWith([
          entry(
            name: 'GestureDetector',
            properties: const [],
            flutterType: 'package:apps_examples/toggle.dart#GestureDetector',
          ),
        ]),
      );

      expect(result, isA<ComposableWidget>());
      expect(
        (result as ComposableWidget).requiredMechanisms,
        contains(InliningMechanism.declarativeState),
      );
    });

    test('a non-primitive State field is ImperativeWidget / nonSimpleState',
        () async {
      final result = await classifyFixture(
        {
          'lib/spinner.dart': '''
$kClassifierStubs

class AnimationController { const AnimationController(); }

class Container extends StatelessWidget {
  const Container();
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(
  name: 'AcmeSpinner',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.display,
  description: 'spinner',
)
class AcmeSpinner extends StatefulWidget {
  const AcmeSpinner();
  _AcmeSpinnerState createState() => _AcmeSpinnerState();
}

class _AcmeSpinnerState extends State<AcmeSpinner> {
  AnimationController controller = const AnimationController();
  Widget build(BuildContext context) => Container();
}
''',
        },
        inputPath: 'lib/spinner.dart',
        widgetName: 'AcmeSpinner',
        catalog: catalogWith([
          entry(
            name: 'Container',
            properties: const [],
            flutterType: 'package:apps_examples/spinner.dart#Container',
          ),
        ]),
      );

      expect(result, isA<ImperativeWidget>());
      expect(
        (result as ImperativeWidget).blockers.first.kind,
        BlockerKind.nonSimpleState,
      );
    });

    test('a State lifecycle method is ImperativeWidget / asyncOrLifecycle',
        () async {
      final result = await classifyFixture(
        {
          'lib/fader.dart': '''
$kClassifierStubs

class Container extends StatelessWidget {
  const Container();
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(
  name: 'AcmeFader',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.display,
  description: 'fader',
)
class AcmeFader extends StatefulWidget {
  const AcmeFader();
  _AcmeFaderState createState() => _AcmeFaderState();
}

class _AcmeFaderState extends State<AcmeFader> {
  void initState() {}
  Widget build(BuildContext context) => Container();
}
''',
        },
        inputPath: 'lib/fader.dart',
        widgetName: 'AcmeFader',
        catalog: catalogWith([
          entry(
            name: 'Container',
            properties: const [],
            flutterType: 'package:apps_examples/fader.dart#Container',
          ),
        ]),
      );

      expect(result, isA<ImperativeWidget>());
      expect(
        (result as ImperativeWidget).blockers.first.kind,
        BlockerKind.asyncOrLifecycle,
      );
    });

    test(
        'a motion State (Flutter AnimationController + lifecycle) NAMES the '
        'motion adopt-targets in BOTH its lifecycle and field deferrals',
        () async {
      // Real `package:flutter/` resolution: the State holds an
      // `AnimationController` field (the motion signal) and a `dispose()`
      // lifecycle method. classifyStateShape adds the lifecycle blocker BEFORE
      // the field blocker, and the diagnostic surfaces the first dead-end
      // blocker — so the lifecycle blocker (which surfaces) MUST carry the
      // motion hint, not just the field blocker.
      final result = await classifyFixture(
        {
          'lib/spring.dart': '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

@RestageWidget(
  name: 'AcmeSpring',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.display,
  description: 'spring entrance',
)
class AcmeSpring extends StatefulWidget {
  const AcmeSpring({super.key});
  _AcmeSpringState createState() => _AcmeSpringState();
}

class _AcmeSpringState extends State<AcmeSpring>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget build(BuildContext context) => const SizedBox();
}
''',
        },
        inputPath: 'lib/spring.dart',
        widgetName: 'AcmeSpring',
      );

      expect(result, isA<ImperativeWidget>());
      final imp = result as ImperativeWidget;
      // The surfaced diagnostic uses the first dead-end blocker (the lifecycle
      // method here) — it must carry the motion adopt-targets.
      final surfaced = imp.blockers.firstWhere(
        (b) => b.disposition == CustomWidgetDisposition.deadEnd,
      );
      expect(surfaced.kind, BlockerKind.asyncOrLifecycle);
      for (final widget in const [
        'RestageMotion',
        'RestageFadeIn',
        'RestagePulse',
        'RestageStagger',
      ]) {
        expect(surfaced.detail, contains(widget));
      }
      // The non-primitive field blocker is tagged too (for a field-only State).
      final field =
          imp.blockers.firstWhere((b) => b.kind == BlockerKind.nonSimpleState);
      expect(field.detail, contains('RestageMotion'));
      // The aggregation subject stays the member name (the idiom histogram
      // keys on it) — unchanged by the detail enrichment.
      expect(field.idiomSubject, '_c');
      expect(surfaced.idiomSubject, 'dispose');
    });

    test(
        'a customer look-alike AnimationController State does NOT name the '
        'motion widgets (element gate)', () async {
      // A customer class merely named `AnimationController` is not Flutter
      // animation — the motion hint is withheld (the look-alike discipline).
      final result = await classifyFixture(
        {
          'lib/fake.dart': '''
$kClassifierStubs

class AnimationController { const AnimationController(); }

@RestageWidget(
  name: 'AcmeFake',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.display,
  description: 'fake',
)
class AcmeFake extends StatefulWidget {
  const AcmeFake();
  _AcmeFakeState createState() => _AcmeFakeState();
}

class _AcmeFakeState extends State<AcmeFake> {
  AnimationController controller = const AnimationController();
  void dispose() {}
  Widget build(BuildContext context) => const Widget();
}
''',
        },
        inputPath: 'lib/fake.dart',
        widgetName: 'AcmeFake',
      );

      expect(result, isA<ImperativeWidget>());
      final imp = result as ImperativeWidget;
      for (final blocker in imp.blockers) {
        expect(blocker.detail, isNot(contains('Restage')));
      }
    });

    test(
        'a directly-constructed Flutter spring in build() NAMES RestageMotion '
        'in the unclassifiable reason', () async {
      // The spring look-alike path: a `SpringSimulation` / `SpringDescription`
      // construction reaching the classifier's `_construction` walk names the
      // catalog spring widget. (The dominant motion path is the
      // controller-field case above; a spring built in build() is rare, but
      // the recognizer is wired so the helper is live in production.)
      final result = await classifyFixture(
        {
          'lib/springbuild.dart': '''
import 'package:flutter/physics.dart';
$kClassifierStubs

@RestageWidget(
  name: 'AcmeSpringBuild',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.display,
  description: 'spring in build',
)
class AcmeSpringBuild extends StatelessWidget {
  const AcmeSpringBuild();
  Object build(BuildContext context) =>
      SpringSimulation(SpringDescription(mass: 1, stiffness: 100, damping: 10),
          0, 1, 0);
}
''',
        },
        inputPath: 'lib/springbuild.dart',
        widgetName: 'AcmeSpringBuild',
      );

      expect(result, isA<UnclassifiableWidget>());
      expect(
        (result as UnclassifiableWidget).reason,
        contains('RestageMotion'),
      );
    });

    test(
        'a customer look-alike spring construction does NOT name RestageMotion '
        '(element gate)', () async {
      final result = await classifyFixture(
        {
          'lib/fakespring.dart': '''
$kClassifierStubs

class SpringDescription {
  const SpringDescription({double? mass, double? stiffness, double? damping});
}

@RestageWidget(
  name: 'AcmeFakeSpring',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.display,
  description: 'fake spring',
)
class AcmeFakeSpring extends StatelessWidget {
  const AcmeFakeSpring();
  Object build(BuildContext context) =>
      const SpringDescription(mass: 1, stiffness: 100, damping: 10);
}
''',
        },
        inputPath: 'lib/fakespring.dart',
        widgetName: 'AcmeFakeSpring',
      );

      expect(result, isA<UnclassifiableWidget>());
      expect(
        (result as UnclassifiableWidget).reason,
        isNot(contains('Restage')),
      );
    });

    test(
        'a lifecycle method in a NON-motion State stays generic (no motion '
        'signal)', () async {
      // A lifecycle method with no animation-controller field is NOT motion
      // (it could be analytics / a stream / a focus node) — no motion hint.
      final result = await classifyFixture(
        {
          'lib/plain.dart': '''
$kClassifierStubs

@RestageWidget(
  name: 'AcmePlain',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.display,
  description: 'plain',
)
class AcmePlain extends StatefulWidget {
  const AcmePlain();
  _AcmePlainState createState() => _AcmePlainState();
}

class _AcmePlainState extends State<AcmePlain> {
  bool annual = false;
  void initState() {}
  Widget build(BuildContext context) => const Widget();
}
''',
        },
        inputPath: 'lib/plain.dart',
        widgetName: 'AcmePlain',
      );

      expect(result, isA<ImperativeWidget>());
      final imp = result as ImperativeWidget;
      final surfaced = imp.blockers.firstWhere(
        (b) => b.disposition == CustomWidgetDisposition.deadEnd,
      );
      expect(surfaced.kind, BlockerKind.asyncOrLifecycle);
      expect(surfaced.detail, 'the State lifecycle method initState()');
      expect(surfaced.detail, isNot(contains('Restage')));
    });

    test(
        "a StatefulWidget's blueprint captures each State field as a "
        'CustomWidgetStateField with the folded initial value', () async {
      final classification = await classifyFixtureResult(
        {
          'lib/multistate.dart': '''
$kClassifierStubs

class GestureDetector extends StatelessWidget {
  const GestureDetector({this.onTap, this.child});
  final void Function()? onTap;
  final Widget? child;
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(
  name: 'AcmeMulti',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.input,
  description: 'multi',
)
class AcmeMulti extends StatefulWidget {
  const AcmeMulti();
  _AcmeMultiState createState() => _AcmeMultiState();
}

class _AcmeMultiState extends State<AcmeMulti> {
  bool on = false;
  int index = 0;
  double scale = 1.5;
  String label = "ready";
  void noop() => setState(() => on = on);
  Widget build(BuildContext context) => GestureDetector(onTap: noop);
}
''',
        },
        inputPath: 'lib/multistate.dart',
        widgetName: 'AcmeMulti',
        catalog: catalogWith([
          entry(
            name: 'GestureDetector',
            properties: const [],
            flutterType:
                'package:apps_examples/multistate.dart#GestureDetector',
          ),
        ]),
      );

      const key = 'package:apps_examples/multistate.dart#AcmeMulti';
      final blueprint = classification.blueprints[key];
      expect(blueprint, isNotNull);
      final state = blueprint!.state;
      expect(state, isNotNull);
      // Order follows the State class's field declaration order — the
      // emitted `state { … }` block needs a stable order for byte-identical
      // round-trips, so the classifier preserves the source order.
      expect(
        state!.map((f) => f.name).toList(),
        ['on', 'index', 'scale', 'label'],
      );
      expect(
        state.map((f) => f.initialValue).toList(),
        [false, 0, 1.5, 'ready'],
      );
      // `scale` is `double` — numeric so the emitter coerces to a double
      // literal in the state block (no `1` vs `1.0` ambiguity).
      expect(
        state.singleWhere((f) => f.name == 'scale').isNumeric,
        isTrue,
      );
      expect(
        state.singleWhere((f) => f.name == 'on').isNumeric,
        isFalse,
      );
    });

    test(
        'a StatefulWidget with a non-foldable State-field initialiser '
        'captures a null initialValue so the translator can diagnose it',
        () async {
      final classification = await classifyFixtureResult(
        {
          'lib/nonfold.dart': '''
$kClassifierStubs

class GestureDetector extends StatelessWidget {
  const GestureDetector({this.onTap, this.child});
  final void Function()? onTap;
  final Widget? child;
  Widget build(BuildContext context) => const Widget();
}

int _nonConst() => 42;

@RestageWidget(
  name: 'AcmeNonFold',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.input,
  description: 'non-foldable',
)
class AcmeNonFold extends StatefulWidget {
  const AcmeNonFold();
  _AcmeNonFoldState createState() => _AcmeNonFoldState();
}

class _AcmeNonFoldState extends State<AcmeNonFold> {
  int count = _nonConst();
  void noop() => setState(() => count = 0);
  Widget build(BuildContext context) => GestureDetector(onTap: noop);
}
''',
        },
        inputPath: 'lib/nonfold.dart',
        widgetName: 'AcmeNonFold',
        catalog: catalogWith([
          entry(
            name: 'GestureDetector',
            properties: const [],
            flutterType: 'package:apps_examples/nonfold.dart#GestureDetector',
          ),
        ]),
      );

      const key = 'package:apps_examples/nonfold.dart#AcmeNonFold';
      final blueprint = classification.blueprints[key];
      expect(blueprint, isNotNull);
      final state = blueprint!.state;
      expect(state, isNotNull);
      expect(state!.single.name, 'count');
      // The classifier records the field but cannot fold `_nonConst()`; the
      // translator will surface this as a stateShapeUnsupported diagnostic.
      expect(state.single.initialValue, isNull);
    });

    test(
        'a StatelessWidget has a null state list on its blueprint — only '
        'StatefulWidgets carry a state block', () async {
      final classification = await classifyFixtureResult(
        {
          'lib/stateless.dart': '''
$kClassifierStubs

class Box extends StatelessWidget {
  const Box({this.label});
  final String? label;
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(
  name: 'AcmeStateless',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'stateless',
)
class AcmeStateless extends StatelessWidget {
  const AcmeStateless({this.label});
  final String? label;
  Widget build(BuildContext context) => Box(label: label);
}
''',
        },
        inputPath: 'lib/stateless.dart',
        widgetName: 'AcmeStateless',
        catalog: catalogWith([
          entry(
            name: 'Box',
            properties: const [],
            flutterType: 'package:apps_examples/stateless.dart#Box',
          ),
        ]),
      );

      const key = 'package:apps_examples/stateless.dart#AcmeStateless';
      final blueprint = classification.blueprints[key];
      expect(blueprint, isNotNull);
      expect(blueprint!.state, isNull);
    });
  });

  group('WidgetClassifier — recursion', () {
    test('composing a custom widget rolls its mechanisms up transitively',
        () async {
      // Uses real `package:flutter/material.dart` `Theme`; a local `Box`
      // widget plays the catalog-widget role (decoupled from Flutter's
      // internal `Container` library path).
      final result = await classifyFixture(
        {
          'lib/nested.dart': '''
$kFlutterClassifierStubs

class Box extends StatelessWidget {
  const Box({this.child, this.color, super.key});
  final Widget? child;
  final Color? color;
  @override
  Widget build(BuildContext context) => const SizedBox();
}

@RestageWidget(
  name: 'AcmePill',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.display,
  description: 'pill',
)
class AcmePill extends StatelessWidget {
  const AcmePill({super.key});
  @override
  Widget build(BuildContext context) =>
      Box(color: Theme.of(context).colorScheme.primary);
}

@RestageWidget(
  name: 'AcmeCard',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'card',
)
class AcmeCard extends StatelessWidget {
  const AcmeCard({super.key});
  @override
  Widget build(BuildContext context) => Box(child: const AcmePill());
}
''',
        },
        inputPath: 'lib/nested.dart',
        widgetName: 'AcmeCard',
        catalog: catalogWith([
          entry(
            name: 'Box',
            properties: const [],
            flutterType: 'package:apps_examples/nested.dart#Box',
          ),
        ]),
      );

      expect(result, isA<ComposableWidget>());
      final composable = result as ComposableWidget;
      expect(
        composable.composedCustomWidgets,
        contains('package:apps_examples/nested.dart#AcmePill'),
      );
      expect(
        composable.requiredMechanisms,
        contains(InliningMechanism.themeAsData),
      );
    });

    test('composing an imperative custom widget is itself imperative',
        () async {
      final result = await classifyFixture(
        {
          'lib/outer.dart': '''
$kClassifierStubs

class CustomPainter { const CustomPainter(); }
class CustomPaint extends StatelessWidget {
  const CustomPaint({this.painter});
  final CustomPainter? painter;
  Widget build(BuildContext context) => const Widget();
}
class ChartPainter extends CustomPainter {
  const ChartPainter();
}

@RestageWidget(
  name: 'AcmeChart',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.display,
  description: 'chart',
)
class AcmeChart extends StatelessWidget {
  const AcmeChart();
  Widget build(BuildContext context) =>
      CustomPaint(painter: ChartPainter());
}

@RestageWidget(
  name: 'AcmeCard',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'card',
)
class AcmeCard extends StatelessWidget {
  const AcmeCard();
  Widget build(BuildContext context) => AcmeChart();
}
''',
        },
        inputPath: 'lib/outer.dart',
        widgetName: 'AcmeCard',
      );

      expect(result, isA<ImperativeWidget>());
      expect(
        (result as ImperativeWidget).blockers.first.kind,
        BlockerKind.composesImperativeWidget,
      );
    });

    test('a multi-statement build() body is UnclassifiableWidget', () async {
      final result = await classifyFixture(
        {
          'lib/multi.dart': '''
$kClassifierStubs

class Container extends StatelessWidget {
  const Container();
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(
  name: 'AcmeMulti',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'multi',
)
class AcmeMulti extends StatelessWidget {
  const AcmeMulti();
  Widget build(BuildContext context) {
    assert(true);
    return Container();
  }
}
''',
        },
        inputPath: 'lib/multi.dart',
        widgetName: 'AcmeMulti',
      );

      expect(result, isA<UnclassifiableWidget>());
      expect(
        (result as UnclassifiableWidget).reason,
        contains('single returned expression'),
      );
      // No specific diagnosticCode — falls back to the generic one.
      expect(result.diagnosticCode, IssueCode.customWidgetUnclassified);
    });

    test(
        'a build() body binding Theme.of(...) to a `final` local resolves '
        'through to a ComposableWidget with themeAsData (rung 2)', () async {
      // Uses real `package:flutter/material.dart` `Theme`; a local `Box`
      // widget plays the catalog-widget role. The bound `cs` local resolves
      // through to the theme read at the `cs.primary` use site.
      final result = await classifyFixture(
        {
          'lib/intermediate.dart': '''
$kFlutterClassifierStubs

class Box extends StatelessWidget {
  const Box({this.color, super.key});
  final Color? color;
  @override
  Widget build(BuildContext context) => const SizedBox();
}

@RestageWidget(
  name: 'AcmeBanner',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'banner',
)
class AcmeBanner extends StatelessWidget {
  const AcmeBanner({super.key});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Box(color: cs.primary);
  }
}
''',
        },
        inputPath: 'lib/intermediate.dart',
        widgetName: 'AcmeBanner',
        catalog: catalogWith([
          entry(
            name: 'Box',
            properties: const [],
            flutterType: 'package:apps_examples/intermediate.dart#Box',
          ),
        ]),
      );

      expect(result, isA<ComposableWidget>());
      expect(
        (result as ComposableWidget).requiredMechanisms,
        contains(InliningMechanism.themeAsData),
      );
    });

    test('a composition cycle is UnclassifiableWidget', () async {
      final result = await classifyFixture(
        {
          'lib/loop.dart': '''
$kClassifierStubs

@RestageWidget(
  name: 'AcmeLoop',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'loop',
)
class AcmeLoop extends StatelessWidget {
  const AcmeLoop();
  Widget build(BuildContext context) => AcmeLoop();
}
''',
        },
        inputPath: 'lib/loop.dart',
        widgetName: 'AcmeLoop',
      );

      expect(result, isA<UnclassifiableWidget>());
      expect(
        (result as UnclassifiableWidget).reason,
        contains('cycle'),
      );
    });
  });

  group('WidgetClassifier — soundness invariant', () {
    test('compute over a widget field via `widget.` is runtimeComputedValue',
        () async {
      final result = await classifyFixture(
        {
          'lib/scaler.dart': '''
$kClassifierStubs

class Container extends StatelessWidget {
  const Container({this.width});
  final double? width;
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(
  name: 'AcmeScaler',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'scaler',
)
class AcmeScaler extends StatefulWidget {
  const AcmeScaler({this.size = 0});
  final double size;
  _AcmeScalerState createState() => _AcmeScalerState();
}

class _AcmeScalerState extends State<AcmeScaler> {
  Widget build(BuildContext context) => Container(width: widget.size * 2);
}
''',
        },
        inputPath: 'lib/scaler.dart',
        widgetName: 'AcmeScaler',
        catalog: catalogWith([
          entry(
            name: 'Container',
            properties: const [],
            flutterType: 'package:apps_examples/scaler.dart#Container',
          ),
        ]),
      );

      expect(result, isA<ImperativeWidget>());
      expect(
        (result as ImperativeWidget).blockers.first.kind,
        BlockerKind.runtimeComputedValue,
      );
    });

    test('a named-constructor catalog widget is matched by its full key',
        () async {
      final result = await classifyFixture(
        {
          'lib/named.dart': '''
$kClassifierStubs

class Banner extends StatelessWidget {
  const Banner.outlined();
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(
  name: 'AcmeNamed',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'named',
)
class AcmeNamed extends StatelessWidget {
  const AcmeNamed();
  Widget build(BuildContext context) => const Banner.outlined();
}
''',
        },
        inputPath: 'lib/named.dart',
        widgetName: 'AcmeNamed',
        catalog: catalogWith([
          entry(
            name: 'Banner',
            properties: const [],
            flutterType: 'package:apps_examples/named.dart#Banner.outlined',
          ),
        ]),
      );

      expect(result, isA<ComposableWidget>());
    });

    test(
        'a method tear-off event handler in a stateless widget is '
        'unclassifiable — only State methods can be lowered to set-state '
        'handlers, so a stateless tear-off has no RFW representation',
        () async {
      final result = await classifyFixture(
        {
          'lib/btn.dart': '''
$kClassifierStubs

class GestureDetector extends StatelessWidget {
  const GestureDetector({this.onTap, this.child});
  final void Function()? onTap;
  final Widget? child;
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(
  name: 'AcmeButton',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.input,
  description: 'button',
)
class AcmeButton extends StatelessWidget {
  const AcmeButton({this.child});
  final Widget? child;
  void handleTap() {}
  Widget build(BuildContext context) =>
      GestureDetector(onTap: handleTap, child: child);
}
''',
        },
        inputPath: 'lib/btn.dart',
        widgetName: 'AcmeButton',
        catalog: catalogWith([
          entry(
            name: 'GestureDetector',
            properties: const [],
            flutterType: 'package:apps_examples/btn.dart#GestureDetector',
          ),
        ]),
      );

      expect(result, isA<UnclassifiableWidget>());
      expect(
        (result as UnclassifiableWidget).reason,
        contains('method tear-off'),
      );
    });

    test('a non-constructor widget field is not a Phase-3-inlinable verdict',
        () async {
      final result = await classifyFixture(
        {
          'lib/listed.dart': '''
$kClassifierStubs

String buildRuntimeLabel() => '';

class Text extends StatelessWidget {
  const Text(this.data);
  final String? data;
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(
  name: 'AcmeListed',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.display,
  description: 'listed',
)
class AcmeListed extends StatelessWidget {
  AcmeListed();
  final String data = buildRuntimeLabel();
  Widget build(BuildContext context) => Text(data);
}
''',
        },
        inputPath: 'lib/listed.dart',
        widgetName: 'AcmeListed',
        catalog: catalogWith([
          entry(
            name: 'Text',
            properties: const [],
            flutterType: 'package:apps_examples/listed.dart#Text',
          ),
        ]),
      );

      // `data` is widget instance state, not a constructor argument — Phase 3
      // cannot emit it, so the widget must not be a plain-composition verdict.
      expect(result, isA<UnclassifiableWidget>());
    });

    test('a registered paywall-helper call classifies as composition',
        () async {
      final result = await classifyFixture(
        {
          'lib/priced.dart': '''
$kClassifierStubs

class Text extends StatelessWidget {
  const Text(this.data);
  final String? data;
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(
  name: 'AcmePriced',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.display,
  description: 'priced',
)
class AcmePriced extends StatelessWidget {
  const AcmePriced();
  Widget build(BuildContext context) => Text(paywallPriceFor(slot: 'pro'));
}
''',
        },
        inputPath: 'lib/priced.dart',
        widgetName: 'AcmePriced',
        catalog: catalogWith([
          entry(
            name: 'Text',
            properties: const [],
            flutterType: 'package:apps_examples/priced.dart#Text',
          ),
        ]),
        helpers: HelperRegistry()..registerAll(paywallHelpers),
      );

      expect(result, isA<ComposableWidget>());
    });

    test(
        'a customer paywallPurchase look-alike (a non-SDK library) is NOT '
        'recognised as the build helper — the (name, libraryOrigin) gate '
        'holds', () async {
      // The build registers `paywallPurchase` from the SDK library. A customer
      // function of the SAME NAME, resolved to the customer's own
      // library, must NOT be mistaken for it (the look-alike-safe rule): it
      // defers as a `dartCall`, never lowering to a `restage.purchase` event.
      // This pins the (name, libraryOrigin) gate so registering the build's
      // helpers in the scanner can never widen recognition to name-only.
      final result = await classifyFixture(
        {
          'lib/lookalike.dart': '''
$kClassifierStubs

// The customer's OWN paywallPurchase — same name, different library.
void Function() paywallPurchase({String? slot}) => () {};

class GestureDetector extends StatelessWidget {
  const GestureDetector({this.onTap});
  final void Function()? onTap;
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(
  name: 'AcmeLookalike',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.display,
  description: 'lookalike',
)
class AcmeLookalike extends StatelessWidget {
  const AcmeLookalike();
  Widget build(BuildContext context) =>
      GestureDetector(onTap: paywallPurchase(slot: 'pro'));
}
''',
        },
        inputPath: 'lib/lookalike.dart',
        widgetName: 'AcmeLookalike',
        catalog: catalogWith([
          entry(
            name: 'GestureDetector',
            properties: [prop('onTap', PropertyType.event)],
            flutterType: 'package:apps_examples/lookalike.dart#GestureDetector',
          ),
        ]),
        helpers: HelperRegistry()..registerAll(paywallHelpers),
      );

      expect(result, isA<ImperativeWidget>());
      expect(
        (result as ImperativeWidget).blockers,
        contains(
          isA<Blocker>()
              .having((b) => b.kind, 'kind', BlockerKind.dartCall)
              .having((b) => b.detail, 'detail', contains('paywallPurchase')),
        ),
        reason: 'the customer look-alike must defer as a dartCall naming '
            'paywallPurchase, never lower as the SDK purchase event',
      );
    });
  });

  group('WidgetClassifier — named-intermediate inlining', () {
    test(
        'a parameterless own helper returning a widget resolves-through to '
        'ComposableWidget', () async {
      final result = await classifyFixture(
        {
          'lib/card.dart': '''
$kClassifierStubs

class Container extends StatelessWidget {
  const Container({this.child});
  final Widget? child;
  Widget build(BuildContext context) => const Widget();
}

class Text extends StatelessWidget {
  const Text(this.data);
  final String? data;
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(
  name: 'AcmeCard',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'card',
)
class AcmeCard extends StatelessWidget {
  const AcmeCard();
  Widget _header() => Text("hi");
  Widget build(BuildContext context) => Container(child: _header());
}
''',
        },
        inputPath: 'lib/card.dart',
        widgetName: 'AcmeCard',
        catalog: _stubCatalog(),
      );

      expect(result, isA<ComposableWidget>());
    });

    test(
        'a same-library top-level helper function resolves-through to '
        'ComposableWidget', () async {
      final result = await classifyFixture(
        {
          'lib/card.dart': '''
$kClassifierStubs

class Container extends StatelessWidget {
  const Container({this.child});
  final Widget? child;
  Widget build(BuildContext context) => const Widget();
}

class Text extends StatelessWidget {
  const Text(this.data);
  final String? data;
  Widget build(BuildContext context) => const Widget();
}

Widget _header() => Text("hi");

@RestageWidget(
  name: 'AcmeCard',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'card',
)
class AcmeCard extends StatelessWidget {
  const AcmeCard();
  Widget build(BuildContext context) => Container(child: _header());
}
''',
        },
        inputPath: 'lib/card.dart',
        widgetName: 'AcmeCard',
        catalog: _stubCatalog(),
      );

      expect(result, isA<ComposableWidget>());
    });

    test(
        'a same-library static helper method resolves-through to '
        'ComposableWidget', () async {
      final result = await classifyFixture(
        {
          'lib/card.dart': '''
$kClassifierStubs

class Container extends StatelessWidget {
  const Container({this.child});
  final Widget? child;
  Widget build(BuildContext context) => const Widget();
}

class Text extends StatelessWidget {
  const Text(this.data);
  final String? data;
  Widget build(BuildContext context) => const Widget();
}

class Helpers {
  static Widget row(String s) => Text(s);
}

@RestageWidget(
  name: 'AcmeCard',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'card',
)
class AcmeCard extends StatelessWidget {
  const AcmeCard();
  Widget build(BuildContext context) => Container(child: Helpers.row("Pro"));
}
''',
        },
        inputPath: 'lib/card.dart',
        widgetName: 'AcmeCard',
        catalog: _stubCatalog(),
      );

      expect(result, isA<ComposableWidget>());
    });

    test(
        'a same-NAMED static helper on a DIFFERENT-library class does NOT '
        'inline — it defers (the same-library S13 boundary)', () async {
      // `Helpers.row` resolves to a class in `deps.dart`, a different library
      // than the widget's `card.dart`. Element identity (not the name) is the
      // gate: a same-named static in another library must NOT be inlined —
      // it falls through to the existing `dartCall` defer, never substituting
      // an unrelated library's helper body.
      final result = await classifyFixture(
        {
          'lib/deps.dart': '''
$kClassifierStubs

class Container extends StatelessWidget {
  const Container({this.child});
  final Widget? child;
  Widget build(BuildContext context) => const Widget();
}

class Text extends StatelessWidget {
  const Text(this.data);
  final String? data;
  Widget build(BuildContext context) => const Widget();
}

class Helpers {
  static Widget row(String s) => Text(s);
}
''',
          'lib/card.dart': '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'deps.dart';

@RestageWidget(
  name: 'AcmeCard',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'card',
)
class AcmeCard extends StatelessWidget {
  const AcmeCard();
  Widget build(BuildContext context) => Container(child: Helpers.row("Pro"));
}
''',
        },
        inputPath: 'lib/card.dart',
        widgetName: 'AcmeCard',
        catalog: _stubCatalog(file: 'deps.dart'),
      );

      expect(result, isA<ImperativeWidget>());
      expect(
        (result as ImperativeWidget).blockers.any(
              (b) => b.kind == BlockerKind.dartCall,
            ),
        isTrue,
        reason: 'a different-library static must defer as a dartCall, never '
            'inline a same-named helper from an unrelated library',
      );
    });

    test(
        'a parameterized own helper with a 1:1-bound argument resolves-through '
        'to ComposableWidget', () async {
      final result = await classifyFixture(
        {
          'lib/card.dart': '''
$kClassifierStubs

class Container extends StatelessWidget {
  const Container({this.child});
  final Widget? child;
  Widget build(BuildContext context) => const Widget();
}

class Text extends StatelessWidget {
  const Text(this.data);
  final String? data;
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(
  name: 'AcmeCard',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'card',
)
class AcmeCard extends StatelessWidget {
  const AcmeCard();
  Widget _row(String s) => Text(s);
  Widget build(BuildContext context) => Container(child: _row("Pro"));
}
''',
        },
        inputPath: 'lib/card.dart',
        widgetName: 'AcmeCard',
        catalog: _stubCatalog(),
      );

      expect(result, isA<ComposableWidget>());
    });

    test(
        'a helper call whose arguments do not bind 1:1 to the parameters is '
        'not inlined (diagnosed defer)', () async {
      final result = await classifyFixture(
        {
          'lib/card.dart': '''
$kClassifierStubs

class Container extends StatelessWidget {
  const Container({this.child});
  final Widget? child;
  Widget build(BuildContext context) => const Widget();
}

class Text extends StatelessWidget {
  const Text(this.data);
  final String? data;
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(
  name: 'AcmeCard',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'card',
)
class AcmeCard extends StatelessWidget {
  const AcmeCard();
  Widget _row(String a, [String b = "x"]) => Text(a);
  Widget build(BuildContext context) => Container(child: _row("only-one"));
}
''',
        },
        inputPath: 'lib/card.dart',
        widgetName: 'AcmeCard',
        catalog: _stubCatalog(),
      );

      expect(result, isA<ImperativeWidget>());
      expect(
        (result as ImperativeWidget).blockers.first.kind,
        BlockerKind.dartCall,
      );
    });

    test(
        'a widget-valued final local binding resolves-through to '
        'ComposableWidget', () async {
      final result = await classifyFixture(
        {
          'lib/card.dart': '''
$kClassifierStubs

class Container extends StatelessWidget {
  const Container({this.child});
  final Widget? child;
  Widget build(BuildContext context) => const Widget();
}

class Text extends StatelessWidget {
  const Text(this.data);
  final String? data;
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(
  name: 'AcmeCard',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'card',
)
class AcmeCard extends StatelessWidget {
  const AcmeCard();
  Widget build(BuildContext context) {
    final header = Text("hi");
    return Container(child: header);
  }
}
''',
        },
        inputPath: 'lib/card.dart',
        widgetName: 'AcmeCard',
        catalog: _stubCatalog(),
      );

      expect(result, isA<ComposableWidget>());
    });

    test('a directly recursive helper is unclassifiable, never looped',
        () async {
      final result = await classifyFixture(
        {
          'lib/card.dart': '''
$kClassifierStubs

class Container extends StatelessWidget {
  const Container({this.child});
  final Widget? child;
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(
  name: 'AcmeCard',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'card',
)
class AcmeCard extends StatelessWidget {
  const AcmeCard();
  Widget _loop() => Container(child: _loop());
  Widget build(BuildContext context) => _loop();
}
''',
        },
        inputPath: 'lib/card.dart',
        widgetName: 'AcmeCard',
        catalog: _stubCatalog(),
      );

      expect(result, isA<UnclassifiableWidget>());
      expect((result as UnclassifiableWidget).reason, contains('recursive'));
    });

    test('a mutually recursive helper pair is unclassifiable, never looped',
        () async {
      final result = await classifyFixture(
        {
          'lib/card.dart': '''
$kClassifierStubs

class Container extends StatelessWidget {
  const Container({this.child});
  final Widget? child;
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(
  name: 'AcmeCard',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'card',
)
class AcmeCard extends StatelessWidget {
  const AcmeCard();
  Widget _a() => Container(child: _b());
  Widget _b() => Container(child: _a());
  Widget build(BuildContext context) => _a();
}
''',
        },
        inputPath: 'lib/card.dart',
        widgetName: 'AcmeCard',
        catalog: _stubCatalog(),
      );

      expect(result, isA<UnclassifiableWidget>());
      expect((result as UnclassifiableWidget).reason, contains('recursive'));
    });

    test('a reassignable (var) local binding in build() is not inlinable',
        () async {
      final result = await classifyFixture(
        {
          'lib/card.dart': '''
$kClassifierStubs

class Container extends StatelessWidget {
  const Container({this.child});
  final Widget? child;
  Widget build(BuildContext context) => const Widget();
}

class Text extends StatelessWidget {
  const Text(this.data);
  final String? data;
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(
  name: 'AcmeCard',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'card',
)
class AcmeCard extends StatelessWidget {
  const AcmeCard();
  Widget build(BuildContext context) {
    var header = Text("hi");
    return Container(child: header);
  }
}
''',
        },
        inputPath: 'lib/card.dart',
        widgetName: 'AcmeCard',
        catalog: _stubCatalog(),
      );

      expect(result, isA<UnclassifiableWidget>());
    });
  });

  group('WidgetClassifier — emission blueprints', () {
    test(
        'a ComposableWidget gets a blueprint with its build expression and '
        'constructor arg names', () async {
      final result = await classifyFixtureResult(
        {
          'lib/card.dart': '''
$kClassifierStubs

class Container extends StatelessWidget {
  const Container({this.child});
  final Widget? child;
  Widget build(BuildContext context) => const Widget();
}

class Text extends StatelessWidget {
  const Text(this.data);
  final String? data;
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(
  name: 'AcmeCard',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'card',
)
class AcmeCard extends StatelessWidget {
  const AcmeCard({this.label});
  final String? label;
  Widget build(BuildContext context) => Container(child: Text(label));
}
''',
        },
        inputPath: 'lib/card.dart',
        widgetName: 'AcmeCard',
        catalog: _stubCatalog(),
      );

      const key = 'package:apps_examples/card.dart#AcmeCard';
      expect(result.classifications[key], isA<ComposableWidget>());
      final blueprint = result.blueprints[key];
      expect(blueprint, isNotNull);
      expect(blueprint!.classKey, key);
      expect(blueprint.rfwName, 'AcmeCard');
      expect(blueprint.params.map((p) => p.name), contains('label'));
    });

    test('an ImperativeWidget gets no blueprint', () async {
      final result = await classifyFixtureResult(
        {
          'lib/chart.dart': '''
$kClassifierStubs

class CustomPainter { const CustomPainter(); }

class CustomPaint extends StatelessWidget {
  const CustomPaint({this.painter});
  final CustomPainter? painter;
  Widget build(BuildContext context) => const Widget();
}

class ChartPainter extends CustomPainter {
  const ChartPainter();
}

@RestageWidget(
  name: 'AcmeChart',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.display,
  description: 'chart',
)
class AcmeChart extends StatelessWidget {
  const AcmeChart();
  Widget build(BuildContext context) =>
      CustomPaint(painter: ChartPainter());
}
''',
        },
        inputPath: 'lib/chart.dart',
        widgetName: 'AcmeChart',
      );

      const key = 'package:apps_examples/chart.dart#AcmeChart';
      expect(result.classifications[key], isA<ImperativeWidget>());
      expect(result.blueprints[key], isNull);
    });
  });

  group('WidgetClassifier — constant-folding boundary', () {
    const foldingFixture = {
      'lib/folding.dart': '''
$kClassifierStubs

const int kA = 4;
const int kB = 3;

class Box extends StatelessWidget {
  const Box({this.width, this.flag});
  final int? width;
  final bool? flag;
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(
  name: 'AcmeSum',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'sum',
)
class AcmeSum extends StatelessWidget {
  const AcmeSum();
  Widget build(BuildContext context) => Box(width: kA + kB);
}

@RestageWidget(
  name: 'AcmeCompare',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'compare',
)
class AcmeCompare extends StatelessWidget {
  const AcmeCompare();
  Widget build(BuildContext context) => Box(flag: kA == kB);
}
''',
    };
    final foldingCatalog = catalogWith([
      entry(
        name: 'Box',
        properties: const [],
        flutterType: 'package:apps_examples/folding.dart#Box',
      ),
    ]);

    test('const arithmetic carries the constantFolding mechanism', () async {
      final result = await classifyFixture(
        foldingFixture,
        inputPath: 'lib/folding.dart',
        widgetName: 'AcmeSum',
        catalog: foldingCatalog,
      );
      expect(result, isA<ComposableWidget>());
      expect(
        (result as ComposableWidget).requiredMechanisms,
        contains(InliningMechanism.constantFolding),
      );
    });

    test('a const expression the folder cannot evaluate is Unclassifiable',
        () async {
      // `kA == kB` is a compile-time constant, but the shared folder does not
      // evaluate `==` — the classifier must not tag it constantFolding (which
      // would let it reach inlining), nor call it runtime-imperative.
      final result = await classifyFixture(
        foldingFixture,
        inputPath: 'lib/folding.dart',
        widgetName: 'AcmeCompare',
        catalog: foldingCatalog,
      );
      expect(result, isA<UnclassifiableWidget>());
    });
  });

  group('WidgetClassifier — inlining guards', () {
    test('a widget declaring multiple constructors is Unclassifiable',
        () async {
      // Disambiguating which constructor a call site targets is deferred;
      // until then a multi-constructor widget must not reach inlining.
      final result = await classifyFixture(
        {
          'lib/multi.dart': '''
$kClassifierStubs

class Container extends StatelessWidget {
  const Container();
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(
  name: 'AcmeMultiCtor',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'multi-ctor',
)
class AcmeMultiCtor extends StatelessWidget {
  const AcmeMultiCtor();
  const AcmeMultiCtor.alt();
  Widget build(BuildContext context) => Container();
}
''',
        },
        inputPath: 'lib/multi.dart',
        widgetName: 'AcmeMultiCtor',
        catalog: catalogWith([
          entry(
            name: 'Container',
            properties: const [],
            flutterType: 'package:apps_examples/multi.dart#Container',
          ),
        ]),
      );
      expect(result, isA<UnclassifiableWidget>());
    });

    test('a parameter with an unfoldable default is Unclassifiable', () async {
      // A structured-const default cannot be folded to a literal, so an
      // omitted argument could not reproduce the Dart default.
      final result = await classifyFixture(
        {
          'lib/padded.dart': '''
$kClassifierStubs

class EdgeInsets {
  const EdgeInsets.all(this.value);
  final double value;
}

class Container extends StatelessWidget {
  const Container({this.padding});
  final EdgeInsets? padding;
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(
  name: 'AcmePadded',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'padded',
)
class AcmePadded extends StatelessWidget {
  const AcmePadded({this.pad = const EdgeInsets.all(8)});
  final EdgeInsets pad;
  Widget build(BuildContext context) => Container(padding: pad);
}
''',
        },
        inputPath: 'lib/padded.dart',
        widgetName: 'AcmePadded',
        catalog: catalogWith([
          entry(
            name: 'Container',
            properties: const [],
            flutterType: 'package:apps_examples/padded.dart#Container',
          ),
        ]),
      );
      expect(result, isA<UnclassifiableWidget>());
    });

    test('a parameter with a non-finite default is Unclassifiable', () async {
      // double.infinity has no representable RFW literal — an omitted
      // argument could not reproduce it.
      final result = await classifyFixture(
        {
          'lib/sized.dart': '''
$kClassifierStubs

class Container extends StatelessWidget {
  const Container();
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(
  name: 'AcmeSized',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'sized',
)
class AcmeSized extends StatelessWidget {
  const AcmeSized({this.maxWidth = double.infinity});
  final double maxWidth;
  Widget build(BuildContext context) => Container();
}
''',
        },
        inputPath: 'lib/sized.dart',
        widgetName: 'AcmeSized',
        catalog: catalogWith([
          entry(
            name: 'Container',
            properties: const [],
            flutterType: 'package:apps_examples/sized.dart#Container',
          ),
        ]),
      );
      expect(result, isA<UnclassifiableWidget>());
    });
  });
}

final Catalog _mechanismsCatalog = catalogWith([
  entry(
    name: 'Container',
    properties: const [],
    flutterType: 'package:apps_examples/mechanisms.dart#Container',
  ),
]);

final Map<String, String> _mechanismsFixture = {
  'lib/mechanisms.dart': '''
$kClassifierStubs

const double kGap = 16;

class EdgeInsets {
  const EdgeInsets.all(this.value);
  final double value;
}

class Container extends StatelessWidget {
  const Container({this.child, this.padding, this.width});
  final Widget? child;
  final EdgeInsets? padding;
  final double? width;
  Widget build(BuildContext context) => const Widget();
}

@RestageWidget(
  name: 'AcmePanel',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'panel',
)
class AcmePanel extends StatelessWidget {
  const AcmePanel();
  Widget build(BuildContext context) =>
      Container(padding: EdgeInsets.all(16));
}

@RestageWidget(
  name: 'AcmeGap',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'gap',
)
class AcmeGap extends StatelessWidget {
  const AcmeGap();
  Widget build(BuildContext context) =>
      Container(padding: EdgeInsets.all(kGap));
}

@RestageWidget(
  name: 'AcmeBox',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'box',
)
class AcmeBox extends StatelessWidget {
  const AcmeBox({this.size = 0});
  final double size;
  Widget build(BuildContext context) => Container(width: size * 2);
}
''',
};
