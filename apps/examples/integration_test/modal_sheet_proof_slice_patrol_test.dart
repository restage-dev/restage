import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';
import 'package:restage_material/restage_material.dart';

/// Proof slice for `RestageModalSheet` — drives the load-bearing
/// interactions (open → drag-to-dismiss → re-open → scrim-tap) and holds
/// each state on screen long enough for the visual gate to capture it as
/// a distinct frame.
///
/// Run with `patrol test --device chrome --web-video=on` to record the
/// slide-in, the rounded-top sheet over the scrim, the drag-down
/// dismissal, and the scrim-tap dismissal.
///
/// What to look for in the frames: a bottom sheet with rounded top
/// corners flush to the bottom edge, a visible drag handle, a dimmed
/// full-surface scrim behind it; the sheet following the finger on a
/// downward drag and animating away; the surface fully interactive again
/// once closed.
const _dwell = Duration(milliseconds: 1500);

void main() {
  patrolTest(
    'RestageModalSheet — open, drag-to-dismiss, scrim-tap',
    ($) async {
      await $.pumpWidgetAndSettle(const _ModalSheetDemoApp());

      // State 1 — closed: the trigger is visible, no sheet.
      expect($('Show plans'), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      await Future<void>.delayed(_dwell);

      // State 2 — open: tap the trigger, the sheet slides up over the scrim.
      await $('Show plans').tap();
      await $.pumpAndSettle();
      expect($(const Key('sheetTitle')), findsOneWidget);
      await Future<void>.delayed(_dwell);

      // State 3 — drag-to-dismiss: fling the sheet downward past the
      // threshold; it follows the finger and animates away.
      await $.tester.fling(
        find.byType(BottomSheet),
        const Offset(0, 400),
        1200,
      );
      await $.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      await Future<void>.delayed(_dwell);

      // State 4 — re-open, then dismiss by tapping the scrim.
      await $('Show plans').tap();
      await $.pumpAndSettle();
      expect($(const Key('sheetTitle')), findsOneWidget);
      await Future<void>.delayed(_dwell);

      await $.tester.tapAt(const Offset(10, 10)); // tap the scrim
      await $.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      await Future<void>.delayed(_dwell);
    },
  );
}

/// A minimal host that drives [RestageModalSheet] from a state flag,
/// exactly as a paywall binds the sheet's `open` to local state.
class _ModalSheetDemoApp extends StatefulWidget {
  const _ModalSheetDemoApp();

  @override
  State<_ModalSheetDemoApp> createState() => _ModalSheetDemoAppState();
}

class _ModalSheetDemoAppState extends State<_ModalSheetDemoApp> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      home: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Center(
              child: FilledButton(
                onPressed: () => setState(() => _open = true),
                child: const Text('Show plans'),
              ),
            ),
            RestageModalSheet(
              open: _open,
              showDragHandle: true,
              onSheetDismissed: () => setState(() => _open = false),
              child: const _SheetBody(),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetBody extends StatelessWidget {
  const _SheetBody();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Choose your plan',
            key: const Key('sheetTitle'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: colors.onSurface,
            ),
          ),
          const SizedBox(height: 20),
          _PlanRow(label: 'Annual · Save 40%', price: r'$59.99/yr'),
          const SizedBox(height: 12),
          _PlanRow(label: 'Monthly', price: r'$7.99/mo'),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () {},
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text('Start free trial'),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanRow extends StatelessWidget {
  const _PlanRow({required this.label, required this.price});

  final String label;
  final String price;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: colors.onSurface,
              ),
            ),
          ),
          Text(
            price,
            style: TextStyle(fontSize: 15, color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
