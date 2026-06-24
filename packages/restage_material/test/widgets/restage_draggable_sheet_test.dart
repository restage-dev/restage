import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_material/restage_material.dart';

/// Hosts a [RestageDraggableSheet] and lets a test flip `expanded` across
/// frames via [_HostState.setExpanded], mirroring how a paywall binds the
/// sheet's expand to a local state field (a tap → `set state.expanded = true`).
class _Host extends StatefulWidget {
  const _Host({
    this.startExpanded = false,
    this.initialChildSize = 0.5,
    this.minChildSize = 0.25,
    this.maxChildSize = 1.0,
    this.snap = false,
    this.snapSizes,
    this.expandDuration,
    this.expandCurve,
  });

  final bool startExpanded;
  final double initialChildSize;
  final double minChildSize;
  final double maxChildSize;
  final bool snap;
  final List<double>? snapSizes;
  final Duration? expandDuration;
  final Curve? expandCurve;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late bool expanded = widget.startExpanded;

  void setExpanded(bool value) => setState(() => expanded = value);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            const ColoredBox(color: Color(0xFFEEEEEE)),
            RestageDraggableSheet(
              expanded: expanded,
              initialChildSize: widget.initialChildSize,
              minChildSize: widget.minChildSize,
              maxChildSize: widget.maxChildSize,
              snap: widget.snap,
              snapSizes: widget.snapSizes,
              expandDuration: widget.expandDuration,
              expandCurve: widget.expandCurve,
              // A tall body so the inner SingleChildScrollView has overflow
              // content to scroll once the sheet is expanded.
              child: const SizedBox(
                height: 1200,
                width: double.infinity,
                child: Text('body'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The sheet's current size as a fraction of its parent — the rendered
/// `FractionallySizedBox.heightFactor`, which `DraggableScrollableSheet` keys
/// to its current extent. The single deterministic size probe.
double _sheetSize(WidgetTester tester) {
  final FractionallySizedBox box =
      tester.widget<FractionallySizedBox>(find.byType(FractionallySizedBox));
  return box.heightFactor!;
}

DraggableScrollableSheet _innerSheet(WidgetTester tester) =>
    tester.widget<DraggableScrollableSheet>(
      find.byType(DraggableScrollableSheet),
    );

void main() {
  group('RestageDraggableSheet', () {
    testWidgets('renders the child at the peek (initialChildSize) on mount',
        (WidgetTester tester) async {
      await tester.pumpWidget(const _Host(initialChildSize: 0.4));

      expect(find.byType(DraggableScrollableSheet), findsOneWidget);
      expect(find.text('body'), findsOneWidget);
      expect(_sheetSize(tester), closeTo(0.4, 0.001));
    });

    testWidgets('is persistent / non-closeable — bottoms out at minChildSize',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const _Host(initialChildSize: 0.5, minChildSize: 0.25),
      );

      // The wrapped sheet never asks a parent to close.
      expect(_innerSheet(tester).shouldCloseOnMinExtent, isFalse);

      // A hard downward drag does not dismiss it: it clamps at minChildSize
      // (a modal would slide away to nothing) and stays mounted.
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, 2000),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      expect(find.text('body'), findsOneWidget);
      expect(_sheetSize(tester), closeTo(0.25, 0.02));
    });

    testWidgets(
        'threads the drag controller into a SingleChildScrollView wrapping '
        'the child', (WidgetTester tester) async {
      await tester.pumpWidget(const _Host());

      final Finder scrollView = find.byType(SingleChildScrollView);
      expect(scrollView, findsOneWidget);
      // The child sits inside that scrollable.
      expect(
        find.descendant(of: scrollView, matching: find.text('body')),
        findsOneWidget,
      );
      // The wrapper owns a controller and threads it in (the whole sheet is
      // draggable — the canonical single-scrollable attach).
      expect(
        tester.widget<SingleChildScrollView>(scrollView).controller,
        isNotNull,
      );
    });

    testWidgets('expanded=true at mount shows the sheet at maxChildSize',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const _Host(startExpanded: true, maxChildSize: 0.9),
      );

      // Instant — no slide-in flash; the first frame is already at max.
      expect(_sheetSize(tester), closeTo(0.9, 0.001));
    });

    testWidgets('flipping expanded false→true animates toward maxChildSize',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const _Host(initialChildSize: 0.4, maxChildSize: 0.9),
      );
      expect(_sheetSize(tester), closeTo(0.4, 0.001));

      tester.state<_HostState>(find.byType(_Host)).setExpanded(true);
      await tester.pump(); // didUpdateWidget → animateTo kicks off

      // Sample a monotonic-increasing trace toward max.
      final double mid =
          await _pumpAndRead(tester, const Duration(milliseconds: 100));
      expect(mid, greaterThan(0.4));
      expect(mid, lessThan(0.9));

      await tester.pumpAndSettle();
      expect(_sheetSize(tester), closeTo(0.9, 0.001));
    });

    testWidgets(
        'flipping expanded true→false animates back to initialChildSize',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const _Host(
            startExpanded: true, initialChildSize: 0.4, maxChildSize: 0.9),
      );
      expect(_sheetSize(tester), closeTo(0.9, 0.001));

      tester.state<_HostState>(find.byType(_Host)).setExpanded(false);
      await tester.pump();

      final double mid =
          await _pumpAndRead(tester, const Duration(milliseconds: 100));
      expect(mid, lessThan(0.9));
      expect(mid, greaterThan(0.4));

      await tester.pumpAndSettle();
      expect(_sheetSize(tester), closeTo(0.4, 0.001));
    });

    testWidgets('expandDuration override is honored (longer than the default)',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _Host(
          initialChildSize: 0.4,
          maxChildSize: 0.9,
          expandDuration: const Duration(milliseconds: 400),
          expandCurve: Curves.linear,
        ),
      );

      tester.state<_HostState>(find.byType(_Host)).setExpanded(true);
      await tester.pump();
      // At 320ms a 400ms animation is still running; the framework default
      // (250ms) would already be settled at max — so this distinguishes them.
      final double atT =
          await _pumpAndRead(tester, const Duration(milliseconds: 320));
      expect(atT, lessThan(0.9));
      expect(atT, greaterThan(0.4));

      await tester.pumpAndSettle();
      expect(_sheetSize(tester), closeTo(0.9, 0.001));
    });

    testWidgets('passes the snap config through to the underlying sheet',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const _Host(snap: true, snapSizes: <double>[0.5, 0.75]),
      );
      final DraggableScrollableSheet sheet = _innerSheet(tester);
      expect(sheet.snap, isTrue);
      expect(sheet.snapSizes, <double>[0.5, 0.75]);
    });

    testWidgets('the sheet itself adds no scrim (it is in-layout, not a modal)',
        (WidgetTester tester) async {
      await tester.pumpWidget(const _Host());
      // The app route builds its own (non-dimming) ModalBarrier; what matters
      // is that the sheet's OWN subtree introduces no scrim/dimming overlay —
      // unlike a modal sheet, it floats in-layout over whatever is behind it.
      expect(
        find.descendant(
          of: find.byType(RestageDraggableSheet),
          matching: find.byType(ModalBarrier),
        ),
        findsNothing,
      );
    });
  });
}

/// Pumps [step] then returns the sheet size — for sampling an animation trace.
Future<double> _pumpAndRead(WidgetTester tester, Duration step) async {
  await tester.pump(step);
  return _sheetSize(tester);
}
