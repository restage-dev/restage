// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/resolver/surface_assignment_credential_store.dart';
import 'package:restage/src/resolver/surface_assignment_key_provider.dart';
import 'package:restage/src/resolver/surface_canonical_carrier_provider.dart';
import 'package:restage/src/resolver/surface_delivery_observations.dart';
import 'package:restage/src/runtime/native_facts.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/placement_delivery_fixture.dart';
import '../support/sent_placement_request.dart';

const _vectorPath = '../restage_shared/test/vectors/first_launch_startup.json';
const _ordinal = 42;

// The device values the vector fills the template with.
const _device = {
  'android': {
    'country': 'se',
    'language': 'sv',
    'osVersion': 34,
    'deviceClass': 'phone',
    'daysSinceInstall': 0,
    'appVersion': '1.2.3',
    'utcOffsetMinutes': 120,
  },
  'ios': {
    'country': 'us',
    'language': 'en',
    'osVersion': 17,
    'deviceClass': 'phone',
    'daysSinceInstall': 0,
    'appVersion': '1.2.3',
    'utcOffsetMinutes': -420,
  },
};
const _meteringKey = '3f2b7c1e-5d4a-4b8e-9c0f-1a2b3c4d5e6f';
const _anonymousId = '7a9e1d2c-8b3f-4c6a-a1d0-2e4f6a8b0c1d';
const _nonce = 'AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE';
const _createdAtMicros = 1793600000000000;

String _canonical(Object? value) => switch (value) {
      Map() => '{${([
          for (final k in value.keys) k as String
        ]..sort()).map((k) => '${jsonEncode(k)}:${_canonical(value[k])}').join(',')}}',
      List() => '[${value.map(_canonical).join(',')}]',
      _ => jsonEncode(value),
    };

String _carrier(Object? tree) =>
    base64Url.encode(utf8.encode(_canonical(tree))).replaceAll('=', '');

String _hash(String contract) =>
    'sha256:${sha256.convert(utf8.encode('restage.placement-build-contract.v1\u0000$contract'))}';

/// What the platform makes of [template]: its tokens filled the way the
/// native early request fills them.
String _fill(
  Map<String, Object?> template,
  String key,
  Map<String, Object?> facts, {
  required int ordinal,
  required String metering,
  required String anonymous,
  required String nonce,
  required int createdAtMicros,
}) {
  var text = template[key]! as String;
  final contract = (template['contract']! as String).replaceAll(
    '@@buildOrdinal@@',
    '$ordinal',
  );
  String tree(String name) {
    final tree = Map<String, Object?>.of(
      (template[name]! as Map).cast<String, Object?>(),
    );
    for (final fact in (template['fills']! as List).cast<String>()) {
      if (fact == 'utcOffsetMinutes' ||
          fact == 'buildOrdinal' ||
          (fact == 'appVersion') != (name == 'installedLibraries')) {
        continue;
      }
      final value = fact == 'appBuildOrdinal' ? ordinal : facts[fact];
      if (value == null) {
        tree.remove(fact);
      } else {
        tree[fact] = value;
      }
    }
    return _carrier(tree);
  }

  text = text
      .replaceAll('@@buildContract@@', contract)
      .replaceAll('@@appBuildContractHash@@', _hash(contract))
      .replaceAll('@@meteringKey@@', metering)
      .replaceAll('@@analyticsAnonymousId@@', anonymous)
      .replaceAll('@@mountedSince@@', '')
      .replaceAll('@@utcOffsetMinutes@@', '${facts['utcOffsetMinutes']}')
      .replaceAll('@@registrationNonce@@', nonce)
      .replaceAll('@@registrationCreatedAtMicros@@', '$createdAtMicros');
  if (text.contains('@@sdkBuiltIns@@')) {
    text = text.replaceAll('@@sdkBuiltIns@@', tree('builtIns'));
  }
  if (text.contains('@@sdkInstalledLibraries@@')) {
    text = text.replaceAll(
      '@@sdkInstalledLibraries@@',
      tree('installedLibraries'),
    );
  }
  return text;
}

