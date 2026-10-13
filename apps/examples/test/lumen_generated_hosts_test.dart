import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_example/onboarding/lumen_onboarding_demo.dart';
import 'package:restage_example/surfaces/lumen_cancel.dart';
import 'package:restage_example/surfaces/lumen_cancel_demo.dart';
import 'package:restage_example/surfaces/lumen_trial_ending_demo.dart';

import '_support/support_directory_channel.dart';

final class _NoAssets extends CachingAssetBundle {
  final reads = <String>[];

  @override
  Future<ByteData> load(String key) async {
    reads.add(key);
    throw FlutterError('No assets in this app: $key');
  }
}

void main() {
  useSupportDirectoryChannel();
  late _NoAssets bundle;

  setUp(() async {
    await Restage.debugResetAndWait();
    bundle = _NoAssets();
    Restage.configure(flowResolver: AssetFlowResolver(bundle: bundle));
  });

  Future<void> open(WidgetTester tester, Widget surface) async {
    tester.view.physicalSize = const Size(800, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: surface));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets('onboarding completes through its embedded offer without assets',
      (tester) async {
    await open(tester, const LumenOnboardingDemo());
    await tap(tester, 'Begin');
    await tap(tester, "I'm new to meditation");
    await tap(tester, 'Sleep better');
    await tap(tester, 'Enable daily reminders');
    await tap(tester, 'See your plan');
    await tap(tester, 'Start 14 days free');
    expect(find.text('Onboarding complete'), findsOneWidget);
    expect(bundle.reads, isNotEmpty);
  });

  testWidgets('message opens its offer and completes without assets',
      (tester) async {
    await open(tester, const LumenTrialEndingDemo());
    await tap(tester, 'See the offer');
    await tap(tester, 'Start 14 days free');
    expect(find.text('Message dismissed'), findsOneWidget);
    expect(bundle.reads, isNotEmpty);
  });

  testWidgets('message can go back from its offer and dismiss without assets',
      (tester) async {
    await open(tester, const LumenTrialEndingDemo());
    await tap(tester, 'See the offer');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Keep the calm going'), findsOneWidget);
    await tap(tester, 'Maybe later');
    expect(find.text('Message dismissed'), findsOneWidget);
  });

  testWidgets('survey returns its answer and note without assets',
      (tester) async {
    await open(tester, const LumenCancelDemo());
    await tap(tester, 'It costs too much');
    await tester.enterText(find.byType(TextField), 'A smaller plan would help');
    await tester.pump();
    await tap(tester, 'Send');
    await tap(tester, 'Done');
    expect(
      find.text('Thanks — you told us: too_expensive\n'
          'Note: A smaller plan would help'),
      findsOneWidget,
    );
    expect(bundle.reads, isNotEmpty);
  });

  testWidgets('survey skip completes without an answer', (tester) async {
    final events = <RestageEvent>[];
    final subscription = Restage.events.listen(events.add);
    addTearDown(subscription.cancel);
    await open(tester, const LumenCancelDemo());
    expect(find.byType(LumenCancelReasonScreen), findsOneWidget);
    await tap(tester, 'Skip');
    expect(find.text('Survey skipped'), findsOneWidget);
    expect(events.whereType<SurveyQuestionResponded>(), isEmpty);
  });

  testWidgets('bundled survey skip completes without an answer',
      (tester) async {
    Restage.configure(flowResolver: const AssetFlowResolver());
    final events = <RestageEvent>[];
    final subscription = Restage.events.listen(events.add);
    addTearDown(subscription.cancel);
    await open(tester, const LumenCancelDemo());
    expect(find.text('Why are you\nleaving?'), findsOneWidget);
    expect(find.byType(LumenCancelReasonScreen), findsNothing);
    await tap(tester, 'Skip');
    expect(find.text('Survey skipped'), findsOneWidget);
    expect(events.whereType<SurveyQuestionResponded>(), isEmpty);
  });
}
