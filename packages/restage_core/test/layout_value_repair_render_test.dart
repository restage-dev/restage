// End-to-end fail-safe proofs for the layout-bearing value repairs.
//
// Two failure modes matter here, and they are not equal.
//
// A throw during the BUILD phase is *contained*: it propagates out of the
// factory, the runtime error boundary catches it, and the surface degrades to a
// safe replacement. Loud and safe.
//
// A throw during the LAYOUT phase is not. `RenderObject.layout` wraps
// `performLayout` in its own try/catch and merely reports the error, so it never
// reaches the error boundary — the user is left with a broken frame and no
// signal. And Flutter's preconditions here are `assert`s, which are stripped
// from release *and* profile builds, so nothing catches the bad value in
// production at all. That is the mode these repairs exist to prevent.
//
// So a layout-bearing value cannot be validated where it is used; it has to be
// repaired on the way in. Two slots are repaired today — the reassembled
// `BoxConstraints` and the decoded inset — and these tests drive hostile values
// through the REAL generated factories, render through a REAL `Runtime`, and
// assert on what the render objects DERIVE (the size laid out, the sums a
// padding subtracts) rather than on what they were handed.
//
// **These repairs do not close the class.** A widget that takes a raw `width` or
// `height` still tightens its constraints against those separately, and other
// layout-bearing slots — a raw alignment, a border side — still decode without
// repair. What is proved below is that these two paths are safe, not that every
// path is.

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';
import 'package:rfw/formats.dart';
import 'package:rfw/rfw.dart';

const LibraryName _coreLibrary = LibraryName(<String>['restage', 'core']);
const LibraryName _rootLibrary = LibraryName(<String>['restage', 'paywall']);

/// The bounded viewport these cases lay out against.
const double _kViewport = 300;

