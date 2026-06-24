// Broad synthetic Flutter-idiom census (B2) — representative of *customer
// authoring*, not just paywall shapes. Each widget exercises one idiom slot
// across the inlinable / deferred / structural spectrum, so the
// classifier-bucketing measures the frequency signal the tiered scope
// proposal needs.
//
// Real-Flutter resolution (imports `package:flutter/material.dart`) so the
// classifier's element-resolution gates fire (Theme.of, real imperative
// constructs). A local `Slot` stub stands in as the catalog widget the
// inlinable-candidate idioms compose against (a non-Flutter name so it does
// not collide with Flutter's own widgets); declared in the harness catalog.
//
// Classifier-bucketed only this phase (per the coordinator's lock-in #5);
// emit-confirmation against the real catalog converges post-L12. The silent-
// loss idioms (non-finite width, EdgeInsets.zero) classify inlinable here —
// their loss is at EMIT (a documented, known emit-time gap), not at classify.
//
// ignore_for_file: annotate_overrides, depend_on_referenced_packages
// ignore_for_file: library_private_types_in_public_api
// ignore_for_file: prefer_const_constructors
// IdiomHelperArityMismatch deliberately leaves an optional helper param
// unsupplied to exercise the non-1:1-binding defer:
// ignore_for_file: unused_element_parameter

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// The local stand-in catalog widget the inlinable-candidate idioms compose.
class Slot extends StatelessWidget {
  const Slot({
    this.child,
    this.label,
    this.width,
    this.padding,
    this.color,
    this.onTap,
    this.style,
    this.icon,
    super.key,
  });
  final Widget? child;
  final String? label;
  final double? width;
  final EdgeInsets? padding;
  final Color? color;
  final VoidCallback? onTap;
  final TextStyle? style;
  final IconData? icon;
  Widget build(BuildContext context) => const SizedBox();
}

const double _kGap = 8;

// ─── inlinable / composition-only ─────────────────────────────────────
@RestageWidget(
  name: 'IdiomComposition',
  library: WidgetLibrary.custom('coverage.idioms'),
  category: WidgetCategory.layout,
  description: 'pure composition',
)
class IdiomComposition extends StatelessWidget {
  const IdiomComposition({this.label, super.key});
  final String? label;
  Widget build(BuildContext context) => Slot(child: Slot(label: label));
}

// ─── inlinable / + const-fold ─────────────────────────────────────────
@RestageWidget(
  name: 'IdiomConstFold',
  library: WidgetLibrary.custom('coverage.idioms'),
  category: WidgetCategory.layout,
  description: 'build-time-constant arithmetic',
)
class IdiomConstFold extends StatelessWidget {
  const IdiomConstFold({super.key});
  Widget build(BuildContext context) => Slot(width: _kGap * 2);
}

// ─── inlinable / + theme-as-data (in-contract) ────────────────────────
@RestageWidget(
  name: 'IdiomThemeRead',
  library: WidgetLibrary.custom('coverage.idioms'),
  category: WidgetCategory.decoration,
  description: 'in-contract Theme.of read',
)
class IdiomThemeRead extends StatelessWidget {
  const IdiomThemeRead({super.key});
  Widget build(BuildContext context) =>
      Slot(color: Theme.of(context).colorScheme.primary);
}

// ─── inlinable / + declarative-state ──────────────────────────────────
@RestageWidget(
  name: 'IdiomBoolState',
  library: WidgetLibrary.custom('coverage.idioms'),
  category: WidgetCategory.input,
  description: 'bool-state toggle',
)
class IdiomBoolState extends StatefulWidget {
  const IdiomBoolState({super.key});
  _IdiomBoolStateState createState() => _IdiomBoolStateState();
}

class _IdiomBoolStateState extends State<IdiomBoolState> {
  bool on = false;
  void toggle() => setState(() => on = !on);
  Widget build(BuildContext context) => Slot(onTap: toggle, label: 'tap');
}

// ─── conditional expression over state ────────────────────────────────
@RestageWidget(
  name: 'IdiomConditional',
  library: WidgetLibrary.custom('coverage.idioms'),
  category: WidgetCategory.input,
  description: 'ternary over a state flag',
)
class IdiomConditional extends StatefulWidget {
  const IdiomConditional({super.key});
  _IdiomConditionalState createState() => _IdiomConditionalState();
}

