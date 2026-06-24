import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';

/// RestageStagger reveals a vertical list of children with a cascading spring
/// entrance — each child plays RestageMotion's entrance, offset by
/// delayBetween * index. Another genuine gap over the implicit Animated* suite.
void main() {
  testWidgets('staggers each child by delayBetween * index', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: RestageStagger(
          delayBetween: Duration(milliseconds: 60),
          children: [Text('a'), Text('b'), Text('c')],
        ),
      ),
    );
    final motions =
        tester.widgetList<RestageMotion>(find.byType(RestageMotion)).toList();
    expect(motions.length, 3);
    expect(motions[0].delay, Duration.zero);
    expect(motions[1].delay, const Duration(milliseconds: 60));
    expect(motions[2].delay, const Duration(milliseconds: 120));
  });

  testWidgets('renders all children and the entrance from-state passes through',
      (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: RestageStagger(
          spring: RestageSpring.bouncy,
          fromOffset: Offset(0, 16),
          children: [Text('a'), Text('b')],
        ),
      ),
    );
    expect(find.text('a'), findsOneWidget);
    expect(find.text('b'), findsOneWidget);
    final first =
        tester.widgetList<RestageMotion>(find.byType(RestageMotion)).first;
    expect(first.spring, RestageSpring.bouncy);
    expect(first.fromOffset, const Offset(0, 16));
    await tester.pumpAndSettle(const Duration(seconds: 2));
  });

  testWidgets('a huge delayBetween does not overflow the per-child delay',
      (tester) async {
    // A pathological wire delayBetween multiplied by the child index would
    // otherwise overflow Int64 to a negative Duration, making a later child
    // start immediately and breaking the stagger order. The step is clamped.
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: RestageStagger(
          delayBetween: Duration(microseconds: 5000000000000000000),
          children: [Text('a'), Text('b'), Text('c')],
        ),
      ),
    );
    final motions =
        tester.widgetList<RestageMotion>(find.byType(RestageMotion)).toList();
    // Delays stay non-negative and non-decreasing — no overflow to negative.
    expect(motions[0].delay, Duration.zero);
    expect(motions[1].delay! >= Duration.zero, isTrue);
    expect(motions[2].delay! >= motions[1].delay!, isTrue);
  });

  testWidgets('an empty children list renders nothing and does not throw',
      (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: RestageStagger(children: []),
      ),
    );
    expect(find.byType(RestageMotion), findsNothing);
  });
}
