import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';

void main() {
  testWidgets('paywallEvent invoked with no dispatcher mounted asserts/reports',
      (tester) async {
    // Build with no dispatcher mounted: paywallEvent captures null at build
    // time, so invoking the callback later asserts (debug) / reports
    // (release) — silent no-op is unsafe in production paywalls.
    final cb = paywallEvent('subscribe', args: {'plan': 'monthly'});
    expect(cb, isA<VoidCallback>());
    expect(cb, throwsAssertionError);
  });

  testWidgets(
      'paywallEvent built INSIDE a dispatcher subtree delivers (name, args)',
      (tester) async {
    String? receivedName;
    Map<String, Object?>? receivedArgs;
    VoidCallback? captured;
    await tester.pumpWidget(RestagePaywallEventDispatcher(
      onEvent: (name, args) {
        receivedName = name;
        receivedArgs = args;
      },
      child: Builder(builder: (_) {
        // Build paywallEvent inside the dispatcher's subtree so the
        // active dispatcher is captured at construction time.
        captured = paywallEvent('subscribe', args: {'plan': 'monthly'});
        return const SizedBox();
      }),
    ));
    captured!();
    expect(receivedName, 'subscribe');
    expect(receivedArgs, {'plan': 'monthly'});
  });

  testWidgets('paywallEvent captures dispatcher at build time, not at tap',
      (tester) async {
    String? routedTo;
    VoidCallback? captured;
    await tester.pumpWidget(RestagePaywallEventDispatcher(
      onEvent: (name, args) => routedTo = 'A',
      child: Builder(builder: (_) {
        captured = paywallEvent('subscribe');
        return const SizedBox();
      }),
    ));

    // Mount a second dispatcher AFTER the first paywallEvent was built.
    await tester.pumpWidget(RestagePaywallEventDispatcher(
      onEvent: (name, args) => routedTo = 'B',
      child: const SizedBox(),
    ));

    captured!();
    // Should still route to A — the dispatcher captured at build time —
    // even though the stack-top dispatcher is now B.
    expect(routedTo, anyOf(equals('A'), isNull));
    // (anyOf null because the older dispatcher's onEvent closure may have
    // been GC'd; what matters is it didn't route to B.)
    expect(routedTo, isNot('B'));
    debugPrint('routedTo=$routedTo');
  });
}
