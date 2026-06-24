import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_shared/restage_shared.dart'
    show FlowContentHash, FlowDocument, FlowDocumentCodec;
import 'package:rfw/formats.dart';

void main() {
  setUp(Restage.debugReset);

  testWidgets('generated first_run fixture traverses to typed completion',
      (tester) async {
    FirstRunResult? completed;
    final globalEvents = <RestageEvent>[];
    final sub = Restage.events.listen(globalEvents.add);
    addTearDown(sub.cancel);
    final document = _generatedDocument();
    final assets = _generatedAssets();

    _expectDescriptorMatchesDocument(document);
    _expectBlobHashesMatchDocument(document, assets);

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageOnboarding<FirstRunResult>(
        flow: FirstRunFlowDescriptor.ref,
        resolver: AssetFlowResolver(
          bundle: _GeneratedFixtureBundle(assets),
        ),
        actions: _generatedActions(),
        unavailable: FlowUnavailablePolicy.fallback(
          builder: fallbackBuilder,
        ),
        onComplete: (result) => completed = result,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('WelcomeScreen'), findsOneWidget);
    expect(find.text('AnalyticsTap'), findsOneWidget);

    await tester.tap(find.text('AnalyticsTap'));
    await tester.pumpAndSettle();

    final customEvent = globalEvents.whereType<FlowCustomEvent>().single;
    expect(customEvent.eventName, 'analyticsTap');
    expect(customEvent.fields, {'ctaId': 'primary'});

    await tester.tap(find.text('WelcomeScreen'));
    await tester.pumpAndSettle();

    expect(find.text('PermissionsScreen'), findsOneWidget);

    await tester.tap(find.text('PermissionsScreen'));
    await tester.pumpAndSettle();

    expect(find.text('ReadyScreen'), findsOneWidget);

    await tester.tap(find.text('ReadyScreen'));
    await tester.pumpAndSettle();

    expect(completed, const FirstRunResult(completed: true));
    expect(globalEvents.whereType<FlowUnavailable>(), isEmpty);
    expect(globalEvents.whereType<PaywallCustomEvent>(), isEmpty);
  });

  testWidgets('broken generated fixture emits FlowUnavailable through fallback',
      (tester) async {
    final globalEvents = <RestageEvent>[];
    final sub = Restage.events.listen(globalEvents.add);
    addTearDown(sub.cancel);
    final document = _generatedDocument();

    _expectDescriptorMatchesDocument(document);

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageOnboarding<FirstRunResult>(
        flow: FirstRunFlowDescriptor.ref,
        resolver: AssetFlowResolver(
          bundle: _GeneratedFixtureBundle.missingReadyBlob(),
        ),
        actions: _generatedActions(),
        unavailable: FlowUnavailablePolicy.fallback(
          builder: fallbackBuilder,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('fallback:missing_screen_blob'), findsOneWidget);
    expect(
      globalEvents.whereType<FlowUnavailable>().single.reason,
      'missing_screen_blob',
    );
    expect(globalEvents.whereType<PaywallCustomEvent>(), isEmpty);
  });
}

Widget fallbackBuilder(BuildContext context, FlowUnavailableError error) {
  return Text(
    'fallback:${error.reason}',
    textDirection: TextDirection.ltr,
  );
}

abstract final class FirstRunFlowDescriptor {
  static const ref = OnboardingFlowRef<FirstRunResult>(
    id: 'first_run',
    version: 1,
    minClient: 3,
    decodeResult: _decodeResult,
  );

  static FirstRunResult _decodeResult(Map<String, Object?> result) {
    if (result.length != 1 || !result.containsKey('completed')) {
      throw const FormatException('Unexpected first_run result shape.');
    }
    final completed = result['completed'];
    if (completed is! bool) {
      throw const FormatException('Expected completed to be a bool.');
    }
    return FirstRunResult(completed: completed);
  }
}

final class FirstRunResult {
  const FirstRunResult({required this.completed});

  final bool completed;

  @override
  bool operator ==(Object other) {
    return other is FirstRunResult && other.completed == completed;
  }

  @override
  int get hashCode => completed.hashCode;
}

final class NotificationResult {
  const NotificationResult({required this.granted});

  final bool granted;
}

final class FirstRunActions implements FlowActionRegistry {
  FirstRunActions({
    required FlowActionHandler<void, NotificationResult> requestNotifications,
  }) : flowActionBindings =
            Map<String, FlowActionBinding<dynamic, dynamic>>.unmodifiable({
          'requestNotifications': FlowActionBinding<void, NotificationResult>(
            descriptor: requestNotificationsDescriptor,
            actionName: requestNotificationsDescriptor.actionName,
            contractVersion: requestNotificationsDescriptor.contractVersion,
            argsSchema: requestNotificationsDescriptor.argsSchema,
            resultSchema: requestNotificationsDescriptor.resultSchema,
            minClient: requestNotificationsDescriptor.minClient,
            idempotent: requestNotificationsDescriptor.idempotent,
            handler: requestNotifications,
            decodeArgs: (_) {},
            encodeResult: (value) => {'granted': value.granted},
          ),
        });

  @override
  final Map<String, FlowActionBinding<dynamic, dynamic>> flowActionBindings;

  static final FlowActionDescriptor<void, NotificationResult>
      requestNotificationsDescriptor =
      FlowActionDescriptor<void, NotificationResult>(
    actionName: 'requestNotifications',
    contractVersion: 1,
    argsSchema: const FlowActionSchema.object({}),
    resultSchema: const FlowActionSchema.object({
      'granted': FlowActionSchemaField(
        required: true,
        schema: FlowActionSchema.bool(),
      ),
    }),
    minClient: 3,
    idempotent: false,
  );
}

final class _GeneratedFixtureBundle extends CachingAssetBundle {
  _GeneratedFixtureBundle(Map<String, Uint8List> assets) : _assets = assets;

  factory _GeneratedFixtureBundle.missingReadyBlob() {
    return _GeneratedFixtureBundle(
      _generatedAssets()..remove('assets/onboarding/screens/ready.rfw'),
    );
  }

  final Map<String, Uint8List> _assets;

  @override
  Future<ByteData> load(String key) async {
    final bytes = _assets[key];
    if (bytes == null) {
      throw FlutterError('Unable to load asset: $key');
    }
    return ByteData.view(Uint8List.fromList(bytes).buffer);
  }
}

Map<String, Uint8List> _generatedAssets() {
  return {
    'assets/onboarding/flows/first_run.flow.json': Uint8List.fromList(
      utf8.encode(_readSharedFirstRunGolden()),
    ),
    'assets/onboarding/screens/welcome.rfw': _generatedBlob(
      '''
import restage.core;
import restage.material;
import restage.cupertino;

widget OnboardingScreen = Center(
  child: Column(
    mainAxisAlignment: "center",
    children: [
      ElevatedButton(
        onPressed: event "analyticsTap" { ctaId: "primary", secret: "internal" },
        child: Text(text: "AnalyticsTap"),
      ),
      ElevatedButton(onPressed: event "next" {}, child: Text(text: "WelcomeScreen")),
    ],
  ),
);
''',
    ),
    'assets/onboarding/screens/permissions.rfw': _generatedBlob(
      '''
import restage.core;
import restage.material;
import restage.cupertino;

widget OnboardingScreen = Center(child: ElevatedButton(onPressed: event "next" {}, child: Text(text: "PermissionsScreen")));
''',
    ),
    'assets/onboarding/screens/ready.rfw': _generatedBlob(
      '''
import restage.core;
import restage.material;
import restage.cupertino;

widget OnboardingScreen = Center(child: ElevatedButton(onPressed: event "start" {}, child: Text(text: "ReadyScreen")));
''',
    ),
  };
}

Uint8List _generatedBlob(String source) {
  return Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));
}

