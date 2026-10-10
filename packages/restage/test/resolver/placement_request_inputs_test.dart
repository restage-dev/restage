import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/resolver/delivery_input_budget.dart';
import 'package:restage/src/resolver/surface_assignment_key_provider.dart';
import 'package:restage/src/resolver/surface_canonical_carrier_provider.dart';
import 'package:restage/src/resolver/surface_delivery_observations.dart';
import 'package:restage/src/resolver/surface_request_inputs.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:restage/src/runtime/first_launch_store.dart';
import 'package:restage/src/runtime/installed_libraries_carrier.dart';
import 'package:restage/src/runtime/installed_widget_vocabulary.dart';
import 'package:restage/src/runtime/library_runtime_registry.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart'
    show SurfaceScreenDeliveryDescriptorV1Codec;
import 'package:shared_preferences/shared_preferences.dart';

import '../surface_screen/surface_screen_test_support.dart';

const _baseUrl = 'https://example.com';
const _apiKey = 'rs_pk_test';
const _firstLaunchKey = 'restage.first_launch_utc';

Map<String, Object?> _decodeBuiltIns(Object? carrier) => (jsonDecode(utf8
            .decode(base64Url.decode(base64Url.normalize(carrier as String))))
        as Map)
    .cast<String, Object?>();

SdkInstalledLibrariesV1 _decodeLibraries(Object? carrier) =>
    SdkInstalledLibrariesV1.fromCanonicalBytes(
      base64Url.decode(base64Url.normalize(carrier as String)),
    );

void _register(String namespace, {int version = 2}) =>
    Restage.registerWidgetLibrary(
      WidgetLibrary.custom(namespace),
      widgets: [
        RestageWidgetFactory(name: 'W', builder: (_, __) => const SizedBox())
      ],
      capabilityVersion: version,
    );

RestageRpcClient _client(Future<http.Response> Function(http.Request) answer) =>
    RestageRpcClient(
      baseUrl: _baseUrl,
      apiKey: _apiKey,
      httpClient: MockClient(answer),
    );

