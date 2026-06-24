// Some cases shell out to `dart analyze` (cold-start resolution); give them
// headroom over the 30s default so they don't flake under load.
@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';

abstract final class WelcomeScreen {
  static const next = OnboardingEvent<void>('next');
  static const age = OnboardingEvent<int>('age');
}

void main() {
  test('OnboardingEvent stores the event id and type', () {
    const event = OnboardingEvent<void>('next');

    expect(event.id, 'next');
    expect(event, isA<OnboardingEvent<void>>());
  });

  testWidgets('onboardingEvent dispatches through the active dispatcher',
      (tester) async {
    String? receivedEventId;
    Object? receivedValue;
    VoidCallback? captured;

    await tester.pumpWidget(RestageOnboardingEventDispatcher(
      onEvent: (eventId, value) {
        receivedEventId = eventId;
        receivedValue = value;
      },
      child: Builder(builder: (_) {
        captured = onboardingEvent(WelcomeScreen.next);
        return const SizedBox();
      }),
    ));

    captured!();

    expect(receivedEventId, 'next');
    expect(receivedValue, isNull);
  });

  testWidgets('onboardingEvent dispatches a typed payload', (tester) async {
    String? receivedEventId;
    Object? receivedValue;
    VoidCallback? captured;

    await tester.pumpWidget(RestageOnboardingEventDispatcher(
      onEvent: (eventId, value) {
        receivedEventId = eventId;
        receivedValue = value;
      },
      child: Builder(builder: (_) {
        captured = onboardingEvent(WelcomeScreen.age, 42);
        return const SizedBox();
      }),
    ));

    captured!();

    expect(receivedEventId, 'age');
    expect(receivedValue, 42);
  });

  test('onboardingEvent rejects the wrong payload type statically', () async {
    final result = await _analyzeNegativeSample(
      fileName: 'wrong_onboarding_event_payload.dart',
      source: '''
import 'package:restage/restage.dart';

void main() {
  const age = OnboardingEvent<int>('age');
  onboardingEvent(age, 'forty-two');
}
''',
    );

    expect(result.exitCode, isNot(0), reason: result.output);
    expect(result.output, contains('String'));
    expect(result.output, contains('int'));
  });

  testWidgets(
      'onboardingEvent invoked with no dispatcher mounted asserts/reports',
      (tester) async {
    final callback = onboardingEvent(WelcomeScreen.next);

    expect(callback, isA<VoidCallback>());
    expect(callback, throwsAssertionError);
  });

  testWidgets('onboardingEvent captures dispatcher at build time, not at tap',
      (tester) async {
    String? routedTo;
    VoidCallback? captured;

    await tester.pumpWidget(RestageOnboardingEventDispatcher(
      onEvent: (eventId, value) => routedTo = 'A',
      child: Builder(builder: (_) {
        captured = onboardingEvent(WelcomeScreen.next);
        return const SizedBox();
      }),
    ));

    await tester.pumpWidget(RestageOnboardingEventDispatcher(
      onEvent: (eventId, value) => routedTo = 'B',
      child: const SizedBox(),
    ));

    captured!();

    expect(routedTo, 'A');
  });
}

Future<_AnalyzeResult> _analyzeNegativeSample({
  required String fileName,
  required String source,
}) async {
  final negativeDir = Directory('.dart_tool/restage_negative_tests');
  negativeDir.createSync(recursive: true);
  final negativeFile = File('${negativeDir.path}/$fileName');
  negativeFile.writeAsStringSync(source);
  addTearDown(() {
    if (negativeFile.existsSync()) {
      negativeFile.deleteSync();
    }
  });

  final result = await Process.run(
    'dart',
    <String>['analyze', negativeFile.path],
    workingDirectory: Directory.current.path,
  );

  return _AnalyzeResult(
    exitCode: result.exitCode,
    output: '${result.stdout}\n${result.stderr}',
  );
}

final class _AnalyzeResult {
  const _AnalyzeResult({
    required this.exitCode,
    required this.output,
  });

  final int exitCode;
  final String output;
}