class _IdiomConditionalState extends State<IdiomConditional> {
  bool expanded = false;
  Widget build(BuildContext context) =>
      expanded ? Slot(label: 'open') : Slot(label: 'closed');
}

// ─── A2: TextStyle ctor inside an inlined widget ──────────────────────
@RestageWidget(
  name: 'IdiomTextStyleArg',
  library: WidgetLibrary.custom('coverage.idioms'),
  category: WidgetCategory.decoration,
  description: 'A2 — TextStyle ctor (classifier-narrower-than-translator)',
)
class IdiomTextStyleArg extends StatelessWidget {
  const IdiomTextStyleArg({super.key});
  Widget build(BuildContext context) =>
      Slot(label: 'Pro', style: TextStyle(fontSize: 16));
}

// ─── A2: Icons.* reference ────────────────────────────────────────────
@RestageWidget(
  name: 'IdiomIconRef',
  library: WidgetLibrary.custom('coverage.idioms'),
  category: WidgetCategory.decoration,
  description: 'A2 — Icons.* named reference',
)
class IdiomIconRef extends StatelessWidget {
  const IdiomIconRef({super.key});
  Widget build(BuildContext context) => Slot(icon: Icons.star);
}

// ─── A2: Colors.* named constant ──────────────────────────────────────
@RestageWidget(
  name: 'IdiomColorConst',
  library: WidgetLibrary.custom('coverage.idioms'),
  category: WidgetCategory.decoration,
  description: 'A2 — Colors.* named constant',
)
class IdiomColorConst extends StatelessWidget {
  const IdiomColorConst({super.key});
  Widget build(BuildContext context) => Slot(color: Colors.transparent);
}

// ─── A4: adjacent-string concatenation ────────────────────────────────
@RestageWidget(
  name: 'IdiomAdjacentStrings',
  library: WidgetLibrary.custom('coverage.idioms'),
  category: WidgetCategory.decoration,
  description: 'A4 — adjacent string literals',
)
class IdiomAdjacentStrings extends StatelessWidget {
  const IdiomAdjacentStrings({super.key});
  Widget build(BuildContext context) => Slot(label: 'Save ' 'big');
}

// ─── deferred: inline closure handler ─────────────────────────────────
@RestageWidget(
  name: 'IdiomInlineClosure',
  library: WidgetLibrary.custom('coverage.idioms'),
  category: WidgetCategory.input,
  description: 'deferred — inline event-handler closure',
)
class IdiomInlineClosure extends StatelessWidget {
  const IdiomInlineClosure({super.key});
  Widget build(BuildContext context) => Slot(onTap: () {}, label: 'go');
}

// ─── inlinable: parameterless helper-function call ────────────────────
@RestageWidget(
  name: 'IdiomHelperCall',
  library: WidgetLibrary.custom('coverage.idioms'),
  category: WidgetCategory.layout,
  description: 'inlinable — calls a pure-composition parameterless helper',
)
class IdiomHelperCall extends StatelessWidget {
  const IdiomHelperCall({super.key});
  Widget _header() => Slot(label: 'header');
  Widget build(BuildContext context) => Slot(child: _header());
}

// ─── inlinable: parameterized helper with a 1:1-bound argument ─────────
@RestageWidget(
  name: 'IdiomParamHelper',
  library: WidgetLibrary.custom('coverage.idioms'),
  category: WidgetCategory.layout,
  description: 'inlinable — parameterized helper, argument bound 1:1',
)
class IdiomParamHelper extends StatelessWidget {
  const IdiomParamHelper({super.key});
  Widget _row(String s) => Slot(label: s);
  Widget build(BuildContext context) => Slot(child: _row('Pro'));
}

// ─── structural: helper argument does not bind 1:1 ────────────────────
@RestageWidget(
  name: 'IdiomHelperArityMismatch',
  library: WidgetLibrary.custom('coverage.idioms'),
  category: WidgetCategory.layout,
  description: 'structural — helper call args do not bind 1:1 (diagnosed)',
)
class IdiomHelperArityMismatch extends StatelessWidget {
  const IdiomHelperArityMismatch({super.key});
  // An optional parameter left to its default is a non-1:1 binding (valid
  // Dart, but the transpiler defers rather than guess the default value).
  Widget _row(String a, [String b = 'x']) => Slot(label: a);
  Widget build(BuildContext context) => Slot(child: _row('only-one'));
}

