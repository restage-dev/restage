import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:restage/restage.dart';
import 'package:restage/src/measurement/measurement_host_session.dart';
import 'package:restage/src/resolver/delivery_input_budget.dart';
import 'package:restage/src/resolver/surface_delivery_observations.dart';
import 'package:restage/src/restage_rpc_client/bounded_http_client.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../surface_screen/surface_screen_test_support.dart';

const _baseUrl = 'https://surfaces.example.com';
const _apiKey = 'rs_pk_test_screen';
const _surfacePath = '/sdk/v1/surface';
const _credentialPath = '/sdk/v1/measurement-assignment-credential';
const _bindingPath = '/sdk/v1/measurement-publication-binding';
const _credentialHandle = 'handle-1';

const _packageInfoChannel = 'dev.fluttercommunity.plus/package_info';
const _deviceInfoChannel = 'dev.fluttercommunity.plus/device_info';

/// Where an optional request input can stop answering.
enum _Silent { preferences, packageInfo, deviceInfo, credentialRequest }

void main() {
  setUp(() {
    Restage.debugReset();
    debugResetAppBuildOrdinal();
    debugResetOsVersion();
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(Restage.debugReset);

  for (final silent in _Silent.values) {
    testWidgets('renders the hosted screen when ${silent.name} never answers',
        (tester) async {
      final harness = _Harness(tester, silent: {silent});

      await harness.mount();
      await tester.pump(DeliveryInputBudget.defaultTotal);
      await tester.pump();

      expect(find.text('Hosted screen'), findsOneWidget);
      expect(harness.surfaceRequests, hasLength(1));
      await harness.unmount();
    });
  }

  testWidgets('renders the bundled screen when nothing is published',
      (tester) async {
    final harness = _Harness(
      tester,
      silent: _Silent.values.toSet(),
      published: false,
    );

    await harness.mount();
    await tester.pump(DeliveryInputBudget.defaultTotal);
    await tester.pump();

    expect(find.text('Bundled screen'), findsOneWidget);
    expect(harness.surfaceRequests, hasLength(1));
    await harness.unmount();
  });

  testWidgets('registers the assignment key at configuration', (tester) async {
    final harness = _Harness(tester, credentialDelay: Duration.zero);

    await harness.configureOnly();
    await harness.settle(done: () => harness.credentialRequests > 0);

    expect(harness.credentialRequests, 1);
    expect(harness.surfaceRequests, isEmpty);
    await harness.unmount();
  });

  testWidgets('renders when the measurement session never opens',
      (tester) async {
    final harness = _Harness(tester, silentBindingRead: true);

    await harness.mount();
    await harness.settle(done: () => harness.bindingReads > 0);
    expect(harness.bindingReads, 1);
    expect(find.text('Hosted screen'), findsNothing);

    await tester.pump(MeasurementHostSessionController.openBudget);
    await tester.pump();

    expect(find.text('Hosted screen'), findsOneWidget);
    await harness.unmount();
  });

  testWidgets('answered inputs are sent without waiting on the deadline',
      (tester) async {
    final harness = _Harness(tester);

    await harness.mount();
    await harness.settle(
      done: () => find.text('Hosted screen').evaluate().isNotEmpty,
    );

    expect(find.text('Hosted screen'), findsOneWidget);
    final body = harness.surfaceRequests.single;
    expect(body['meteringKey'], isA<String>());
    expect(body['analyticsAnonymousId'], isA<String>());
    expect(body['sdkBuiltInsCanonicalBase64'], isA<String>());
    await harness.unmount();
  });

  testWidgets('an input answered before the deadline is still sent',
      (tester) async {
    final harness = _Harness(tester, delayedPreferences: true);

    await harness.mount();
    for (var i = 0; i < 19; i += 1) {
      await tester.pump(DeliveryInputBudget.defaultTotal ~/ 20);
      await harness.settle();
    }
    await harness.settle(
      done: () => find.text('Hosted screen').evaluate().isNotEmpty,
    );

    expect(find.text('Hosted screen'), findsOneWidget);
    expect(harness.surfaceRequests.single['meteringKey'], isA<String>());
    await harness.unmount();
  });

  testWidgets('a surface fetch completes when preferences never answer',
      (tester) async {
    _silencePreferences();
    Restage.configure(apiKey: _apiKey, baseUrl: _baseUrl);
    final bodies = <Map<String, dynamic>>[];
    final client = RestageRpcClient(
      baseUrl: _baseUrl,
      apiKey: _apiKey,
      httpClient: stringScreenFixture().hostedDelivery.client((request) async {
        if (request.url.path == _surfacePath) {
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        }
        return http.Response('', 404);
      }),
    );
    Restage.debugRestageRpcClient = client;

    var done = false;
    unawaited(client
        .fetchSurface(surfaceType: 'paywall', surfaceSlug: 'offer')
        .whenComplete(() => done = true));
    await tester.pump();
    expect(done, isFalse);

    await tester.pump(DeliveryInputBudget.defaultTotal);
    await tester.pump();

    expect(done, isTrue);
    expect(bodies.single, isNot(contains('meteringKey')));
    expect(bodies.single, isNot(contains('analyticsAnonymousId')));
  });
}

final class _SilentPreferencesStore extends SharedPreferencesStorePlatform {
  @override
  Future<bool> clear() => Completer<bool>().future;

  @override
  Future<Map<String, Object>> getAll() =>
      Completer<Map<String, Object>>().future;

  @override
  Future<bool> remove(String key) => Completer<bool>().future;

  @override
  Future<bool> setValue(String valueType, String key, Object value) =>
      Completer<bool>().future;
}

final class _DelayedPreferencesStore extends SharedPreferencesStorePlatform {
  final Map<String, Object> _values = {};

  Future<T> _later<T>(T Function() value) => Future<T>.delayed(
        DeliveryInputBudget.defaultTotal ~/ 10,
        value,
      );

  @override
  Future<bool> clear() => _later(() {
        _values.clear();
        return true;
      });

  @override
  Future<Map<String, Object>> getAll() => _later(() => Map.of(_values));

  @override
  Future<bool> remove(String key) => _later(() => _values.remove(key) != null);

  @override
  Future<bool> setValue(String valueType, String key, Object value) =>
      _later(() {
        _values[key] = value;
        return true;
      });
}

void _silencePreferences() {
  SharedPreferences.resetStatic();
  SharedPreferencesStorePlatform.instance = _SilentPreferencesStore();
}

final class _Harness {
  _Harness(
    this.tester, {
    this.silent = const {},
    this.published = true,
    this.silentBindingRead = false,
    this.delayedPreferences = false,
    this.credentialDelay,
  });

  final WidgetTester tester;
  final Set<_Silent> silent;
  final bool published;
  final bool silentBindingRead;
  final bool delayedPreferences;

  /// When set, the credential request answers with a key after this long.
  final Duration? credentialDelay;
  final surfaceRequests = <Map<String, dynamic>>[];
  var bindingReads = 0;
  var credentialRequests = 0;
  late final _fixture = stringScreenFixture();
  late final RestageRpcClient _client = _buildClient();

  /// Configures the SDK without mounting a screen.
  Future<void> configureOnly() async {
    Restage.configure(apiKey: _apiKey, baseUrl: _baseUrl);
    Restage.debugRestageRpcClient = _client;
  }

  Future<void> mount() async {
    if (silent.contains(_Silent.preferences)) _silencePreferences();
    if (delayedPreferences) {
      SharedPreferences.resetStatic();
      SharedPreferencesStorePlatform.instance = _DelayedPreferencesStore();
    }
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMessageHandler(
      _packageInfoChannel,
      silent.contains(_Silent.packageInfo)
          ? (_) => Completer<ByteData?>().future
          : null,
    );
    messenger.setMockMessageHandler(
      _deviceInfoChannel,
      silent.contains(_Silent.deviceInfo)
          ? (_) => Completer<ByteData?>().future
          : null,
    );
    addTearDown(() {
      messenger.setMockMessageHandler(_packageInfoChannel, null);
      messenger.setMockMessageHandler(_deviceInfoChannel, null);
    });

    final fixture = _fixture;
    final client = _client;
    await configureOnly();

    await tester.pumpWidget(MaterialApp(
      home: RestageScreen<String>(
        screen: fixture.ref,
        resolver: RestageScreenResolver(
          apiKey: _apiKey,
          environment: RestageEnvironment.production,
          baseUrl: _baseUrl,
          assetFallback: FixedBundledScreenResolver(fixture.bundled()),
          rpcClientProvider: () => client,
        ),
        unavailable: SurfaceScreenUnavailablePolicy.fallback(
          builder: (_, error) => Text('fallback:${error.reason.name}'),
        ),
      ),
    ));
  }

  RestageRpcClient _buildClient() {
    final fixture = _fixture;
    final hostedBlob = rfwScreenBlob(text: 'Hosted screen', event: 'tap');
    return RestageRpcClient(
      baseUrl: _baseUrl,
      apiKey: _apiKey,
      httpClient: fixture.hostedDelivery.client((request) async {
        switch (request.url.path) {
          case _surfacePath:
            surfaceRequests.add(
              jsonDecode(request.body) as Map<String, dynamic>,
            );
            if (!published) return http.Response('', 204);
            return http.Response(
              jsonEncode(SurfaceScreenDeliveryDescriptorV1Codec.encode(
                fixture.delivery(hostedBlob: hostedBlob),
              )),
              200,
              headers: {
                if (silentBindingRead)
                  'Restage-Measurement-Publication-Binding-V1':
                      base64UrlEncode(_bindingReference().canonicalBytes)
                          .replaceAll('=', ''),
              },
            );
          case _credentialPath when silent.contains(_Silent.credentialRequest):
            return Completer<http.Response>().future;
          case _credentialPath when credentialDelay != null:
            credentialRequests += 1;
            await Future<void>.delayed(credentialDelay!);
            return http.Response(
              jsonEncode({
                'credentialHandle': _credentialHandle,
                'expiresAtMicros': DateTime.utc(2100).microsecondsSinceEpoch,
              }),
              200,
            );
          case _bindingPath:
            bindingReads += 1;
            return Completer<http.Response>().future;
        }
        return http.Response('', 404);
      }),
    );
  }

  /// Lets real I/O and zero-time work run, without advancing the clock,
  /// until [done] holds or a generous number of turns has passed.
  Future<void> settle({bool Function()? done}) async {
    for (var i = 0; i < 200; i += 1) {
      if (i >= 10 && (done?.call() ?? true)) return;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
    }
  }

  /// Lets stalled requests time out, then removes the screen.
  Future<void> unmount() async {
    await tester.pump(BoundedHttpClient.defaultTimeout);
    await tester.pumpWidget(const SizedBox());
  }
}

MeasurementPublicationBindingReferenceV1 _bindingReference() {
  final candidate = MeasurementPublicationCandidateReferenceV1(
    candidateDigest: CanonicalDigest('a' * 64),
    selectedPublicationManifestDigest: CanonicalDigest('b' * 64),
    declaredArtifactBytesDigest: CanonicalDigest('c' * 64),
    assembledPublicationUploadDigest: CanonicalDigest('d' * 64),
    measurementPublicationDraftDigest: CanonicalDigest('e' * 64),
  );
  return MeasurementPublicationBindingReferenceV1(
    publicationAuthorityReference: RegisteredPublicationAuthorityReferenceV1(
      authorityId: MeasurementPublicationAuthorityId('authority.screen.a'),
      externalPublicationAuthorityRef: 'mpa1.${'A' * 32}',
      candidateReference: candidate,
      immutablePublicationDigest: CanonicalDigest('f' * 64),
      declaredArtifactBytesDigest: candidate.declaredArtifactBytesDigest,
    ),
    bindingDigest: CanonicalDigest('0' * 64),
  );
}