void _configure({String? channel, bool installedCatalog = false}) {
  if (installedCatalog) {
    Restage.configureWithInstalledCatalog(
      apiKey: _apiKey,
      baseUrl: _baseUrl,
      channel: channel,
      analyticsEnabled: false,
      measurementEnabled: false,
      deliveryReceiptsEnabled: false,
    );
  } else {
    Restage.configure(
      apiKey: _apiKey,
      baseUrl: _baseUrl,
      channel: channel,
      analyticsEnabled: false,
      measurementEnabled: false,
      deliveryReceiptsEnabled: false,
    );
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final support =
      Directory.systemTemp.createTempSync('restage-request-inputs-');
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  binding.defaultBinaryMessenger.setMockMethodCallHandler(
    pathProvider,
    (call) async => support.path,
  );
  tearDownAll(() async {
    await Restage.debugResetAndWait();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(pathProvider, null);
    await support.delete(recursive: true);
  });
  setUp(() {
    Restage.debugReset();
    debugResetInstallObservations();
    debugResetAppBuildOrdinal();
    debugSetOsVersion(null);
    PackageInfo.setMockInitialValues(
      appName: 'Example',
      packageName: 'example.app',
      version: '1.0.0',
      buildNumber: '42',
      buildSignature: '',
    );
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(Restage.debugResetAndWait);
  tearDown(debugResetInstallObservations);

  test('ordinary HTTP sends the capability captured before optional inputs',
      () async {
    _register('app.widgets');
    final key = Completer<String?>();
    SurfaceAssignmentKeyProvider.current = () => key.future;
    final budget = DeliveryInputBudget();
    addTearDown(budget.close);
    final pending = SurfaceRequestInputs.gather(
      budget: budget,
      surface: 'general',
      slug: 'notice',
    );
    _register('app.widgets', version: 3);
    _register('later.widgets', version: 1);
    key.complete('assignment-a');
    final inputs = await pending;
    expect(inputs.installedCapability.libraryOf('app.widgets')!.version, 2);
    expect(inputs.installedCapability.libraryOf('later.widgets'), isNull);
    expect(
        inputs.installedCapabilityHash, inputs.installedCapability.contentHash);
    expect(inputs.sdkInstalledLibraries,
        installedLibrariesCarrier(snapshot: inputs.installedCapability));
    expect(() => inputs.installedCapability.installedLibraries.clear(),
        throwsUnsupportedError);
    late Map<String, Object?> sent;

    await _client((request) async {
      sent = (jsonDecode(request.body) as Map).cast();
      return http.Response('', 404);
    }).fetchSurface(
        surfaceType: 'general', surfaceSlug: 'notice', inputs: inputs);

    expect(sent['sdkInstalledLibraries'], inputs.sdkInstalledLibraries);
    final libraries = _decodeLibraries(sent['sdkInstalledLibraries']).libraries;
    expect(libraries, hasLength(1));
    expect(libraries.single.version, 2);
    expect(sent['assignmentKey'], 'assignment-a');
  });

  test(
      'strict screen HTTP sends the snapshot captured before the lease resolves',
      () async {
    final fixture = stringScreenFixture();
    _register('app.widgets');
    final expected = currentInstalledCapability();
    final ready = Completer<String?>();
    SurfaceAssignmentKeyProvider.current = () {
      _register('later.widgets', version: 1);
      return ready.future;
    };
    late Map<String, Object?> sent;
    final resolver = RestageScreenResolver(
      apiKey: _apiKey,
      environment: RestageEnvironment.production,
      rpcClientProvider: () => _client((request) async {
        sent = (jsonDecode(request.body) as Map).cast();
        return http.Response('', 404);
      }),
      assetFallback: FixedBundledScreenResolver(fixture.bundled()),
    );
    final pending = resolver.resolve(fixture.ref);
    ready.complete('assignment-a');
    await pending;

    expect(sent['sdkInstalledLibraries'],
        installedLibrariesCarrier(snapshot: expected));
    expect(
        _decodeLibraries(sent['sdkInstalledLibraries'])
            .libraries
            .single
            .namespace,
        'app.widgets');
    expect(sent['assignmentKey'], 'assignment-a');
  });

  for (final invalid in ['has space', 'oversize']) {
    test('$invalid libraries are omitted from ordinary and strict HTTP',
        () async {
      if (invalid == 'oversize') {
        for (var index = 0;
            index <= sdkInstalledLibrariesMaximumLibraries;
            index++) {
          _register('lib$index');
        }
      } else {
        _register(invalid);
      }
      final fixture = stringScreenFixture();
      final sent = <Map<String, Object?>>[];
      final client = _client((request) async {
        sent.add((jsonDecode(request.body) as Map).cast());
        return http.Response('', 404);
      });
      await client.fetchSurface(surfaceType: 'general', surfaceSlug: 'notice');
      await RestageScreenResolver(
        apiKey: _apiKey,
        environment: RestageEnvironment.production,
        rpcClientProvider: () => client,
        assetFallback: FixedBundledScreenResolver(fixture.bundled()),
      ).resolve(fixture.ref);

      expect(sent, hasLength(2));
      for (final body in sent) {
        expect(body, isNot(contains('sdkInstalledLibraries')));
      }
    });
  }

  for (final installedCatalog in [false, true]) {
    test(
        'configure installedCatalog=$installedCatalog emits bounded raw channel',
        () async {
      final channel = 'é' * 64;
      _configure(channel: channel, installedCatalog: installedCatalog);
      await pumpEventQueue();
      late Map<String, Object?> sent;
      await _client((request) async {
        sent = (jsonDecode(request.body) as Map).cast();
        return http.Response('', 404);
      }).fetchSurface(surfaceType: 'general', surfaceSlug: 'notice');
      final builtIns = _decodeBuiltIns(sent['sdkBuiltInsCanonicalBase64']);
      expect(builtIns['channel'], channel);
      expect(builtIns['sdkApiLevel'], 4);
      expect(builtIns['daysSinceInstall'], 0);
      expect(sent, isNot(contains('context')));
      expect(sent, isNot(contains('seed')));
    });
  }

  for (final channel in [null, '', 'é' * 65]) {
    test('an unknown channel $channel leaves the built-in field absent',
        () async {
      _configure(channel: channel);
      final builtIns =
          _decodeBuiltIns(await SurfaceCanonicalCarrierProvider.builtIns());
      expect(builtIns, isNot(contains('channel')));
      expect(builtIns['sdkApiLevel'], 4);
    });
  }

  for (final (label, channel, expectedChannel) in <(String, String, String?)>[
    ('unpaired high surrogate', String.fromCharCode(0xD800), null),
    ('unpaired low surrogate', String.fromCharCode(0xDC00), null),
    ('valid Unicode', ' beta-測試-🚀 ', ' beta-測試-🚀 '),
    ('128-byte multibyte channel', 'é' * 64, 'é' * 64),
    ('128-byte surrogate-pair channel', '🚀' * 32, '🚀' * 32),
  ]) {
    test('channel $label preserves known inputs on hosted screen HTTP',
        () async {
      debugResetOsVersion();
      _configure(channel: channel);
      await pumpEventQueue();
      // Configure may have read the build for local discovery. This request
      // must use the controlled pending source below, rather than that memo.
      debugResetAppBuildOrdinal();
      _register('app.widgets');
      SurfaceAssignmentKeyProvider.current = () async => 'assignment-a';
      final buildNumber = Completer<String?>();
      final cell = SurfaceDeliveryObservationCell(
        () => readSurfaceDeliveryObservations(
          isWeb: false,
          targetPlatform: TargetPlatform.android,
          shortestLogicalSide: 390,
          deviceRegion: 'SE',
          deviceLanguage: 'sv',
          buildNumberSource: () => buildNumber.future,
          osVersionSource: (_) async => 17,
        ),
      );
      final fixture = stringScreenFixture();
      final sent = <Map<String, Object?>>[];
      final client = RestageRpcClient(
        baseUrl: _baseUrl,
        apiKey: _apiKey,
        httpClient: fixture.hostedDelivery.serving(
          SurfaceScreenDeliveryDescriptorV1Codec.encode(fixture.delivery()),
          onDelivery: (request) =>
              sent.add((jsonDecode(request.body) as Map).cast()),
        ),
      );
      final resolver = RestageScreenResolver(
        apiKey: _apiKey,
        environment: RestageEnvironment.production,
        rpcClientProvider: () => client,
        assetFallback: FixedBundledScreenResolver(fixture.bundled()),
      );
      final pending = withSurfaceDeliveryObservations(
        cell: cell,
        resolve: () => resolver.resolve(fixture.ref),
      );
      await pumpEventQueue();
      expect(sent, isEmpty);
      buildNumber.complete('42');
      final resolved = await pending;

      expect(sent, hasLength(1));
      expect(_decodeBuiltIns(sent.single['sdkBuiltInsCanonicalBase64']), {
        'appBuildOrdinal': 42,
        'country': 'se',
        'daysSinceInstall': 0,
        'deviceClass': 'phone',
        'language': 'sv',
        'osVersion': 17,
        'platform': 'android',
        'sdkApiLevel': 4,
        if (expectedChannel != null) 'channel': expectedChannel,
      });
      expect(sent.single['assignmentKey'], 'assignment-a');
      expect(
        _decodeLibraries(sent.single['sdkInstalledLibraries'])
            .libraries
            .single
            .namespace,
        'app.widgets',
      );
      expect(fixture.hostedDelivery.artifactRequests, hasLength(1));
      expect(resolved.origin, SurfaceScreenOrigin.hosted);
      expect(resolved.publishedRevision, 7);
      expect(resolved.blob, fixture.blob);
    });
  }

  test(
      'request reuse refreshes age and channel while retaining presentation facts',
      () async {
    final first = DateTime.utc(2026, 10, 3, 12);
    var now = first;
    SharedPreferences.setMockInitialValues(
        {_firstLaunchKey: first.toIso8601String()});
    debugResetInstallObservations(nowUtc: () => now);
    _configure(channel: 'beta');
    await pumpEventQueue();
    var country = 'se';
    var reads = 0;
    final cell = SurfaceDeliveryObservationCell(() {
      reads++;
      return readSurfaceDeliveryObservations(deviceRegion: country);
    });
    final original = await cell.read();
    expect(original.daysSinceInstall, 0);
    expect(original.channel, 'beta');
    now = first.add(const Duration(hours: 23, minutes: 59));
    expect(await cell.read(), same(original));
    country = 'us';
    now = first.add(const Duration(hours: 24));
    final next = await cell.read();
    expect(next.daysSinceInstall, 1);
    expect(next.presentationCountry, 'SE');
    expect(original.daysSinceInstall, 0);
    Restage.reset();
    Restage.configureWithInstalledCatalog(
      apiKey: _apiKey,
      baseUrl: _baseUrl,
      channel: 'release',
      environment: RestageEnvironment.sandbox,
      analyticsEnabled: false,
      measurementEnabled: false,
    );
    final changed = await cell.read();
    expect(changed.daysSinceInstall, 1);
    expect(changed.channel, 'release');
    expect(original.channel, 'beta');
    expect(reads, 1);
    expect((await SharedPreferences.getInstance()).getString(_firstLaunchKey),
        first.toIso8601String());
  });

  test('storage failure stays unknown and a later configure retries', () async {
    final first = DateTime.utc(2026, 10, 3, 12);
    final preferences = await SharedPreferences.getInstance();
    var fails = true;
    var reads = 0;
    debugResetInstallObservations(
      nowUtc: () => first,
      store: FirstLaunchStore(preferences: () async {
        reads++;
        if (fails) throw StateError('Storage unavailable');
        return preferences;
      }),
    );
    _configure();
    await pumpEventQueue();
    expect((await readSurfaceDeliveryObservations()).daysSinceInstall, isNull);
    fails = false;
    _configure();
    await pumpEventQueue();
    expect((await readSurfaceDeliveryObservations()).daysSinceInstall, 0);
    expect(reads, greaterThanOrEqualTo(2));
  });

  testWidgets(
      'first-launch storage cannot delay the mount deadline and later age is sent',
      (tester) async {
    final previousOnError = FlutterError.onError;
    try {
      final first = DateTime.utc(2026, 10, 3, 12);
      final preferences = await SharedPreferences.getInstance();
      final launchReady = Completer<SharedPreferences>();
      debugResetInstallObservations(
        nowUtc: () => first,
        store: FirstLaunchStore(preferences: () => launchReady.future),
      );
      await tester.runAsync(() async => _configure(channel: 'beta'));
      debugResetAppBuildOrdinal();
      expect(Restage.renderDeadline, const Duration(milliseconds: 300));
      final fixture = stringScreenFixture();
      final sent = <Map<String, Object?>>[];
      final response = Completer<http.Response>();
      final client = _client((request) {
        sent.add((jsonDecode(request.body) as Map).cast());
        return sent.length == 1
            ? response.future
            : Future.value(http.Response('', 404));
      });
      final resolver = RestageScreenResolver(
        apiKey: _apiKey,
        environment: RestageEnvironment.production,
        rpcClientProvider: () => client,
        assetFallback: FixedBundledScreenResolver(fixture.bundled()),
      );
      await tester.pumpWidget(MaterialApp(
          home: RestageScreen(
        screen: fixture.ref,
        resolver: resolver,
        unavailable: const SurfaceScreenUnavailablePolicy.hide(),
      )));
      await tester.pump(const Duration(milliseconds: 299));
      expect(find.text('Bundled screen'), findsNothing);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(find.text('Bundled screen'), findsOneWidget);
      await tester.pump(DeliveryInputBudget.defaultTotal);
      await tester.pump();
      expect(sent, hasLength(1));
      final initialBuiltIns =
          _decodeBuiltIns(sent.single['sdkBuiltInsCanonicalBase64']);
      expect(initialBuiltIns, isNot(contains('daysSinceInstall')));
      expect(initialBuiltIns, containsPair('appBuildOrdinal', 42));
      expect(initialBuiltIns, containsPair('sdkApiLevel', 4));
      expect(initialBuiltIns, containsPair('channel', 'beta'));
      launchReady.complete(preferences);
      response.complete(http.Response('', 404));
      await tester.pumpAndSettle();
      await tester.runAsync(() => pumpEventQueue());
      final nextRequest = resolver.resolve(fixture.ref);
      await tester.pump(DeliveryInputBudget.defaultTotal);
      await tester.pump();
      await nextRequest;
      expect(sent, hasLength(2));
      expect(
          _decodeBuiltIns(
              sent.last['sdkBuiltInsCanonicalBase64'])['daysSinceInstall'],
          0);
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      FlutterError.onError = previousOnError;
    }
  });

  testWidgets(
      'after-frame prefetch installs every listed flow and screen vocabulary',
      (tester) async {
    SurfaceVocabulary vocabulary(String namespace) =>
        SurfaceVocabulary(libraries: [
          RestageWidgetLibraryRegistration(
            library: WidgetLibrary.custom(namespace),
            widgets: [
              RestageWidgetFactory(
                  name: 'W', builder: (_, __) => const SizedBox())
            ],
            capabilityVersion: 1,
          ),
        ]);
    final screen =
        stringScreenFixture(vocabulary: vocabulary('screen.widgets'));
    final child = SurfaceFlowRef<Map<String, Object?>>(
      id: 'child',
      version: 1,
      minClient: 1,
      surface: Surface.general,
      decodeResult: (value) => value,
      vocabulary: vocabulary('child.widgets'),
    );
    final flow = SurfaceFlowRef<Map<String, Object?>>(
      id: 'root',
      version: 1,
      minClient: 1,
      surface: Surface.onboarding,
      decodeResult: (value) => value,
      vocabulary: vocabulary('flow.widgets'),
      subFlows: [child],
    );
    LibraryRuntimeRegistry.clear();
    await tester.runAsync(() async {
      Restage.configure(
        apiKey: _apiKey,
        baseUrl: _baseUrl,
        analyticsEnabled: false,
        measurementEnabled: false,
        deliveryReceiptsEnabled: false,
        registerWidgets: _Registration(),
        surfaces: [screen.ref, flow],
      );
    });
    final sent = <Map<String, Object?>>[];
    Restage.debugRestageRpcClient = _client((request) async {
      sent.add((jsonDecode(request.body) as Map).cast());
      return http.Response('', 404);
    });
    expect(
        currentInstalledCapability()
            .installedLibraries
            .map((library) => library.namespace),
        ['outer.widgets']);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.runAsync(() => pumpEventQueue());

    expect(sent, hasLength(1));
    final libraries =
        _decodeLibraries(sent.single['sdkInstalledLibraries']).libraries;
    expect(libraries.map((library) => library.namespace),
        ['child.widgets', 'flow.widgets', 'outer.widgets', 'screen.widgets']);
    expect(sent.single, isNot(contains('assignmentKey')));
    expect(sent.single, isNot(contains('registrationNonce')));
  });
}

final class _Registration implements RestageWidgetRegistration {
  @override
  void call({required bool includeMaterial, required bool includeCupertino}) =>
      _register('outer.widgets');
}