// ─── inlinable: widget-valued final local binding ─────────────────────
@RestageWidget(
  name: 'IdiomWidgetLocal',
  library: WidgetLibrary.custom('coverage.idioms'),
  category: WidgetCategory.layout,
  description: 'inlinable — widget-valued final local binding',
)
class IdiomWidgetLocal extends StatelessWidget {
  const IdiomWidgetLocal({super.key});
  Widget build(BuildContext context) {
    final header = Slot(label: 'header');
    return Slot(child: header);
  }
}

// ─── inlinable: const-local in build() (folds at the use site) ────────
@RestageWidget(
  name: 'IdiomConstLocal',
  library: WidgetLibrary.custom('coverage.idioms'),
  category: WidgetCategory.layout,
  description: 'inlinable — const local declaration folds at the use site',
)
class IdiomConstLocal extends StatelessWidget {
  const IdiomConstLocal({super.key});
  Widget build(BuildContext context) {
    const gap = 12.0;
    return Slot(width: gap);
  }
}

// ─── deferred/structural: runtime compute (DateTime.now) ──────────────
@RestageWidget(
  name: 'IdiomRuntimeCompute',
  library: WidgetLibrary.custom('coverage.idioms'),
  category: WidgetCategory.decoration,
  description: 'runtime compute — DateTime.now in build()',
)
class IdiomRuntimeCompute extends StatelessWidget {
  const IdiomRuntimeCompute({super.key});
  Widget build(BuildContext context) =>
      Slot(label: DateTime.now().toIso8601String());
}

// ─── structural: CustomPaint ──────────────────────────────────────────
class _DotPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {}
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

@RestageWidget(
  name: 'IdiomCustomPaint',
  library: WidgetLibrary.custom('coverage.idioms'),
  category: WidgetCategory.decoration,
  description: 'structural — CustomPaint',
)
class IdiomCustomPaint extends StatelessWidget {
  const IdiomCustomPaint({super.key});
  Widget build(BuildContext context) => CustomPaint(painter: _DotPainter());
}

// ─── structural: LayoutBuilder ────────────────────────────────────────
@RestageWidget(
  name: 'IdiomLayoutBuilder',
  library: WidgetLibrary.custom('coverage.idioms'),
  category: WidgetCategory.layout,
  description: 'structural — LayoutBuilder builder closure',
)
class IdiomLayoutBuilder extends StatelessWidget {
  const IdiomLayoutBuilder({super.key});
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) =>
            Slot(width: constraints.maxWidth / 2),
      );
}

// ─── structural: FutureBuilder ────────────────────────────────────────
@RestageWidget(
  name: 'IdiomFutureBuilder',
  library: WidgetLibrary.custom('coverage.idioms'),
  category: WidgetCategory.layout,
  description: 'structural — FutureBuilder async builder',
)
class IdiomFutureBuilder extends StatelessWidget {
  const IdiomFutureBuilder({super.key});
  Widget build(BuildContext context) => FutureBuilder<int>(
        future: Future.value(1),
        builder: (context, snapshot) => Slot(label: '${snapshot.data}'),
      );
}

// ─── structural: AnimationController + lifecycle ──────────────────────
@RestageWidget(
  name: 'IdiomController',
  library: WidgetLibrary.custom('coverage.idioms'),
  category: WidgetCategory.decoration,
  description: 'structural — controller + initState/dispose lifecycle',
)
class IdiomController extends StatefulWidget {
  const IdiomController({super.key});
  _IdiomControllerState createState() => _IdiomControllerState();
}

class _IdiomControllerState extends State<IdiomController>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget build(BuildContext context) => Slot(label: 'anim');
}

// ─── non-finite width: the classifier DEFERS it (safe) ────────────────
// As a *custom widget* this defers (the classifier can't fold double.infinity
// and it isn't an enum → Unclassifiable → deferred). The silent
// loss is the @PaywallSource TRANSLATOR path (`SizedBox(width:
// double.infinity)` authored directly in a paywall body emits `"infinity"`
// via the enum-name fallback), NOT this custom-widget classifier path — this
// fixture is the safe (deferred) data point for it.
@RestageWidget(
  name: 'IdiomNonFiniteWidth',
  library: WidgetLibrary.custom('coverage.idioms'),
  category: WidgetCategory.layout,
  description: 'non-finite width — classifier defers (safe); A3 is translator',
)
class IdiomNonFiniteWidth extends StatelessWidget {
  const IdiomNonFiniteWidth({super.key});
  Widget build(BuildContext context) => Slot(width: double.infinity);
}
