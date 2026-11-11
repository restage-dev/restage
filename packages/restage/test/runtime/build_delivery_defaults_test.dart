import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/early/early_request.dart';
import 'package:restage/src/resolver/surface_delivery_observations.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/placement_delivery_fixture.dart';
import '../support/restage_runtime_test_support.dart';
import 'fixtures/catalog_options_delivery.g.dart' as delivery;
import 'fixtures/catalog_options_full.g.dart' as offline;

const _buildKey = 'rs_pk_sandbox_dev_build';
const _buildUrl = 'https://build.example.com';
const _resolve = '$_buildUrl/sdk/v1/placements/resolve';

/// A registration carrying a URL written with a trailing slash.
final class _SlashedSetup
    implements RestageWidgetRegistration, RestageBuildDelivery {
  const _SlashedSetup();

  @override
  String get apiKey => _buildKey;

  @override
  String get baseUrl => '$_buildUrl/';

  @override
  String? get channel => null;

  @override
  bool get analyticsEnabled => true;

  @override
  void call({required bool includeMaterial, required bool includeCupertino}) {}
}

/// A generated setup with `analytics: false` and no key in build.yaml.
final class _KeylessAnalyticsOff
    implements RestageWidgetRegistration, RestageBuildAnalytics {
  const _KeylessAnalyticsOff();

  @override
  bool get analyticsEnabled => false;

  @override
  void call({required bool includeMaterial, required bool includeCupertino}) {}
}

GeneratedPlacementDefinition _placement() =>
    RestagePaywall.generatedPlacementDefinition(
      id: 'offer',
      defaultSurfaceLocatorJson: DeliverySurfaceLocatorV1(
        surfaceType: DeliverySurfaceTypeId('paywall'),
        slug: 'offer',
        family: const DeliveryFamilySelectorV1.general(),
      ).toJson(),
      hostContractJson: SurfaceHostContractV1(
        hosting: const SurfaceHostingV1(
          contentKind: SurfaceContentKindV1.single,
          presentation: SurfacePresentationV1.inline,
        ),
        providedContext: const SurfaceScreenHostDataSchema.empty(),
        handledEvents: SurfaceScreenEventSchema(events: const []),
      ).toJson(),
      vocabulary: SurfaceVocabulary.none,
    );

void _configure({
  String? apiKey,
  String? baseUrl,
  RestageWidgetRegistration? registerWidgets,
  bool installedCatalog = false,
  List<RestageSurfaceRef> surfaces = const [],
}) {
  if (installedCatalog) {
    Restage.configureWithInstalledCatalog(
      apiKey: apiKey,
      baseUrl: baseUrl,
      registerWidgets: registerWidgets,
      surfaces: surfaces,
      analyticsEnabled: false,
      measurementEnabled: false,
      deliveryReceiptsEnabled: false,
    );
  } else {
    Restage.configure(
      apiKey: apiKey,
      baseUrl: baseUrl,
      registerWidgets: registerWidgets,
      surfaces: surfaces,
      analyticsEnabled: false,
      measurementEnabled: false,
      deliveryReceiptsEnabled: false,
    );
  }
}