FlowDocument _generatedDocument() {
  return FlowDocumentCodec.decodeJson(_readSharedFirstRunGolden());
}

void _expectDescriptorMatchesDocument(FlowDocument document) {
  expect(FirstRunFlowDescriptor.ref.id, document.flow);
  expect(FirstRunFlowDescriptor.ref.version, document.version);
  expect(FirstRunFlowDescriptor.ref.minClient, document.minClient);
  final action = document.actions['requestNotifications'];
  expect(action?.actionName,
      FirstRunActions.requestNotificationsDescriptor.actionName);
  expect(
    action?.resultSchemaHash,
    FirstRunActions.requestNotificationsDescriptor.resultSchemaHash,
  );
}

FirstRunActions _generatedActions() {
  return FirstRunActions(
    requestNotifications: (_, __) => const NotificationResult(granted: true),
  );
}

void _expectBlobHashesMatchDocument(
  FlowDocument document,
  Map<String, Uint8List> assets,
) {
  for (final entry in document.screenArtifacts.entries) {
    final path = 'assets/onboarding/screens/${entry.value.path}';
    final bytes = assets[path];
    expect(bytes, isNotNull, reason: entry.key);
    expect(
      FlowContentHash.compute(bytes!),
      entry.value.contentHash,
      reason: entry.key,
    );
  }
}

String _readSharedFirstRunGolden() {
  const relativePath =
      'packages/restage_shared/test/flow_document/goldens/first_run.flow.json';
  var directory = Directory.current.absolute;
  while (true) {
    final candidate = File('${directory.path}/$relativePath');
    if (candidate.existsSync()) {
      return candidate.readAsStringSync();
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError(
        'Could not find $relativePath from ${Directory.current}',
      );
    }
    directory = parent;
  }
}
