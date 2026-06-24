// Minimal coverage fixture — one customer widget per CoverageBucket
// (theme-as-data deferred to the broader fixture set so this slice can
// validate the harness without spinning up the real-Flutter resolution
// path). All widgets are recognised by the classifier; the bucketing
// in [coverage_snapshot.json] is the expected post-classification
// partition.
//
// Use a self-contained `kClassifierStubs`-style preamble: local stubs
// for the framework base classes plus the catalog widgets the
// fixtures compose against. Each catalog stub's `flutterType` matches
// the `<library URI>#<Class>` the classifier derives, so the catalog
// declared in `coverage_harness_test.dart` resolves them.
//
// Stub fixture file — analyzer hints that conflict with the
// reproduction-of-customer-shape goal are suppressed at file scope.
// `prefer_const_constructors` would alter the exact AST shape the
// classifier walks; `library_private_types_in_public_api` is the
// idiomatic Flutter StatefulWidget pattern; `document_ignores` and
// `annotate_overrides` are cosmetic on stub bodies.
// ignore_for_file: prefer_const_constructors,
// ignore_for_file: library_private_types_in_public_api,
// ignore_for_file: annotate_overrides

import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

class Widget {
  const Widget();
}

class BuildContext {}

abstract class StatelessWidget extends Widget {
  const StatelessWidget();
}

abstract class StatefulWidget extends Widget {
  const StatefulWidget();
}

abstract class State<T extends StatefulWidget> {
  late T widget;
  Widget build(BuildContext context);
  void setState(void Function() fn) {}
}

class Container extends StatelessWidget {
  const Container({this.child, this.padding});
  final Widget? child;
  final EdgeInsets? padding;
  Widget build(BuildContext context) => const Widget();
}

class Text extends StatelessWidget {
  const Text(this.data);
  final String? data;
  Widget build(BuildContext context) => const Widget();
}

class GestureDetector extends StatelessWidget {
  const GestureDetector({this.onTap, this.child});
  final void Function()? onTap;
  final Widget? child;
  Widget build(BuildContext context) => const Widget();
}

class EdgeInsets {
  const EdgeInsets.all(this.value);
  final double value;
}

class CustomPainter {
  const CustomPainter();
}

class CustomPaint extends StatelessWidget {
  const CustomPaint({this.painter});
  final CustomPainter? painter;
  Widget build(BuildContext context) => const Widget();
}

class _ChartPainter extends CustomPainter {
  const _ChartPainter();
}

const double _kGap = 8;

// ─── inlinable / composition-only ─────────────────────────────────────
@RestageWidget(
  name: 'MinCardComposition',
  library: WidgetLibrary.custom('coverage.minimal'),
  category: WidgetCategory.layout,
  description: 'card — pure composition',
)
class MinCardComposition extends StatelessWidget {
  const MinCardComposition({this.label});
  final String? label;
  Widget build(BuildContext context) => Container(child: Text(label));
}

// ─── inlinable / + const-fold ─────────────────────────────────────────
@RestageWidget(
  name: 'MinCardConstFold',
  library: WidgetLibrary.custom('coverage.minimal'),
  category: WidgetCategory.layout,
  description: 'card — uses const-folded EdgeInsets',
)
class MinCardConstFold extends StatelessWidget {
  const MinCardConstFold({this.label});
  final String? label;
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.all(_kGap),
        child: Text(label),
      );
}

// ─── inlinable / + declarative-state ──────────────────────────────────
@RestageWidget(
  name: 'MinToggle',
  library: WidgetLibrary.custom('coverage.minimal'),
  category: WidgetCategory.input,
  description: 'bool-state toggle',
)
class MinToggle extends StatefulWidget {
  const MinToggle();
  _MinToggleState createState() => _MinToggleState();
}

class _MinToggleState extends State<MinToggle> {
  bool on = false;
  void toggle() => setState(() => on = !on);
  Widget build(BuildContext context) =>
      GestureDetector(onTap: toggle, child: const Text('tap'));
}

// ─── deferred (inline event-handler closure) ──────────────────────────
@RestageWidget(
  name: 'MinInlineHandler',
  library: WidgetLibrary.custom('coverage.minimal'),
  category: WidgetCategory.input,
  description: 'uses an inline closure — deferred',
)
class MinInlineHandler extends StatelessWidget {
  const MinInlineHandler();
  Widget build(BuildContext context) =>
      GestureDetector(onTap: () {}, child: const Text('tap'));
}

// ─── structural (CustomPaint) ─────────────────────────────────────────
@RestageWidget(
  name: 'MinChart',
  library: WidgetLibrary.custom('coverage.minimal'),
  category: WidgetCategory.decoration,
  description: 'CustomPaint — structurally outside RFW',
)
class MinChart extends StatelessWidget {
  const MinChart();
  Widget build(BuildContext context) =>
      CustomPaint(painter: const _ChartPainter());
}