Map<String, Object?> _tree(String carrier) =>
    jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(carrier))))
        as Map<String, Object?>;

/// A generated setup whose build.yaml turns analytics off.
final class _AnalyticsOffSetup
    implements RestageWidgetRegistration, RestageBuildDelivery {
  const _AnalyticsOffSetup();

  @override
  String get apiKey => 'rs_pk_test';

  @override
  String get baseUrl => 'https://example.com';

  @override
  String? get channel => null;

  @override
  bool get analyticsEnabled => false;

  @override
  void call({required bool includeMaterial, required bool includeCupertino}) {}
}

/// The first request the SDK sends on a first launch on [platform]: with
/// [analytics] off it is configured so, by the app or, when [fromSetup], by
/// the build's generated setup.
Future<({List<List<int>> bodies, PlacementBatchRequestV1 request})>
    _sdkFirstRequest(
  WidgetTester tester,
  TargetPlatform platform, {
  bool analytics = true,
  bool fromSetup = false,
  bool measurement = true,
}) async {
  SharedPreferences.setMockInitialValues({});
  // Each case is a first launch the service has not seen.
  forgetSentBuilds();
  PackageInfo.setMockInitialValues(
    appName: 'test',
    packageName: 'test',
    version: '1.2.3',
    buildNumber: '$_ordinal',
    buildSignature: '',
  );
  Restage.debugReset();
  NativeFacts.reset();
  NativeFacts.debugFacts = {
    'registrationNonce': _nonce,
    'registrationCreatedAtMicros': _createdAtMicros,
  };
  debugResetAppBuildOrdinal();
  debugResetOsVersion();
  debugDefaultTargetPlatformOverride = platform;
  addTearDown(() {
    NativeFacts.debugFacts = null;
    NativeFacts.reset();
    debugDefaultTargetPlatformOverride = null;
    Restage.debugReset();
  });
  final host = readPlacementDeliveryFixture()
      .request
      .buildContract
      .contractsByHash
      .values
      .first;
  final definition = GeneratedPlacementDefinition(
    defaultSurface: PaywallRef('original'),
    defaultSurfaceLocator: DeliverySurfaceLocatorV1(
      surfaceType: DeliverySurfaceTypeId('paywall'),
      slug: 'original',
      family: const DeliveryFamilySelectorV1.general(),
    ),
    key: PlacementKeyV1.generatedDefault(
      surfaceType: DeliverySurfaceTypeId('paywall'),
      slug: 'original',
    ),
    hostContract: host,
    vocabulary: SurfaceVocabulary.none,
  );
  final bodies = <List<int>>[];
  PlacementBatchRequestV1? decoded;
  Restage.debugPlacementNow = () => DateTime.utc(2026, 10, 4, 12);
  Restage.declareSurfaces([definition]);
  Restage.configure(
    apiKey: fromSetup ? null : 'rs_pk_test',
    baseUrl: fromSetup ? null : 'https://example.com',
    registerWidgets: fromSetup ? const _AnalyticsOffSetup() : null,
    analyticsEnabled: fromSetup ? null : analytics,
    measurementEnabled: false,
    deliveryReceiptsEnabled: false,
    surfaces: [definition],
  );
  debugSetOsVersion(34);
  if (analytics && measurement) _installAssignment();
  final client = RestageRpcClient(
    baseUrl: 'https://example.com',
    apiKey: 'rs_pk_test',
    httpClient: MockClient((request) async {
      final artifact = placementFixtureArtifact(request);
      if (artifact != null) return artifact;
      if (request.method != 'POST' ||
          request.url.path != '/sdk/v1/placements/resolve') {
        throw StateError(
          'Unexpected request: ${request.method} ${request.url}',
        );
      }
      final PlacementBatchRequestV1 batch;
      try {
        batch = sentPlacementRequest(request.bodyBytes);
      } on PlacementBuildContractRequired {
        // As the service answers a build it does not hold yet.
        if (utf8.decode(request.bodyBytes).contains('"startup":true')) {
          bodies.add(request.bodyBytes);
        }
        return http.Response('', PlacementBuildContractRequired.status);
      }
      if (batch.startup) {
        bodies.add(request.bodyBytes);
        decoded ??= batch;
      }
      return http.Response.bytes(
        placementFixtureResponse(batch).canonicalBytes,
        200,
      );
    }),
  );
  Restage.debugRestageRpcClient = client;
  addTearDown(client.close);
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 400)),
  );
  debugDefaultTargetPlatformOverride = null;
  expect(decoded, isNotNull, reason: 'the SDK sent no startup request');
  return (bodies: bodies, request: decoded!);
}

