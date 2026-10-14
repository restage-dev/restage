import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_example/onboarding/lumen_onboarding_demo.dart';
import 'package:restage_example/surfaces/lumen_trial_ending_demo.dart';
import 'package:restage_example/user_factories.g.dart';

import '_support/support_directory_channel.dart';

void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Records the custom events the flow hands the app.
List<String> _recordCustomEvents() {
  final names = <String>[];
  final subscription = Restage.events.listen((event) {
    if (event is FlowCustomEvent) names.add(event.eventName);
  });
  addTearDown(() => unawaited(subscription.cancel()));
  return names;
}

Future<void> _tapEachFooterLink(WidgetTester tester) async {
  for (final label in ['Restore', 'Terms', 'Privacy']) {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }
}

void main() {
  useSupportDirectoryChannel();

  setUp(() async {
    await Restage.debugResetAndWait();
    Restage.configure(
      apiKey: 'rs_pk_test',
      resolver: const AssetVariantResolver(),
    );
    registerRestageWidgets();
  });

  testWidgets('the onboarding offer hands its footer links to the app',
      (tester) async {
    _useTallSurface(tester);
    final events = _recordCustomEvents();
    await tester.pumpWidget(const MaterialApp(home: LumenOnboardingDemo()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Begin'));
    await tester.pumpAndSettle();
    await tester.tap(find.text("I'm new to meditation"));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Just curious'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('See your plan'));
    await tester.pumpAndSettle();
    expect(find.text('Sleep deeper\ntonight.'), findsOneWidget);

    await _tapEachFooterLink(tester);

    expect(events, ['restore_purchases', 'terms', 'privacy']);
    expect(find.text('Sleep deeper\ntonight.'), findsOneWidget);
  });

  testWidgets('the trial-ending offer hands its footer links to the app',
      (tester) async {
    _useTallSurface(tester);
    final events = _recordCustomEvents();
    await tester.pumpWidget(const MaterialApp(home: LumenTrialEndingDemo()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('See the offer'));
    await tester.pumpAndSettle();
    expect(find.text('Sleep deeper\ntonight.'), findsOneWidget);

    await _tapEachFooterLink(tester);

    expect(events, ['restore_purchases', 'terms', 'privacy']);
    expect(find.text('Sleep deeper\ntonight.'), findsOneWidget);
  });
}
