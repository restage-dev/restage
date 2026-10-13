import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_example/onboarding/bare_surface_demo.dart';

import '_support/support_directory_channel.dart';

void main() {
  useSupportDirectoryChannel();

  setUp(() async {
    await Restage.debugResetAndWait();
    Restage.configure(
      apiKey: 'rs_pk_test',
      resolver: const AssetVariantResolver(),
    );
  });

  testWidgets('renders the delivered bare surface with neutral copy',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: BareSurfaceDemo()));
    await tester.pumpAndSettle();

    expect(find.text('Bare surface'), findsOneWidget);
    expect(
      find.textContaining(
        RegExp('onboarding|paywall', caseSensitive: false),
      ),
      findsNothing,
    );
  });
}