Future<void> _pump(
  WidgetTester tester,
  String paywallSource, {
  Map<String, Object?>? data,
}) async {
  final runtime = Runtime()
    ..update(_coreLibrary, buildCoreWidgetLibrary())
    ..update(_rootLibrary, parseLibraryFile(paywallSource));
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      // The `Center` is load-bearing, not decoration. `pumpWidget` gives its
      // root TIGHT screen-sized constraints, so a bare `SizedBox` there is
      // forced to the full test window and the viewport below would be a
      // fiction — the number these tests assert their derived geometry against
      // would not be the one the widget actually laid out against. Loosening the
      // constraints first lets the box be the size it says it is.
      child: Center(
        child: SizedBox(
          width: _kViewport,
          height: _kViewport,
          child: RemoteWidget(
            runtime: runtime,
            data: DynamicContent(data ?? <String, Object?>{}),
            widget: const FullyQualifiedWidgetName(_rootLibrary, 'Paywall'),
            onEvent: (_, __) {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

String _constrained(String args) => '''
import restage.core;
widget Paywall = ConstrainedBox($args child: SizedBox());
''';

/// Puts [widget] on an axis its parent leaves unbounded: a `Row` lays its
/// non-flex children out against an infinite main-axis maximum.
///
/// That is the composition that turns an infinite constraint MINIMUM into an
/// infinite child extent, and from there into `NaN` — so it is the composition a
/// constraint repair has to survive.
String _inUnboundedWidth(String widget) => '''
import restage.core;
widget Paywall = Row(children: [$widget]);
''';

/// A `Padding` on an axis its parent leaves unbounded. The scroll view is the
/// unbounded axis that does not itself report an overflow, so what the test
/// observes is the padding's own derived geometry and nothing else.
String _paddingInUnboundedAxis(String padding) => '''
import restage.core;
widget Paywall = SingleChildScrollView(scrollDirection: "horizontal",
  child: Padding(padding: $padding,
    child: SizedBox(width: 10.0, height: 10.0)));
''';

void main() {
  group('a constraint pair is repaired before it can reach layout', () {
    testWidgets('an inverted pair is normalized, not handed to performLayout',
        (tester) async {
      // `BoxConstraints` does not validate itself: `debugAssertIsValid` is
      // debug-only AND it is the render object, not the constructor, that calls
      // it. So in release an inverted pair reaches `performLayout`, where a
      // throw is swallowed and reported — a broken frame, uncontained. Raise the
      // maximum to meet the minimum instead.
      await _pump(
        tester,
        _constrained('minWidth: 500.0, maxWidth: 10.0,'),
      );

      final box = tester.widget<ConstrainedBox>(find.byType(ConstrainedBox));
      expect(box.constraints.minWidth, 500.0);
      expect(box.constraints.maxWidth, 500.0);
      expect(box.constraints.isNormalized, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a NaN bound is repaired, not laid out against',
        (tester) async {
      await _pump(
        tester,
        _constrained('minHeight: data.nan, maxHeight: data.nan,'),
        data: <String, Object?>{'nan': double.nan},
      );

      final box = tester.widget<ConstrainedBox>(find.byType(ConstrainedBox));
      expect(box.constraints.minHeight, 0.0);
      expect(box.constraints.maxHeight, double.infinity);
      expect(box.constraints.isNormalized, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a negative minimum floors at zero', (tester) async {
      await _pump(
        tester,
        _constrained('minWidth: -40.0, minHeight: -40.0,'),
      );

      final box = tester.widget<ConstrainedBox>(find.byType(ConstrainedBox));
      expect(box.constraints.minWidth, 0.0);
      expect(box.constraints.minHeight, 0.0);
      expect(box.constraints.isNormalized, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an infinite minimum floors at zero', (tester) async {
      // An infinite MAXIMUM means "unbounded", which every box knows how to lay
      // out, and it is preserved. An infinite MINIMUM means "you must be at
      // least infinitely large", and it only survives while some ancestor bounds
      // the axis. Put one on an axis a parent has left unbounded — a `Row` — and
      // the child is laid out at an infinite extent, whose offset and overflow
      // are then `Infinity` arithmetic that resolves to `NaN`, inside the layout
      // phase, in release.
      //
      // Preserving it was a trade for `BoxConstraints.expand()`, and the trade
      // bought nothing: no authoring path can produce an infinite minimum — the
      // build-time toolchain rejects a non-finite real outright, and nothing
      // lowers to `.expand()` — so the only thing that carries one is a corrupt
      // or hostile wire, which is exactly the thing that must not reach the NaN.
      // Floor it.
      await _pump(
        tester,
        _inUnboundedWidth(
          'ConstrainedBox(minWidth: data.inf, maxWidth: data.inf, '
          'child: SizedBox())',
        ),
        data: <String, Object?>{'inf': double.infinity},
      );

      final box = tester.widget<ConstrainedBox>(find.byType(ConstrainedBox));
      expect(box.constraints.minWidth, 0.0);
      expect(box.constraints.maxWidth, double.infinity);
      expect(box.constraints.isNormalized, isTrue);
      // The derived fact, not the input: the box laid out at a finite extent.
      expect(
        tester.getSize(find.byType(ConstrainedBox)).width.isFinite,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('Container and AnimatedContainer floor it too', (tester) async {
      // The same repair feeds all three factories, so the same hostile wire
      // reaches layout through all three. Cover the whole branch, not the one
      // widget the exploit happened to be written against.
      const sources = <String, String>{
        'Container': 'Container(minWidth: data.inf, maxWidth: data.inf, '
            'child: SizedBox())',
        'AnimatedContainer':
            'AnimatedContainer(duration: 100, minWidth: data.inf, '
                'maxWidth: data.inf, child: SizedBox())',
      };
      for (final entry in sources.entries) {
        await _pump(
          tester,
          _inUnboundedWidth(entry.value),
          data: <String, Object?>{'inf': double.infinity},
        );

        final box = tester.widget<ConstrainedBox>(find.byType(ConstrainedBox));
        expect(box.constraints.minWidth, 0.0, reason: entry.key);
        expect(box.constraints.isNormalized, isTrue, reason: entry.key);
        expect(tester.takeException(), isNull, reason: entry.key);
      }
    });

    testWidgets('an int on a real slot is the value, not an absent slot',
        (tester) async {
      // `DataSource.v<double>` is a strict type check: a whole number written
      // as `200` rather than `200.0` reads back as null through it —
      // indistinguishable from an absent slot — and the slot would silently
      // take its default, here `double.infinity`. A box the author constrained
      // would render unconstrained, and nothing downstream could tell: by the
      // time the constraint repair sees the assembled value, the number is
      // already gone. The slot reads both wire number shapes instead.
      await _pump(tester, _constrained('maxWidth: 200, minHeight: 40,'));

      final box = tester.widget<ConstrainedBox>(find.byType(ConstrainedBox));
      expect(box.constraints.maxWidth, 200.0);
      expect(box.constraints.minHeight, 40.0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a legal constraint pair is passed through untouched',
        (tester) async {
      await _pump(
        tester,
        _constrained('minWidth: 100.0, maxWidth: 200.0, maxHeight: 50.0,'),
      );

      final box = tester.widget<ConstrainedBox>(find.byType(ConstrainedBox));
      expect(box.constraints.minWidth, 100.0);
      expect(box.constraints.maxWidth, 200.0);
      expect(box.constraints.minHeight, 0.0);
      expect(box.constraints.maxHeight, 50.0);
      expect(tester.takeException(), isNull);
    });
  });

  group('an inset is repaired before it can reach layout', () {
    // An inset is subtracted from the space a box or a sliver has to give its
    // child. The widgets that consume one validate it with an `assert`, which is
    // stripped from release AND profile — so a corrupt component does not fail
    // at the boundary, it fails inside `performLayout`, where the pipeline
    // catches the throw and merely reports it. Repair it on the way in instead.

    // Only the WIDTH is asserted below. The horizontal scroll view leaves the
    // width unbounded — the axis on which a corrupt inset turns into NaN — while
    // tightening the height to the viewport, so the height carries no
    // information about the inset and the width carries all of it.

    testWidgets('a NaN inset cannot poison the constraints it deflates',
        (tester) async {
      await _pump(
        tester,
        _paddingInUnboundedAxis('[data.nan]'),
        data: <String, Object?>{'nan': double.nan},
      );

      // The derived fact: the padded box laid out at the child's own width,
      // because a NaN inset was repaired to one that subtracts nothing.
      expect(tester.getSize(find.byType(Padding)).width, 10.0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a negative inset floors at zero', (tester) async {
      await _pump(tester, _paddingInUnboundedAxis('[-40.0]'));

      expect(tester.getSize(find.byType(Padding)).width, 10.0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an axis whose components SUM to infinity collapses to zero',
        (tester) async {
      // The derived quantity again, and the reason a per-component finiteness
      // check is not enough. What layout subtracts is not a component but a sum:
      // `EdgeInsetsGeometry.horizontal`. Two merely finite components sum to
      // infinity (`1.7e308 + 1.7e308`), and subtracting THAT from an unbounded
      // axis is `Infinity - Infinity` — a NaN constraint, handed to the child,
      // during layout.
      //
      // Pin the arithmetic as a fact before asserting the repair prevents it.
      expect(const EdgeInsets.all(1.7e308).horizontal, double.infinity);
      expect(double.infinity - double.infinity, isNaN);

      await _pump(
        tester,
        _paddingInUnboundedAxis('[data.vast]'),
        data: <String, Object?>{'vast': 1.7e308},
      );

      // The disposition, asserted on the value the render object actually
      // holds: the axis that could not be represented is gone entirely, rather
      // than quietly rescaled to some number nobody asked for.
      final render = tester.renderObject<RenderPadding>(find.byType(Padding));
      expect(render.padding, EdgeInsetsDirectional.zero);

      // And what that derives: the child's own width, not a NaN constraint
      // handed down to it.
      expect(tester.getSize(find.byType(Padding)).width, 10.0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an overflowing axis does not disturb a legal one',
        (tester) async {
      // The pair is the unit of the sum check, so it must also be the unit of
      // the repair: a vertical inset nobody can represent is no reason to throw
      // away a horizontal one that is perfectly legal.
      await _pump(
        tester,
        // [start, top, end, bottom] — the vertical pair overflows, the
        // horizontal pair is ordinary.
        _paddingInUnboundedAxis('[4.0, data.vast, 16.0, data.vast]'),
        data: <String, Object?>{'vast': 1.7e308},
      );

      final render = tester.renderObject<RenderPadding>(find.byType(Padding));
      expect(
        render.padding,
        const EdgeInsetsDirectional.fromSTEB(4, 0, 16, 0),
      );
      expect(tester.getSize(find.byType(Padding)).width, 30.0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a large but legal inset is NOT truncated', (tester) async {
      // A big inset is a real layout, not a corruption. A horizontally
      // scrolling view with a 2,000,000px inset and a 10px child has a content
      // width of 4,000,010px — that is what Flutter does with it, and it is
      // what the author asked for. An arbitrary magnitude ceiling would halve
      // that number and render something nobody wrote, silently: a wrong render
      // of a VALID surface, which is a worse failure than the corrupt wire the
      // repair is here for. Preserve every finite component, at any magnitude;
      // only the sum that cannot be represented at all is repaired.
      const inset = 2e6; // deliberately above the ceiling that used to exist
      await _pump(tester, _paddingInUnboundedAxis('[$inset]'));

      final render = tester.renderObject<RenderPadding>(find.byType(Padding));
      expect(
        render.padding,
        const EdgeInsetsDirectional.fromSTEB(inset, inset, inset, inset),
      );
      expect(tester.getSize(find.byType(Padding)).width, 10.0 + 2 * inset);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a legal inset is passed through untouched', (tester) async {
      // The repair must not distort a design anyone authored — and all four
      // components must survive it, not just the two the width happens to sum.
      await _pump(tester, _paddingInUnboundedAxis('[4.0, 8.0, 16.0, 32.0]'));

      // What the render object was actually handed — every component intact.
      final render = tester.renderObject<RenderPadding>(find.byType(Padding));
      expect(
        render.padding,
        const EdgeInsetsDirectional.fromSTEB(4, 8, 16, 32),
      );
      // And what it derived from that: start 4 + child 10 + end 16.
      expect(tester.getSize(find.byType(Padding)).width, 30.0);
      expect(tester.takeException(), isNull);
    });
  });
}
