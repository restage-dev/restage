import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/public_api/paywall_subclass.dart';

void main() {
  testWidgets('a paywall subclass can own a BuildContext context getter', (
    tester,
  ) async {
    late BuildContext hostBuildContext;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          hostBuildContext = context;
          return const SizedBox.shrink();
        },
      ),
    );

    final paywall = ContextAwarePaywall(hostBuildContext: hostBuildContext);
    expect(paywall.context, same(hostBuildContext));
  });
}
