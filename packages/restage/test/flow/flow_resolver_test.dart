import 'dart:convert';
import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_shared/restage_shared.dart';

void main() {
  const flowRef = OnboardingFlowRef<Map<String, Object?>>(
    id: 'first_run',
    version: 1,
    minClient: 3,
    decodeResult: _decodeMapResult,
  );

  setUp(Restage.debugReset);

  test('loads and validates a bundled flow with immutable exact screen bytes',
      () async {
    final screenBytes = Uint8List.fromList([1, 2, 3, 255]);
    final bundle = _FlowAssetBundle.withFlow(
      flowRef,
      _validDocument(screenBytes: screenBytes),
      screenBytes: screenBytes,
    );
    const resolver = AssetFlowResolver(bundle: null);
    final injectedResolver = AssetFlowResolver(bundle: bundle);

    expect(resolver, isA<AssetFlowResolver>());

    final resolved = await injectedResolver.resolve(flowRef);

    expect(bundle.loadedKeys, [
      'assets/onboarding/flows/first_run.flow.json',
      'assets/onboarding/screens/welcome.rfw',
    ]);
    expect(resolved.cacheHit, isFalse);
    expect(resolved.document.flow, flowRef.id);
    expect(resolved.document.version, flowRef.version);
    expect(resolved.screenBlobs.keys, ['welcome']);
    expect(resolved.screenBlobs['welcome'], screenBytes);
    expect(
      () => resolved.document.screenArtifacts.clear(),
      throwsUnsupportedError,
    );
    expect(
      () => resolved.document.states.clear(),
      throwsUnsupportedError,
    );
    expect(
      () {
        final state = resolved.document.states['welcome'] as ScreenFlowState;
        state.on.clear();
      },
      throwsUnsupportedError,
    );
    expect(
      () => resolved.screenBlobs['welcome']![0] = 9,
      throwsUnsupportedError,
    );
    expect(
      () => resolved.screenBlobs['extra'] = Uint8List(0),
      throwsUnsupportedError,
    );
  });

  test('freezes nested result JSON values in resolved documents', () async {
    final screenBytes = Uint8List.fromList([1, 2, 3, 255]);
    final bundle = _FlowAssetBundle.withFlow(
      flowRef,
      _validDocument(
        screenBytes: screenBytes,
        states: const {
          'welcome': ScreenFlowState(
            screen: 'welcome',
            on: {'next': FlowTransition.goto('done')},
          ),
          'done': EndFlowState(
            result: {
              'profile': {'completed': true},
              'steps': [1, 2, 3],
            },
          ),
        },
      ),
      screenBytes: screenBytes,
    );
    final resolver = AssetFlowResolver(bundle: bundle);

    final resolved = await resolver.resolve(flowRef);
    final end = resolved.document.states['done'] as EndFlowState;
    final profile = end.result['profile'] as Map<String, Object?>;
    final steps = end.result['steps'] as List<Object?>;

    expect(
      () => profile['completed'] = false,
      throwsUnsupportedError,
    );
    expect(
      () => steps.add(4),
      throwsUnsupportedError,
    );
  });

  test('ResolvedFlow constructor freezes caller-provided document graphs', () {
    final screenBytes = Uint8List.fromList([1, 2, 3, 255]);
    final actions = {
      'requestNotifications': FlowActionContract(
        actionName: 'requestNotifications',
        contractVersion: 1,
        argsSchema: _emptyArgsSchema,
        resultSchema: _boolResultSchema,
        minClient: 3,
        idempotent: false,
      ),
    };
    final document = _validDocument(
      screenBytes: screenBytes,
      actions: actions,
      states: {
        'welcome': ScreenFlowState(
          screen: 'welcome',
          on: {'next': const FlowTransition.goto('done')},
        ),
        'done': EndFlowState(
          result: {
            'profile': {'completed': true},
            'steps': [1, 2, 3],
          },
        ),
      },
    );

    final resolved = ResolvedFlow(
      document: document,
      screenBlobs: {'welcome': screenBytes},
      cacheHit: false,
    );
    final welcome = resolved.document.states['welcome'] as ScreenFlowState;
    final end = resolved.document.states['done'] as EndFlowState;
    final profile = end.result['profile'] as Map<String, Object?>;
    final steps = end.result['steps'] as List<Object?>;

    actions['requestNotifications'] = FlowActionContract(
      actionName: 'requestNotifications',
      contractVersion: 2,
      argsSchema: _emptyArgsSchema,
      resultSchema: _boolResultSchema,
      minClient: 3,
      idempotent: false,
    );

    expect(
        resolved.document.actions['requestNotifications']?.contractVersion, 1);
    expect(
      () => resolved.document.actions.clear(),
      throwsUnsupportedError,
    );
    expect(
      () => resolved.document.screenArtifacts.clear(),
      throwsUnsupportedError,
    );
    expect(
      () => resolved.document.states.clear(),
      throwsUnsupportedError,
    );
    expect(
      () => welcome.on.clear(),
      throwsUnsupportedError,
    );
    expect(
      () => profile['completed'] = false,
      throwsUnsupportedError,
    );
    expect(
      () => steps.add(4),
      throwsUnsupportedError,
    );
  });

  test('cache hits only when document bytes and artifact hashes are unchanged',
      () async {
    final firstBytes = Uint8List.fromList([1, 2, 3]);
    final secondBytes = Uint8List.fromList([4, 5, 6]);
    final firstDocument = _validDocument(screenBytes: firstBytes);
    final secondDocument = _validDocument(screenBytes: secondBytes);
    final bundle = _FlowAssetBundle.withFlow(
      flowRef,
      firstDocument,
      screenBytes: firstBytes,
    );
    final resolver = AssetFlowResolver(bundle: bundle);

    expect((await resolver.resolve(flowRef)).cacheHit, isFalse);
    expect((await resolver.resolve(flowRef)).cacheHit, isTrue);

    bundle.writeFlowJson(
      flowRef,
      '${FlowDocumentCodec.encodePrettyJson(firstDocument)}\n',
    );
    expect((await resolver.resolve(flowRef)).cacheHit, isFalse);
    expect((await resolver.resolve(flowRef)).cacheHit, isTrue);

    bundle.writeFlow(flowRef, secondDocument);
    bundle.writeScreen('welcome.rfw', secondBytes);
    expect((await resolver.resolve(flowRef)).cacheHit, isFalse);
  });

  test('cache hits still verify current screen blob bytes before returning',
      () async {
    final screenBytes = Uint8List.fromList([1, 2, 3]);
    final document = _validDocument(screenBytes: screenBytes);
    final bundle = _FlowAssetBundle.withFlow(
      flowRef,
      document,
      screenBytes: screenBytes,
    );
    final resolver = AssetFlowResolver(bundle: bundle);

    expect((await resolver.resolve(flowRef)).cacheHit, isFalse);
    expect((await resolver.resolve(flowRef)).cacheHit, isTrue);

    bundle.removeScreen('welcome.rfw');
    await expectLater(
      resolver.resolve(flowRef),
      throwsA(_flowUnavailable('missing_screen_blob')),
    );

    bundle.writeScreen('welcome.rfw', Uint8List.fromList([9, 9, 9]));
    await expectLater(
      resolver.resolve(flowRef),
      throwsA(_flowUnavailable('hash_mismatch')),
    );
  });

  test('fails closed when the flow JSON asset is missing', () async {
    final resolver = AssetFlowResolver(bundle: _FlowAssetBundle());

    await expectLater(
      resolver.resolve(flowRef),
      throwsA(_flowUnavailable('missing_flow_json')),
    );
  });

  test('fails closed when the flow JSON asset is malformed', () async {
    final bundle = _FlowAssetBundle()..writeFlowJson(flowRef, '{not json');
    final resolver = AssetFlowResolver(bundle: bundle);

    await expectLater(
      resolver.resolve(flowRef),
      throwsA(_flowUnavailable('decode_failed')),
    );
  });

  test('fails closed when the flow JSON id does not match the descriptor',
      () async {
    final screenBytes = Uint8List.fromList([1, 2, 3]);
    final bundle = _FlowAssetBundle.withFlow(
      flowRef,
      _validDocument(flow: 'other_flow', screenBytes: screenBytes),
      screenBytes: screenBytes,
    );
    final resolver = AssetFlowResolver(bundle: bundle);

    await expectLater(
      resolver.resolve(flowRef),
      throwsA(_flowUnavailable('flow_mismatch')),
    );
  });

  test('fails closed when the flow JSON version does not match the descriptor',
      () async {
    final screenBytes = Uint8List.fromList([1, 2, 3]);
    final bundle = _FlowAssetBundle.withFlow(
      flowRef,
      _validDocument(version: 2, screenBytes: screenBytes),
      screenBytes: screenBytes,
    );
    final resolver = AssetFlowResolver(bundle: bundle);

    await expectLater(
      resolver.resolve(flowRef),
      throwsA(_flowUnavailable('version_mismatch')),
    );
  });

  test('fails closed when a screen blob asset is missing', () async {
    final screenBytes = Uint8List.fromList([1, 2, 3]);
    final bundle = _FlowAssetBundle()
      ..writeFlow(flowRef, _validDocument(screenBytes: screenBytes));
    final resolver = AssetFlowResolver(bundle: bundle);

    await expectLater(
      resolver.resolve(flowRef),
      throwsA(_flowUnavailable('missing_screen_blob')),
    );
  });

  test('fails closed when a screen blob hash does not match', () async {
    final bundle = _FlowAssetBundle.withFlow(
      flowRef,
      _validDocument(screenBytes: Uint8List.fromList([1, 2, 3])),
      screenBytes: Uint8List.fromList([9, 9, 9]),
    );
    final resolver = AssetFlowResolver(bundle: bundle);

    await expectLater(
      resolver.resolve(flowRef),
      throwsA(_flowUnavailable('hash_mismatch')),
    );
  });

  test('fails closed for unsupported document schemaVersion', () async {
    final screenBytes = Uint8List.fromList([1, 2, 3]);
    final bundle = _FlowAssetBundle.withFlow(
      flowRef,
      _validDocument(screenBytes: screenBytes, schemaVersion: 2),
      screenBytes: screenBytes,
    );
    final resolver = AssetFlowResolver(bundle: bundle);

    await expectLater(
      resolver.resolve(flowRef),
      throwsA(_flowUnavailable('unsupported_schema_version')),
    );
  });

  test('fails closed for unsupported screen artifact schemaVersion', () async {
    final screenBytes = Uint8List.fromList([1, 2, 3]);
    final bundle = _FlowAssetBundle.withFlow(
      flowRef,
      _validDocument(screenBytes: screenBytes, artifactSchemaVersion: 2),
      screenBytes: screenBytes,
    );
    final resolver = AssetFlowResolver(bundle: bundle);

    await expectLater(
      resolver.resolve(flowRef),
      throwsA(_flowUnavailable('unsupported_schema_version')),
    );
  });

  test('fails closed for unsupported document minClient', () async {
    final screenBytes = Uint8List.fromList([1, 2, 3]);
    final bundle = _FlowAssetBundle.withFlow(
      flowRef,
      _validDocument(screenBytes: screenBytes, minClient: 4),
      screenBytes: screenBytes,
    );
    final resolver = AssetFlowResolver(bundle: bundle);

    await expectLater(
      resolver.resolve(flowRef),
      throwsA(_flowUnavailable('unsupported_min_client')),
    );
  });

  test('fails closed for unsupported screen artifact minClient', () async {
    final screenBytes = Uint8List.fromList([1, 2, 3]);
    final bundle = _FlowAssetBundle.withFlow(
      flowRef,
      _validDocument(screenBytes: screenBytes, artifactMinClient: 4),
      screenBytes: screenBytes,
    );
    final resolver = AssetFlowResolver(bundle: bundle);

    await expectLater(
      resolver.resolve(flowRef),
      throwsA(_flowUnavailable('unsupported_min_client')),
    );
  });

  test('fails closed for unsupported state kind', () async {
    final screenBytes = Uint8List.fromList([1, 2, 3]);
    final document = _validDocument(screenBytes: screenBytes);
    final json = jsonDecode(FlowDocumentCodec.encodePrettyJson(document))
        as Map<String, Object?>;
    final states = json['states'] as Map<String, Object?>;
    states['welcome'] = {
      'kind': 'futureNode',
      'predicate': true,
    };
    final bundle = _FlowAssetBundle()
      ..writeFlowJson(flowRef, jsonEncode(json))
      ..writeScreen('welcome.rfw', screenBytes);
    final resolver = AssetFlowResolver(bundle: bundle);

    await expectLater(
      resolver.resolve(flowRef),
      throwsA(_flowUnavailable('unsupported_state_kind')),
    );
  });

  test('fails closed for validation issues', () async {
    final screenBytes = Uint8List.fromList([1, 2, 3]);
    final document = _validDocument(screenBytes: screenBytes);
    final json = jsonDecode(FlowDocumentCodec.encodePrettyJson(document))
        as Map<String, Object?>;
    final states = json['states'] as Map<String, Object?>;
    states['welcome'] = {
      'kind': 'screen',
      'screen': 'missing',
      'on': {
        'next': {'type': 'goto', 'target': 'done'},
      },
    };
    final bundle = _FlowAssetBundle()
      ..writeFlowJson(flowRef, jsonEncode(json))
      ..writeScreen('welcome.rfw', screenBytes);
    final resolver = AssetFlowResolver(bundle: bundle);

    await expectLater(
      resolver.resolve(flowRef),
      throwsA(_flowUnavailable('validation_failed')),
    );
  });

  test('Restage keeps flow and paywall resolvers separate on configure',
      () async {
    final flowResolver = _FakeFlowResolver();
    final paywallResolver = _FakeVariantResolver();

    expect(Restage.defaultFlowResolver, isA<AssetFlowResolver>());
    expect(Restage.defaultResolver, isA<AssetVariantResolver>());

    Restage.configure(
      apiKey: 'rs_pk_test',
      flowResolver: flowResolver,
      resolver: paywallResolver,
    );

    expect(Restage.defaultFlowResolver, same(flowResolver));
    expect(Restage.defaultResolver, same(paywallResolver));
  });
}