void main() {
  installRestageRuntimeTestSupport();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Restage.debugReset();
    InstalledWidgetLibraries.reset();
    InstalledIconTable.reset();
  });
  tearDown(() {
    Restage.debugReset();
    InstalledWidgetLibraries.reset();
    InstalledIconTable.reset();
  });

  for (final installedCatalog in [false, true]) {
    final entry = installedCatalog ? 'installed catalog' : 'configure';

    test('$entry uses the key, URL and channel the build sets', () {
      _configure(
        registerWidgets: delivery.kRestageWidgetRegistration,
        installedCatalog: installedCatalog,
      );
      expect(Restage.debugApiKey, _buildKey);
      expect(Restage.debugBaseUrl, _buildUrl);
      expect(inMemorySurfaceDeliveryObservations().$1.channel, 'beta');
      expect(InstalledWidgetLibraries.hasSelection, isTrue);
    });

    test('$entry prefers an explicit key and URL', () {
      _configure(
        apiKey: 'rs_pk_sandbox_dev_explicit',
        baseUrl: 'https://explicit.example.com',
        registerWidgets: delivery.kRestageWidgetRegistration,
        installedCatalog: installedCatalog,
      );
      expect(Restage.debugApiKey, 'rs_pk_sandbox_dev_explicit');
      expect(Restage.debugBaseUrl, 'https://explicit.example.com');
    });

    test('$entry stays offline for an empty key', () {
      _configure(
        apiKey: '',
        registerWidgets: delivery.kRestageWidgetRegistration,
        installedCatalog: installedCatalog,
      );
      expect(Restage.debugApiKey, isNull);
      expect(Restage.debugBaseUrl, isNull);
    });

    test('$entry is offline when the build sets no key', () {
      _configure(
        registerWidgets: offline.kRestageWidgetRegistration,
        installedCatalog: installedCatalog,
      );
      expect(Restage.debugApiKey, isNull);
      expect(Restage.debugBaseUrl, isNull);
    });

    test('$entry takes a URL with a trailing slash in canonical form', () {
      _configure(
        registerWidgets: const _SlashedSetup(),
        installedCatalog: installedCatalog,
      );
      expect(Restage.debugBaseUrl, _buildUrl);
      Restage.debugReset();
      _configure(
        apiKey: _buildKey,
        baseUrl: '$_buildUrl//',
        installedCatalog: installedCatalog,
      );
      expect(Restage.debugBaseUrl, _buildUrl);
    });
  }

  group('the choice kept for the next first-launch request', () {
    late List<({bool hosted, bool? analytics})> saved;
    late List<bool> measured;
    setUp(() {
      saved = [];
      measured = [];
      EarlyRequest.choiceRecorder = ({
        required hosted,
        required analytics,
        required measurement,
      }) {
        saved.add((hosted: hosted, analytics: analytics));
        measured.add(measurement);
      };
    });
    tearDown(() {
      EarlyRequest.choiceRecorder = null;
      EarlyRequest.debugBindingExists = null;
    });

    void configureNow({
      String? apiKey,
      bool? analyticsEnabled,
      RestageWidgetRegistration? registerWidgets,
      bool installedCatalog = false,
    }) =>
        installedCatalog
            ? Restage.configureWithInstalledCatalog(
                apiKey: apiKey,
                analyticsEnabled: analyticsEnabled,
                registerWidgets: registerWidgets,
                measurementEnabled: false,
                deliveryReceiptsEnabled: false,
              )
            : Restage.configure(
                apiKey: apiKey,
                analyticsEnabled: analyticsEnabled,
                registerWidgets: registerWidgets,
                measurementEnabled: false,
                deliveryReceiptsEnabled: false,
              );

    Future<void> configure({
      String? apiKey,
      bool? analyticsEnabled,
      RestageWidgetRegistration? registerWidgets,
      bool installedCatalog = false,
    }) async {
      configureNow(
        apiKey: apiKey,
        analyticsEnabled: analyticsEnabled,
        registerWidgets: registerWidgets,
        installedCatalog: installedCatalog,
      );
      await pumpEventQueue();
    }

    for (final installedCatalog in [false, true]) {
      final entry = installedCatalog ? 'installed catalog' : 'configure';

      test("$entry keeps the app's own choice and leaves the rest to the build",
          () async {
        await configure(
          registerWidgets: delivery.kRestageWidgetRegistration,
          installedCatalog: installedCatalog,
        );
        await configure(
          registerWidgets: delivery.kRestageWidgetRegistration,
          analyticsEnabled: true,
          installedCatalog: installedCatalog,
        );
        expect(saved, [
          (hosted: true, analytics: null),
          (hosted: true, analytics: true),
        ]);
      });

      test('$entry keeps offline when it has no key', () async {
        await configure(
          apiKey: '',
          registerWidgets: delivery.kRestageWidgetRegistration,
          installedCatalog: installedCatalog,
        );
        await configure(installedCatalog: installedCatalog);
        expect(saved, [
          (hosted: false, analytics: null),
          (hosted: false, analytics: null),
        ]);
      });
    }

    test('an app that changes nothing keeps hosted', () async {
      Restage.configure(apiKey: _buildKey, baseUrl: _buildUrl);
      await pumpEventQueue();
      expect(saved, [(hosted: true, analytics: null)]);
    });

    test('the measurement setting is kept beside the choice', () async {
      Restage.configure(apiKey: _buildKey, baseUrl: _buildUrl);
      await pumpEventQueue();
      Restage.configure(
        apiKey: _buildKey,
        baseUrl: _buildUrl,
        measurementEnabled: false,
      );
      await pumpEventQueue();
      expect(measured, [true, false]);
    });

    test('the last of several configures is the one kept', () async {
      configureNow(
          registerWidgets: delivery.kRestageWidgetRegistration,
          analyticsEnabled: true);
      configureNow(
          registerWidgets: delivery.kRestageWidgetRegistration,
          analyticsEnabled: false);
      await pumpEventQueue();
      expect(saved, [(hosted: true, analytics: false)]);
    });

    test('a choice made before the binding never lands after a later one',
        () async {
      var exists = false;
      EarlyRequest.debugBindingExists = () => exists;
      // Before runApp: this save waits for the binding.
      configureNow(
          registerWidgets: delivery.kRestageWidgetRegistration,
          analyticsEnabled: true);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      exists = true;
      configureNow(
          registerWidgets: delivery.kRestageWidgetRegistration,
          analyticsEnabled: false);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(saved, [(hosted: true, analytics: false)]);
    });

    testWidgets('a binding that comes within the wait still gets the choice',
        (tester) async {
      var exists = false;
      EarlyRequest.debugBindingExists = () => exists;
      unawaited(EarlyRequest.saveChoice(hosted: true, analytics: false));
      await tester.pump(EarlyRequest.bindingWait - const Duration(seconds: 1));
      expect(saved, isEmpty);
      exists = true;
      await tester.pump(const Duration(milliseconds: 100));
      expect(saved, [(hosted: true, analytics: false)]);
    });

    testWidgets('a binding that never comes drops the choice after the wait',
        (tester) async {
      var exists = false;
      EarlyRequest.debugBindingExists = () => exists;
      unawaited(EarlyRequest.saveChoice(hosted: true, analytics: false));
      await tester.pump(EarlyRequest.bindingWait + const Duration(seconds: 1));
      exists = true;
      await tester.pump(const Duration(seconds: 1));
      expect(saved, isEmpty);
      // The next choice starts a new wait and is kept.
      unawaited(EarlyRequest.saveChoice(hosted: false));
      await tester.pump(const Duration(milliseconds: 100));
      expect(saved, [(hosted: false, analytics: null)]);
    });
  });

  group("the build's analytics default", () {
    void configure({
      bool? analyticsEnabled,
      RestageWidgetRegistration? registerWidgets,
    }) =>
        Restage.configure(
          apiKey: _buildKey,
          baseUrl: _buildUrl,
          analyticsEnabled: analyticsEnabled,
          registerWidgets: registerWidgets,
          measurementEnabled: false,
          deliveryReceiptsEnabled: false,
        );

    test('reaches a key set in code', () {
      configure(registerWidgets: const _KeylessAnalyticsOff());
      expect(Restage.debugAnalyticsEnabled, isFalse);
      configure(
        registerWidgets: const _KeylessAnalyticsOff(),
        analyticsEnabled: true,
      );
      expect(Restage.debugAnalyticsEnabled, isTrue);
    });

    test('declared by registerRestageWidgets() before configure applies', () {
      Restage.declareBuildAnalytics(enabled: false);
      configure();
      expect(Restage.debugAnalyticsEnabled, isFalse);
      configure(analyticsEnabled: true);
      expect(Restage.debugAnalyticsEnabled, isTrue);
    });

    test('declared after configure is reported, unless the app chose', () {
      final reported = <String>[];
      final previous = FlutterError.onError;
      FlutterError.onError = (details) => reported.add('${details.exception}');
      addTearDown(() => FlutterError.onError = previous);
      configure(analyticsEnabled: true);
      Restage.declareBuildAnalytics(enabled: false);
      expect(reported, isEmpty);
      Restage.debugReset();
      configure();
      Restage.declareBuildAnalytics(enabled: false);
      expect(reported, [
        contains(Restage.buildAnalyticsAfterConfigureMessage),
      ]);
    });
  });

  group('a kept first-launch template', () {
    final build = readPlacementDeliveryFixture().request.buildContract;
    final request = startupRequestFor(
      platform: 'android',
      mounts: build.mounts.toList(),
      contractsByHash: build.contractsByHash,
      capability: build.installedCapability,
      builtIns: const {'platform': 'android'},
    );
    Map<String, Object?> kept() => jsonDecode(
          EarlyRequest.rememberedTemplate(
              Uri.parse(_resolve), _buildKey, request)!,
        ) as Map<String, Object?>;

    test("carries the build's analytics default, not the app's choice", () {
      Restage.configure(
        apiKey: _buildKey,
        baseUrl: _buildUrl,
        registerWidgets: const _KeylessAnalyticsOff(),
        analyticsEnabled: true,
      );
      // A launch that ends before its choice is saved sends analytics off.
      expect(kept()['analytics'], isFalse);
      Restage.debugReset();
      Restage.configure(apiKey: _buildKey, baseUrl: _buildUrl);
      expect(kept()['analytics'], isTrue);
    });

    test("carries the app's measurement setting", () {
      Restage.configure(
        apiKey: _buildKey,
        baseUrl: _buildUrl,
        measurementEnabled: false,
      );
      expect(kept()['measurement'], isFalse);
      Restage.debugReset();
      Restage.configure(apiKey: _buildKey, baseUrl: _buildUrl);
      expect(kept()['measurement'], isTrue);
    });
  });

  test('a blank URL is no URL', () {
    _configure(apiKey: 'rs_pk_sandbox_dev_x', baseUrl: ' ');
    expect(Restage.debugBaseUrl, isNull);
  });

  group('debug check of the built-in first-launch request', () {
    late List<String> reported;
    late FlutterExceptionHandler? previous;
    String template(String key, {String url = _resolve}) =>
        jsonEncode({'url': url, 'authorization': 'Bearer $key'});

    setUp(() {
      reported = [];
      previous = FlutterError.onError;
      FlutterError.onError = (details) => reported.add('${details.exception}');
    });
    tearDown(() {
      FlutterError.onError = previous;
      EarlyRequest.debugTemplate = null;
      debugDefaultTargetPlatformOverride = null;
    });

    Future<void> configureWith(
      String? builtIn, {
      String? apiKey,
      String? baseUrl,
      RestageWidgetRegistration? registerWidgets,
      bool installedCatalog = false,
      List<RestageSurfaceRef> surfaces = const [],
    }) async {
      EarlyRequest.debugTemplate = () async => builtIn;
      _configure(
        apiKey: apiKey,
        baseUrl: baseUrl,
        registerWidgets: registerWidgets,
        installedCatalog: installedCatalog,
        surfaces: surfaces,
      );
      await pumpEventQueue();
    }

    test('a built-in request with no key names the call to fix', () async {
      await configureWith(template(_buildKey));
      await configureWith(template(_buildKey), installedCatalog: true);
      expect(reported, [
        contains(
          unusedEarlyTemplateMessage(
            entry: 'Restage.configure',
            registered: false,
          ),
        ),
        contains(
          unusedEarlyTemplateMessage(
            entry: 'Restage.configureWithInstalledCatalog',
            registered: false,
          ),
        ),
      ]);
      expect(
        reported.last,
        contains(
          'Try passing `registerWidgets: kRestageWidgetRegistration` to '
          '`Restage.configureWithInstalledCatalog`.',
        ),
      );
    });

    test('a built-in request with a keyless setup says to rebuild', () async {
      await configureWith(
        template(_buildKey),
        registerWidgets: offline.kRestageWidgetRegistration,
      );
      expect(reported, [
        contains('its generated setup has no publishable key'),
      ]);
      expect(reported.single, isNot(contains('Try passing')));
    });

    test('an explicit empty key is offline on purpose', () async {
      await configureWith(template(_buildKey), apiKey: '');
      expect(reported, isEmpty);
    });

    test('no built-in request and no key reports nothing', () async {
      await configureWith(null);
      expect(reported, isEmpty);
    });

    test('the generated setup matches its own request', () async {
      await configureWith(
        template(_buildKey),
        registerWidgets: delivery.kRestageWidgetRegistration,
      );
      expect(reported, isEmpty);
    });

    test('a URL that differs only by its path is reported', () async {
      await configureWith(
        template(_buildKey),
        apiKey: _buildKey,
        baseUrl: '$_buildUrl/api',
      );
      expect(reported, [
        contains(
          'URL (built for $_resolve, configured '
          '$_buildUrl/api/sdk/v1/placements/resolve)',
        ),
      ]);
    });

    test('a request built for another key is reported', () async {
      await configureWith(
        template('rs_pk_sandbox_dev_other'),
        registerWidgets: delivery.kRestageWidgetRegistration,
      );
      expect(reported, [contains('publishable key')]);
    });

    test('a missing request with an explicit key says to set the key',
        () async {
      await configureWith(
        null,
        apiKey: _buildKey,
        baseUrl: _buildUrl,
        surfaces: [_placement()],
      );
      expect(reported, [contains(kMissingEarlyTemplateMessage)]);
    });

    test('a missing request with the setup names the bundle step', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await configureWith(
        null,
        registerWidgets: delivery.kRestageWidgetRegistration,
        surfaces: [_placement()],
      );
      expect(reported, [
        contains(missingBuiltTemplateMessage(ios: true)),
      ]);
      expect(
        reported.single,
        contains('`ios/Runner/restage_early.json` under `flutter: assets:`'),
      );
    });

    test('a build with no placements needs no request', () async {
      await configureWith(
        null,
        registerWidgets: delivery.kRestageWidgetRegistration,
      );
      expect(reported, isEmpty);
    });
  });

  group('first-launch request reports', () {
    test('match reports nothing', () {
      expect(
        earlyTemplateMismatchMessage(
          builtUrl: _resolve,
          configuredUrl: _resolve,
          sameKey: true,
          entry: 'Restage.configure',
        ),
        isNull,
      );
    });

    test('a different URL and key are both named, with a Try', () {
      final message = earlyTemplateMismatchMessage(
        builtUrl: _resolve,
        configuredUrl: 'https://other.example.com/sdk/v1/placements/resolve',
        sameKey: false,
        entry: 'Restage.configure',
      )!;
      expect(message, contains('and publishable key than Restage.configure'));
      expect(message, contains('Try passing `registerWidgets: '));
      expect(message, isNot(contains(_buildKey)));
    });

    test('a missing template says how to build one', () {
      expect(kMissingEarlyTemplateMessage, contains('Try '));
      expect(kMissingEarlyTemplateMessage, contains('--sdk-key'));
      expect(missingBuiltTemplateMessage(ios: false), contains('Try running'));
    });
  });
}
