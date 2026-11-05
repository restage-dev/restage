import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_example/surfaces/guarded_features.dart';
import 'package:rfw/rfw.dart' show RemoteWidget;

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

  for (final (name, widget, shown, hidden)
      in <(String, Widget, List<String>, List<String>)>[
    (
      'no offer and no title',
      const GuardedFeaturesSurface(),
      ['Features', 'No offer', 'No title'],
      <String>[],
    ),
    (
      'an offer and a title',
      const GuardedFeaturesSurface(
        offer: GuardedOffer(['Sync', 'Backup']),
        title: 'Pro,Plus',
      ),
      ['Features', 'Sync', 'Backup', 'Pro', 'Plus'],
      ['No offer', 'No title'],
    ),
  ]) {
    testWidgets('the delivered paywall shows its guarded lists: $name',
        (tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: widget)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // The delivered design renders, not the compiled fallback.
      expect(find.byType(RemoteWidget), findsOneWidget);
      for (final text in shown) {
        expect(find.text(text), findsOneWidget, reason: text);
      }
      for (final text in hidden) {
        expect(find.text(text), findsNothing, reason: text);
      }
    });
  }
}