Map<String, Object?> _decodeMapResult(Map<String, Object?> result) => result;

Matcher _flowUnavailable(String reason) {
  return isA<FlowUnavailableError>()
      .having((error) => error.reason, 'reason', reason)
      .having((error) => error.message, 'message', isNotEmpty);
}

FlowDocument _validDocument({
  required Uint8List screenBytes,
  String flow = 'first_run',
  int version = 1,
  int schemaVersion = 1,
  int minClient = 3,
  int artifactSchemaVersion = 1,
  int artifactMinClient = 3,
  Map<String, FlowActionContract> actions = const {},
  Map<String, FlowState>? states,
}) {
  return FlowDocument(
    flow: flow,
    version: version,
    schemaVersion: schemaVersion,
    minClient: minClient,
    initial: 'welcome',
    actions: actions,
    screenArtifacts: {
      'welcome': ScreenArtifact(
        path: 'welcome.rfw',
        version: 1,
        schemaVersion: artifactSchemaVersion,
        minClient: artifactMinClient,
        contentHash: FlowContentHash.compute(screenBytes),
      ),
    },
    states: states ??
        const {
          'welcome': ScreenFlowState(
            screen: 'welcome',
            on: {'next': FlowTransition.goto('done')},
          ),
          'done': EndFlowState(result: {'completed': true}),
        },
  );
}

