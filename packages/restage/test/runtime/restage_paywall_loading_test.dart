import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';

class _PendingResolver implements VariantResolver {
  final completer = Completer<ResolvedVariant>();
  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) =>
      completer.future;
}

void main() {
  setUp(() => Restage.debugReset());

  testWidgets('default loading state is SizedBox.shrink', (tester) async {
    final resolver = _PendingResolver();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RestagePaywall(id: 'pro_upgrade', resolver: resolver),
      ),
    );
    expect(find.byType(SizedBox), findsOneWidget);
  });

  testWidgets('loadingBuilder override is shown while pending', (tester) async {
    final resolver = _PendingResolver();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RestagePaywall(
          id: 'pro_upgrade',
          resolver: resolver,
          loadingBuilder: (_) => const Text('Loading...'),
        ),
      ),
    );
    expect(find.text('Loading...'), findsOneWidget);
  });
}
