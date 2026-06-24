// Paywall-relevant coverage fixtures — widgets shaped like the
// surfaces a customer would actually author for a Restage paywall.
// Each widget targets a specific construct mix; the harness asserts
// the snapshot's bucket counts match the realised classification.
//
// Stub framework + catalog widgets locally (without Flutter imports)
// so the file resolves without `depend_on_referenced_packages`. The
// theme-read paywall fixture lives in `theme_as_data.dart` — paywall
// shapes that need real `Theme.of` resolution should be authored
// there.
//
// ignore_for_file: annotate_overrides,
// ignore_for_file: library_private_types_in_public_api,
// ignore_for_file: prefer_const_constructors

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

class Row extends StatelessWidget {
  const Row({this.children});
  final List<Widget>? children;
  Widget build(BuildContext context) => const Widget();
}

class Column extends StatelessWidget {
  const Column({this.children});
  final List<Widget>? children;
  Widget build(BuildContext context) => const Widget();
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

class Image extends StatelessWidget {
  const Image({this.src});
  final String? src;
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

const double _kRowGap = 12;

// ─── inlinable / composition-only ─────────────────────────────────────
@RestageWidget(
  name: 'PaywallHero',
  library: WidgetLibrary.custom('coverage.paywall'),
  category: WidgetCategory.decoration,
  description: 'hero image header — pure composition',
)
class PaywallHero extends StatelessWidget {
  const PaywallHero({this.src});
  final String? src;
  Widget build(BuildContext context) => Image(src: src);
}

@RestageWidget(
  name: 'PaywallRestoreLink',
  library: WidgetLibrary.custom('coverage.paywall'),
  category: WidgetCategory.input,
  description: 'restore-purchase link — composition with literal label',
)
class PaywallRestoreLink extends StatelessWidget {
  const PaywallRestoreLink({this.onTap});
  final void Function()? onTap;
  Widget build(BuildContext context) =>
      GestureDetector(onTap: onTap, child: const Text('Restore purchase'));
}

// ─── inlinable / + const-fold ─────────────────────────────────────────
@RestageWidget(
  name: 'PaywallFeatureRow',
  library: WidgetLibrary.custom('coverage.paywall'),
  category: WidgetCategory.layout,
  description: 'feature row with const-folded gap',
)
class PaywallFeatureRow extends StatelessWidget {
  const PaywallFeatureRow({this.label});
  final String? label;
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.all(_kRowGap),
        child: Row(children: [Text(label)]),
      );
}

// ─── inlinable / + declarative-state ──────────────────────────────────
@RestageWidget(
  name: 'PaywallAnnualToggle',
  library: WidgetLibrary.custom('coverage.paywall'),
  category: WidgetCategory.input,
  description: 'monthly/annual toggle — bool state',
)
class PaywallAnnualToggle extends StatefulWidget {
  const PaywallAnnualToggle();
  _PaywallAnnualToggleState createState() => _PaywallAnnualToggleState();
}

class _PaywallAnnualToggleState extends State<PaywallAnnualToggle> {
  bool annual = false;
  void toggle() => setState(() => annual = !annual);
  Widget build(BuildContext context) => GestureDetector(
        onTap: toggle,
        child: const Text('Monthly / Annual'),
      );
}

// ─── deferred (inline closure for a primary action) ───────────────────
@RestageWidget(
  name: 'PaywallPrimaryCta',
  library: WidgetLibrary.custom('coverage.paywall'),
  category: WidgetCategory.input,
  description: 'primary CTA with inline handler',
)
class PaywallPrimaryCta extends StatelessWidget {
  const PaywallPrimaryCta({this.label});
  final String? label;
  Widget build(BuildContext context) =>
      GestureDetector(onTap: () {}, child: Text(label));
}

// ─── structural (composed widget that itself uses CustomPaint) ────────
class CustomPainter {
  const CustomPainter();
}

class CustomPaint extends StatelessWidget {
  const CustomPaint({this.painter});
  final CustomPainter? painter;
  Widget build(BuildContext context) => const Widget();
}

class _GraphPainter extends CustomPainter {
  const _GraphPainter();
}

@RestageWidget(
  name: 'PaywallTrendGraph',
  library: WidgetLibrary.custom('coverage.paywall'),
  category: WidgetCategory.decoration,
  description: 'trend graph — uses CustomPaint',
)
class PaywallTrendGraph extends StatelessWidget {
  const PaywallTrendGraph();
  Widget build(BuildContext context) =>
      CustomPaint(painter: const _GraphPainter());
}