const _emptyArgsSchema = FlowActionSchema.object({});
const _boolResultSchema = FlowActionSchema.bool();

final class _FlowAssetBundle extends CachingAssetBundle {
  _FlowAssetBundle();

  factory _FlowAssetBundle.withFlow(
    OnboardingFlowRef<Object?> flow,
    FlowDocument document, {
    required Uint8List screenBytes,
  }) {
    return _FlowAssetBundle()
      ..writeFlow(flow, document)
      ..writeScreen('welcome.rfw', screenBytes);
  }

  final Map<String, Uint8List> _assets = {};
  final List<String> loadedKeys = [];

  void writeFlow(OnboardingFlowRef<Object?> flow, FlowDocument document) {
    writeFlowJson(flow, FlowDocumentCodec.encodePrettyJson(document));
  }

  void writeFlowJson(OnboardingFlowRef<Object?> flow, String json) {
    _assets['assets/onboarding/flows/${flow.id}.flow.json'] =
        Uint8List.fromList(utf8.encode(json));
  }

  void writeScreen(String path, Uint8List bytes) {
    _assets['assets/onboarding/screens/$path'] = Uint8List.fromList(bytes);
  }

  void removeScreen(String path) {
    _assets.remove('assets/onboarding/screens/$path');
  }

  @override
  Future<ByteData> load(String key) async {
    loadedKeys.add(key);
    final bytes = _assets[key];
    if (bytes == null) {
      throw FlutterError('Unable to load asset: $key');
    }
    return ByteData.view(
      Uint8List.fromList(bytes).buffer,
    );
  }
}

final class _FakeFlowResolver implements FlowResolver {
  @override
  Future<ResolvedFlow> resolve<R>(OnboardingFlowRef<R> flow) {
    throw UnimplementedError();
  }
}

final class _FakeVariantResolver implements VariantResolver {
  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) {
    throw UnimplementedError();
  }
}