// As configure installs it with measurement on.
void _installAssignment() {
  final store = SurfaceAssignmentCredentialStore(
    namespace: 'vector',
    actor: () async => 'device',
    identityGeneration: () => 0,
    onRetentionRollover: SurfaceCanonicalCarrierProvider.clearHeldAssignments,
  );
  SurfaceAssignmentKeyProvider.install(
    key: store.resolve,
    localKey: store.resolveLocal,
    identityGeneration: () => store.generation,
    registration: store.capture,
    confirmedKey: () => store.currentHandle,
    confirmRegistration: (attempt, start, handle, expiry, serverNow) =>
        store.confirm(
      attempt: attempt,
      localRequestStartMicros: start,
      credentialHandle: handle,
      expiresAtMicros: expiry,
      serverNowMicros: serverNow,
    ),
    refuseRegistration: store.refuse,
  );
}

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    final name = platform == TargetPlatform.android ? 'android' : 'ios';

    for (final fromSetup in [false, true]) {
      final how = fromSetup ? 'the build' : 'the app';
      testWidgets(
          'the $name analytics-off body, set by $how, matches the '
          'template', (tester) async {
        final sent = await _sdkFirstRequest(
          tester,
          platform,
          analytics: false,
          fromSetup: fromSetup,
        );
        final request = sent.request;
        expect(request.startup, isTrue);
        expect(request.meteringKey, isNotNull);
        expect(request.analyticsAnonymousId, isNull);
        expect(request.registration, isNull);
        expect(request.assignmentKey, isNull);

        final build = request.buildContract;
        final template = jsonDecode(
          startupTemplateJson(
            Uri.parse('https://example.com/sdk/v1/placements/resolve'),
            'rs_pk_test',
            startupRequestFor(
              platform: name,
              mounts: build.mounts.toList(),
              contractsByHash: build.contractsByHash,
              capability: build.installedCapability,
              buildOrdinal: 1,
              builtIns: {
                'appBuildOrdinal': 1,
                'country': 'us',
                'daysSinceInstall': 0,
                'deviceClass': 'phone',
                'language': 'en',
                'osVersion': 1,
                'platform': name,
                'sdkApiLevel': kAssignmentSdkApiLevel,
              },
            ),
            identityTokens: true,
            analytics: !fromSetup,
          )!,
        ) as Map<String, Object?>;
        expect(template['analytics'], !fromSetup);
        final off = (template['analyticsOff']! as Map).cast<String, Object?>();
        // The platform's analytics-off body, as it fills it.
        final variant = {
          ...template,
          'body': off['body'],
          'fullBody': off['fullBody']
        };
        for (final key in ['body', 'fullBody']) {
          expect(off[key], isNot(contains('@@analyticsAnonymousId@@')));
          expect(off[key], isNot(contains('@@registrationNonce@@')));
        }
        final builtIns = _tree(request.sdkBuiltInsCanonicalBase64!);
        final libraries = _tree(request.sdkInstalledLibraries!);
        final observed = {
          for (final fact in (template['fills']! as List).cast<String>())
            if (builtIns.containsKey(fact)) fact: builtIns[fact],
          'appVersion': libraries['appVersion'],
          'utcOffsetMinutes': request.localClock!.utcOffsetMinutes,
        };
        String filled(String key) => _fill(
              variant,
              key,
              observed,
              ordinal: _ordinal,
              metering: request.meteringKey!,
              anonymous: '',
              nonce: '',
              createdAtMicros: 0,
            );
        expect(
          sent.bodies.map(utf8.decode),
          [filled('body'), filled('fullBody')],
        );
      });
    }

    testWidgets('the $name measurement-off body matches the template', (
      tester,
    ) async {
      final sent = await _sdkFirstRequest(tester, platform, measurement: false);
      final request = sent.request;
      expect(request.analyticsAnonymousId, isNotNull);
      expect(request.registration, isNull);
      expect(request.assignmentKey, isNull);
      final build = request.buildContract;
      final template = jsonDecode(
        startupTemplateJson(
          Uri.parse('https://example.com/sdk/v1/placements/resolve'),
          'rs_pk_test',
          startupRequestFor(
            platform: name,
            mounts: build.mounts.toList(),
            contractsByHash: build.contractsByHash,
            capability: build.installedCapability,
            buildOrdinal: 1,
            builtIns: {
              'appBuildOrdinal': 1,
              'country': 'us',
              'daysSinceInstall': 0,
              'deviceClass': 'phone',
              'language': 'en',
              'osVersion': 1,
              'platform': name,
              'sdkApiLevel': kAssignmentSdkApiLevel,
            },
          ),
          identityTokens: true,
          measurement: false,
        )!,
      ) as Map<String, Object?>;
      expect(template['measurement'], isFalse);
      final off = (template['measurementOff']! as Map).cast<String, Object?>();
      // The platform's measurement-off body, as it fills it: no registration.
      final variant = {
        ...template,
        'body': off['body'],
        'fullBody': off['fullBody'],
      };
      for (final key in ['body', 'fullBody']) {
        expect(off[key], contains('@@analyticsAnonymousId@@'));
        expect(off[key], isNot(contains('@@registrationNonce@@')));
      }
      final builtIns = _tree(request.sdkBuiltInsCanonicalBase64!);
      final libraries = _tree(request.sdkInstalledLibraries!);
      final observed = {
        for (final fact in (template['fills']! as List).cast<String>())
          if (builtIns.containsKey(fact)) fact: builtIns[fact],
        'appVersion': libraries['appVersion'],
        'utcOffsetMinutes': request.localClock!.utcOffsetMinutes,
      };
      String filled(String key) => _fill(
            variant,
            key,
            observed,
            ordinal: _ordinal,
            metering: request.meteringKey!,
            anonymous: request.analyticsAnonymousId!,
            nonce: '',
            createdAtMicros: 0,
          );
      expect(
        sent.bodies.map(utf8.decode),
        [filled('body'), filled('fullBody')],
      );
    });

    testWidgets('the $name first-launch startup body matches the vector', (
      tester,
    ) async {
      final sent = await _sdkFirstRequest(tester, platform);
      final request = sent.request;
      expect(request.mode, PlacementBatchModeV1.prefetch);
      expect(request.startup, isTrue);
      expect(request.registration, isNotNull);
      expect(request.buildContract.buildOrdinal, _ordinal);

      // The template a generated app ships, built as the build step does.
      final build = request.buildContract;
      final template = jsonDecode(
        startupTemplateJson(
          Uri.parse('https://example.com/sdk/v1/placements/resolve'),
          'rs_pk_test',
          startupRequestFor(
            platform: name,
            mounts: build.mounts.toList(),
            contractsByHash: build.contractsByHash,
            capability: build.installedCapability,
            buildOrdinal: 1,
            builtIns: {
              'appBuildOrdinal': 1,
              'country': 'us',
              'daysSinceInstall': 0,
              'deviceClass': 'phone',
              'language': 'en',
              'osVersion': 1,
              'platform': name,
              'sdkApiLevel': kAssignmentSdkApiLevel,
            },
          ),
          identityTokens: true,
        )!,
      ) as Map<String, Object?>;

      // Filled with the values this SDK run reported, the template is the
      // exact bytes the SDK sent.
      final builtIns = _tree(request.sdkBuiltInsCanonicalBase64!);
      final libraries = _tree(request.sdkInstalledLibraries!);
      final observed = {
        for (final fact in (template['fills']! as List).cast<String>())
          if (builtIns.containsKey(fact)) fact: builtIns[fact],
        'appVersion': libraries['appVersion'],
        'utcOffsetMinutes': request.localClock!.utcOffsetMinutes,
      };
      final registration = request.registration!;
      String filled(String key) => _fill(
            template,
            key,
            observed,
            ordinal: _ordinal,
            metering: request.meteringKey!,
            anonymous: request.analyticsAnonymousId!,
            nonce: registration.registrationNonce,
            createdAtMicros: registration.registrationCreatedAtMicros,
          );
      // The build goes by hash first and in full once the service asks.
      expect(
          sent.bodies.map(utf8.decode), [filled('body'), filled('fullBody')]);

      // The vector holds the same template filled with fixed device values.
      final facts = {..._device[name]!, 'platform': name};
      final contract = (template['contract']! as String).replaceAll(
        '@@buildOrdinal@@',
        'null',
      );
      String fixed(String key) => _fill(template, key, facts,
          ordinal: _ordinal,
          metering: _meteringKey,
          anonymous: _anonymousId,
          nonce: _nonce,
          createdAtMicros: _createdAtMicros);
      final firstLaunch = {
        'ordinal': _ordinal,
        'device': facts,
        'body': fixed('body'),
        'fullBody': fixed('fullBody'),
      };
      final entry = {
        'contract': contract,
        'contractHash': _hash(contract),
        'earlyTemplatePath': name == 'android'
            ? 'android/app/src/main/assets/restage_early.json'
            : 'ios/Runner/restage_early.json',
        'firstLaunch': firstLaunch,
      };
      final file = File(_vectorPath);
      final all = file.existsSync()
          ? jsonDecode(file.readAsStringSync()) as Map<String, Object?>
          : <String, Object?>{};
      if (Platform.environment['UPDATE_VECTOR'] == '1') {
        all['kind'] = 'firstLaunchStartupVector';
        all[name] = entry;
        final sorted = Map.fromEntries(
          all.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
        );
        file.writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert(sorted)}\n',
        );
      }
      expect(all[name], entry, reason: 'run with UPDATE_VECTOR=1 to rewrite');

      // The carrier names the platform and build, which a service keys on.
      for (final key in ['body', 'fullBody']) {
        final text = firstLaunch[key]! as String;
        final carrier = RegExp('"sdkBuiltInsCanonicalBase64":"([^"]+)"')
            .firstMatch(text)!
            .group(1)!;
        expect(
            _tree(carrier),
            {
              'appBuildOrdinal': _ordinal,
              ...facts,
              'sdkApiLevel': kAssignmentSdkApiLevel,
            }
              ..remove('appVersion')
              ..remove('utcOffsetMinutes'));
      }

      // The vector body is a request the service reads, built for ordinal 42.
      final body = PlacementBatchRequestV1.fromCanonicalBytes(
        utf8.encode(firstLaunch['fullBody']! as String),
      );
      expect(body.startup, isTrue);
      expect(body.buildContract.buildOrdinal, _ordinal);
      expect(
        body.appBuildContractHash,
        body.buildContract.appBuildContractHash,
      );
      expect(_hash(contract), isNot(body.appBuildContractHash));
    });
  }
}
