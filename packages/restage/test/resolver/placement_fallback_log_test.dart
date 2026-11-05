import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:restage/src/measurement/measurement_refusal_reason.dart';
import 'package:restage/src/resolver/placement_fallback_log.dart';
import 'package:restage/src/runtime/library_runtime_registry.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';

void main() {
  test('a placement fallback logs once per reason', () {
    final lines = <String>[];
    final previous = debugPrint;
    debugPrint = (message, {wrapWidth}) => lines.add(message!);
    addTearDown(() {
      debugPrint = previous;
      resetPlacementFallbackLog();
    });
    final key = PlacementKeyV1.named(slug: 'home_card');
    debugLogPlacementFallback(key, PlacementBatchRefusalReasonV1.unavailable);
    debugLogPlacementFallback(key, PlacementBatchRefusalReasonV1.unavailable);
    debugLogPlacementFallback(
        key, PlacementBatchRefusalReasonV1.invalidAuthority);
    expect(lines, hasLength(2));
    expect(lines.first, startsWith('[restage] placement named:home_card'));
    expect(lines.first, contains('(unavailable)'));
    expect(lines.last, contains('(invalidAuthority)'));
    debugLogPlacementFallback(key, PlacementBatchRefusalReasonV1.unavailable,
        detail: 'noPublication');
    expect(lines.last, contains('(unavailable:noPublication)'));
    expect(
        placementFallbackReason(
            PlacementBatchRefusalReasonV1.unavailable, 'fitUnavailable'),
        'unavailable:fitUnavailable');
  });

  test('an upload refusal yields only a bounded reason', () {
    List<int> body(Object value) => utf8.encode(jsonEncode(value));
    expect(
        measurementRefusalReason(
            body({'error': 'invalid_request', 'reason': 'unknownBinding'})),
        'unknownBinding');
    expect(measurementRefusalReason(body({'error': 'invalid_request'})),
        'invalid_request');
    expect(measurementRefusalReason(body({'reason': 'a b'})), isNull);
    expect(measurementRefusalReason(body({'reason': 'x' * 65})), isNull);
    expect(measurementRefusalReason(utf8.encode('not json')), isNull);
    expect(measurementRefusalLogLine(400, 'unknownBinding'),
        '[restage] measurement upload refused (HTTP 400): unknownBinding');
  });

  group('fallback causes', () {
    final endpoint =
        Uri.parse('https://api.example.com/sdk/v1/placements/resolve');
    final key = PlacementKeyV1.generatedDefault(
        surfaceType: DeliverySurfaceTypeId('onboarding'), slug: 'welcome');
    late List<String> lines;
    late DebugPrintCallback original;

    setUp(() {
      resetPlacementFallbackLog();
      lines = [];
      original = debugPrint;
      debugPrint = (message, {wrapWidth}) => lines.add(message ?? '');
    });
    tearDown(() => debugPrint = original);

    const prefix = '[restage] placement default:onboarding:welcome '
        'shows its fallback';

    const docs = 'https://docs.restage.dev';
    const libraryDocs =
        '$docs/authoring/custom-widgets#3-declare-exact-library-ownership';
    const configDocs = '$docs/delivery/hosted-delivery#configure-delivery';
    const published =
        PublishedSurfaceLabel(type: 'message', slug: 'spring-sale', version: 7);
    const republish = 'Push and publish it again from this build: `restage '
        'surface push spring-sale`, then `restage surface publish '
        'spring-sale`.';

    String token(SurfaceFitFailureCodeV1 code, String path, Object? required,
            [Object? available]) =>
        SurfaceFitFailureV1(
                code: code,
                path: path,
                required: required,
                available: available)
            .token;

    test('a timeout names the host and its duration', () {
      debugLogPlacementNoAnswer(
          key,
          'offline',
          PlacementNoAnswerCause.of(
              TimeoutException('No response', const Duration(seconds: 8)),
              endpoint));
      expect(
          lines.single,
          "$prefix (offline): the service at api.example.com didn't answer "
          "within 8 s. Check the device's network and `baseUrl`. It's "
          'retried on the next mount.');
    });

    test('a failed connection names the host and the error', () {
      debugLogPlacementNoAnswer(
          key,
          'offline',
          PlacementNoAnswerCause.of(
              http.ClientException('Connection refused'), endpoint));
      expect(
          lines.single,
          "$prefix (offline): couldn't connect to api.example.com "
          "(Connection refused). Check `baseUrl` and the device's network. "
          "It's retried on the next mount. See $configDocs");
    });

    test('a loopback host on Android names the adb port forward', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final cause = PlacementNoAnswerCause.of(
          http.ClientException('Connection refused'),
          Uri.parse('http://localhost:8080/sdk/v1/placements/resolve'));
      expect(
          cause.describe(),
          "couldn't connect to localhost (Connection refused). Check "
          "`baseUrl` and the device's network. On Android, run `adb reverse "
          'tcp:8080 tcp:8080` to let the device or emulator reach localhost '
          "on this computer. It's retried on the next mount. See $configDocs");
    });

    test('a status names the host, status, code and fix', () {
      debugLogPlacementNoAnswer(
          key, 'serverError', PlacementNoAnswerStatus(503, endpoint: endpoint));
      debugLogPlacementNoAnswer(
          key,
          'redirected',
          PlacementNoAnswerStatus(308,
              endpoint: endpoint,
              location: 'https://api2.example.com/sdk/v1/placements/resolve'));
      debugLogPlacementNoAnswer(
          key,
          'throttled',
          PlacementNoAnswerStatus(429,
              endpoint: endpoint, retryAfter: const Duration(seconds: 30)));
      debugLogPlacementNoAnswer(key, 'notFound',
          PlacementNoAnswerStatus(404, endpoint: endpoint, error: 'not_found'));
      debugLogPlacementNoAnswer(
          key, 'forbidden', PlacementNoAnswerStatus(403, endpoint: endpoint));
      debugLogPlacementNoAnswer(
          key, 'badRequest', PlacementNoAnswerStatus(400, endpoint: endpoint));
      expect(lines, [
        '$prefix (serverError): the service at api.example.com returned a '
            "server error (HTTP 503). It's retried on the next mount.",
        '$prefix (redirected): the service at api.example.com redirected the '
            'request (HTTP 308 to '
            'https://api2.example.com/sdk/v1/placements/resolve), and the SDK '
            "doesn't follow redirects. Set `baseUrl` to "
            'https://api2.example.com. See $configDocs',
        '$prefix (throttled): the service at api.example.com is rate '
            'limiting this app (HTTP 429). Retry after 30 s.',
        '$prefix (notFound): the service at api.example.com has no placement '
            'route at https://api.example.com/sdk/v1/placements/resolve (HTTP '
            '404, `not_found`). Set `baseUrl` to the API URL alone, with no '
            'path. See $configDocs',
        '$prefix (forbidden): the service at api.example.com refused the '
            'request (HTTP 403). Check `baseUrl`, and any proxy, firewall or '
            'access policy in front of it. See $configDocs',
        '$prefix (badRequest): the service at api.example.com rejected the '
            'request (HTTP 400) without a placement answer. Check that the '
            'restage package (2.0.0) and the service are current.',
      ]);
    });

    test('only a 401 blames the API key', () {
      expect(
          PlacementNoAnswerStatus(401, endpoint: endpoint).describe(),
          'the service at api.example.com refused the API key (HTTP 401). '
          'Set `apiKey` to the public SDK key (rs_pk_...) for this '
          'environment. See $configDocs');
      expect(
          PlacementNoAnswerStatus(403,
                  endpoint: endpoint, error: 'edge_required')
              .describe(),
          'the service at api.example.com accepts SDK requests only at its '
          'public API address (HTTP 403, `edge_required`). Set `baseUrl` to '
          "your environment's API URL. See $configDocs");
      expect(
          PlacementNoAnswerStatus(403,
                  endpoint: endpoint, error: 'client_network_unavailable')
              .describe(),
          'the service at api.example.com refused the request (HTTP 403, '
          '`client_network_unavailable`). Check `baseUrl`, and any proxy, '
          'firewall or access policy in front of it. See $configDocs');
    });

    test('printed addresses drop credentials, query and fragment', () {
      final secret = Uri.parse('https://user:pass@api.example.com'
          '/sdk/v1/placements/resolve?token=x#top');
      final notFound =
          PlacementNoAnswerStatus(404, endpoint: secret).describe();
      expect(
          notFound,
          contains('at https://api.example.com/sdk/v1/placements'
              '/resolve (HTTP 404)'));
      final redirect = PlacementNoAnswerStatus(301,
              endpoint: secret,
              location: 'https://user:pass@api2.example.com/sdk/v1/placements'
                  '/resolve?token=x#top')
          .describe();
      expect(
          redirect,
          contains('(HTTP 301 to https://api2.example.com/sdk/v1/'
              'placements/resolve)'));
      expect(redirect, contains('Set `baseUrl` to https://api2.example.com.'));
      for (final text in [notFound, redirect]) {
        expect(text, isNot(contains('pass')));
        expect(text, isNot(contains('token')));
        expect(text, isNot(contains('#top')));
      }
    });

    test('a malformed location reads as no location', () {
      expect(
          PlacementNoAnswerStatus(302,
                  endpoint: endpoint, location: 'http://[::1')
              .describe(),
          'the service at api.example.com redirected the request (HTTP 302), '
          "and the SDK doesn't follow redirects. Set `baseUrl` to the address "
          'it redirects to. See $configDocs');
    });

    test('a redirect with no location says where to look', () {
      expect(
          PlacementNoAnswerStatus(301, endpoint: endpoint).describe(),
          'the service at api.example.com redirected the request (HTTP 301), '
          "and the SDK doesn't follow redirects. Set `baseUrl` to the address "
          'it redirects to. See $configDocs');
    });

    test('an unusable answer with no fit tokens names the version', () {
      debugLogPlacementNoAnswer(key, 'unsupported',
          const PlacementNoAnswerUnrenderable([], published: published));
      expect(
          lines.single,
          "$prefix (unsupported): this mount couldn't use the published "
          "message `spring-sale` r7. It's retried on the next mount.");
    });

    test('an unreadable answer names the SDK version', () {
      debugLogPlacementNoAnswer(
          key, 'decodeFailed', const PlacementNoAnswerUndecodable());
      expect(
          lines.single,
          "$prefix (decodeFailed): the delivered content couldn't be read by "
          'restage 2.0.0. Update the restage package, and check that the '
          'service is current.');
    });

    test('a dropped request says what changed', () {
      expect(
          const PlacementNoAnswerStale(PlacementStaleChange.installedWidgets)
              .describe(),
          'a widget library was registered while the request was being '
          'made. The request was dropped. Register libraries before the '
          "first mount. It's retried on the next mount.");
      expect(
          const PlacementNoAnswerStale(PlacementStaleChange.configuration)
              .describe(),
          "Restage's configuration, user identity or consent changed while "
          'the request was being made. The request was dropped. '
          "It's retried on the next mount.");
    });

    test('an unsaved experiment registration names the storage', () {
      debugLogPlacementNoAnswer(
          key, 'enrollmentRequired', const PlacementNoAnswerUnregistered());
      expect(
          lines.single,
          "$prefix (enrollmentRequired): this device's experiment "
          "registration couldn't be saved. The request wasn't sent. Restage "
          'saves the registration with shared_preferences. Check that the '
          'plugin works in this app. In tests, call '
          "`SharedPreferences.setMockInitialValues({})`. It's retried on the "
          'next mount.');
    });

    test('a late experiment registration names the deadline', () {
      expect(
          const PlacementNoAnswerUnregistered(late: true).describe(),
          "this device's experiment registration wasn't saved within 2 s. "
          "The request wasn't sent. Restage saves the registration with "
          'shared_preferences. Check that it answers quickly on this device. '
          "It's retried on the next mount.");
    });

    test('a build that sent no vocabulary says so in separate sentences', () {
      expect(
          describeFitTokens(['missingInstalledVocabulary'],
              published: published),
          "the service got no list of this build's widgets and icons. It "
          "couldn't check the published message `spring-sale` r7 against "
          'them. This SDK (restage 2.0.0) sends one. Check that the service '
          'and the restage package are current.');
    });

    test('a declined request with a refusal name uses its hint', () {
      debugLogPlacementNoAnswer(key, 'enrollmentRequired');
      expect(
          lines.single,
          '$prefix (enrollmentRequired): an experiment needs an assignment '
          'key. Check identity setup.');
    });

    test('library tokens carry what the build has', () {
      const path = r'$.capabilities.requiredLibraries.acme.ui';
      const requirement = {'namespace': 'acme.ui', 'minVersion': 3};
      expect(token(SurfaceFitFailureCodeV1.missingLibrary, path, requirement),
          'missingLibrary:acme.ui@3');
      expect(
          token(SurfaceFitFailureCodeV1.missingLibrary, path, requirement,
              {'namespace': 'acme.ui', 'version': null}),
          'missingLibrary:acme.ui@3;unversioned');
      expect(
          token(SurfaceFitFailureCodeV1.oldLibrary, path, requirement,
              {'namespace': 'acme.ui', 'version': 2}),
          'oldLibrary:acme.ui@3;2/1');
      expect(
          token(
              SurfaceFitFailureCodeV1.oldLibrary,
              path,
              {'namespace': 'acme.ui', 'minVersion': 3, 'minGenerated': 2},
              {'namespace': 'acme.ui', 'version': 3}),
          'oldLibrary:acme.ui@3/2;3/1');
      expect(
          token(
              SurfaceFitFailureCodeV1.brokenLibrary,
              path,
              {'namespace': 'acme.ui', 'minVersion': 2},
              {'namespace': 'acme.ui', 'version': 4, 'compatibleSince': 4}),
          'brokenLibrary:acme.ui@2;4,4');
    });

    test('each library gap names versions and the fix', () {
      String describe(String token) =>
          describeFitTokens([token], published: published);
      expect(
          describe('missingLibrary:acme.ui@3'),
          'the published message `spring-sale` r7 needs the widget library '
          "`acme.ui` v3, which this build doesn't register. Add the "
          'package that provides it to the app, then run `dart run '
          'build_runner build`. See $libraryDocs');
      expect(
          describe('missingLibrary:acme.ui@3;unversioned'),
          'the published message `spring-sale` r7 needs the widget library '
          '`acme.ui` v3, but this build registers it without a capability '
          'version. Set `capabilityVersion` on its `@RestageLibrary` and run '
          '`dart run build_runner build`. See $libraryDocs');
      expect(
          describe('oldLibrary:acme.ui@3;2/1'),
          'the published message `spring-sale` r7 needs `acme.ui` v3; this '
          'build has v2. Update the package that provides `acme.ui` to the '
          'release with capability version 3, then run `dart run '
          'build_runner build`. See $libraryDocs');
      expect(
          describe('oldLibrary:acme.ui@3/2;3/1'),
          "the published message `spring-sale` r7 needs `acme.ui`'s "
          "generated code at v2; this build's is v1. Update restage_codegen, "
          'then run `dart run build_runner build`. See $libraryDocs');
      expect(
          describe('brokenLibrary:acme.ui@2;4,4'),
          'the published message `spring-sale` r7 was built against '
          "`acme.ui` v2, but this build's `acme.ui` v4 declares a break "
          '(compatibleSince: 4). $republish See $libraryDocs');
    });

    test('widget app-code gaps name the widget by its label', () {
      const name = 'app.islands:paywall__screen_ListView_0';
      for (final (code, clause) in [
        (
          SurfaceFitFailureCodeV1.missingIsland,
          "this build doesn't include its app code.",
        ),
        (
          SurfaceFitFailureCodeV1.changedIsland,
          'this build changed its app code.',
        ),
      ]) {
        final fit = token(
            code, '\$.requiredIslands.$name', 'ListView in PaywallScreen');
        final described = describeFitTokens([fit], published: published);
        expect(
            described,
            'the published message `spring-sale` r7 doesn\'t fit this build: '
            'ListView in PaywallScreen: $clause $republish',
            reason: fit);
        expect(described, isNot(contains('island')));
      }
    });

    test('a library gap is described from the token, not this device', () {
      LibraryRuntimeRegistry.clear();
      addTearDown(LibraryRuntimeRegistry.clear);
      // Registered after the request that the service judged was sent.
      LibraryRuntimeRegistry.register(
          const WidgetLibrary.custom('acme.ui'), const [],
          capabilityVersion: 1);
      expect(
          describeFitTokens(['missingLibrary:acme.ui@1/2']),
          startsWith('the published version needs the widget library '
              "`acme.ui` v1, which this build doesn't register."));
    });

    test('widget, icon and catalog gaps name the widget and glyph', () {
      const catalogDocs = '$docs/delivery/app-size'
          '#when-a-surface-uses-a-widget-you-dont-have';
      expect(
          token(SurfaceFitFailureCodeV1.missingIcon,
              r'$.requiredVocabulary.iconCodePoints.MaterialIcons', 0xe5f9),
          'missingIcon:MaterialIcons@0xe5f9');
      expect(
          describeFitTokens(['missingIcon:MaterialIcons@0xe5f9'],
              published: published),
          'the published message `spring-sale` r7 uses the MaterialIcons '
          "glyph 0xe5f9, which this build's icon set leaves out. Draw that "
          'icon once in a `@Screen` and run `dart run build_runner build`, '
          'or install the full catalog. See $catalogDocs');
      expect(
          describeFitTokens(['missingWidget:restage.material:ExpansionTile'],
              published: published),
          'the published message `spring-sale` r7 draws `ExpansionTile`, '
          "which this build's widget catalog leaves out. Draw it once in a "
          '`@Screen` and run `dart run build_runner build`, or install the '
          'full catalog. See $catalogDocs');
      expect(
          describeFitTokens(['missingWidget:acme.ui:VButton'],
              published: published),
          'the published message `spring-sale` r7 draws `VButton` from '
          "`acme.ui`, which this build's `acme.ui` doesn't include. "
          'Update the package that provides `acme.ui`, or annotate '
          '`VButton` with `@RestageWidget`, then run `dart run build_runner '
          'build`. See $libraryDocs');
      expect(
          token(SurfaceFitFailureCodeV1.builtInFloor,
              r'$.capabilities.builtInFloor', 17, 16),
          'builtInFloor@17;16');
      expect(
          token(SurfaceFitFailureCodeV1.builtInFloor,
              r'$.flowBoundary.actions.openPaywall.minClient', 17, 16),
          'builtInFloor:openPaywall@17;16');
      expect(
          describeFitTokens(['builtInFloor@17;16'], published: published),
          'the published message `spring-sale` r7 needs built-in widgets '
          'v17; this build (restage 2.0.0) has v16. Update the restage '
          'package to a release with built-in widgets v17.');
      expect(
          describeFitTokens(['builtInFloor:openPaywall@17;16']),
          "the published version's action `openPaywall` needs built-in "
          'widgets v17; this build (restage 2.0.0) has v16. Update the '
          'restage package to a release with built-in widgets v17.');
    });

    test('hosting and flow mode gaps name both sides', () {
      expect(
          token(SurfaceFitFailureCodeV1.hostingMismatch, r'$.hosting', {
            'contentKind': 'flow',
            'allowedPresentations': ['presented'],
          }, {
            'contentKind': 'single',
            'presentation': 'inline'
          }),
          'hostingMismatch@flow/presented;single/inline');
      expect(
          describeFitTokens(['hostingMismatch@flow/presented;single/inline'],
              published: published),
          'the published message `spring-sale` r7 is a flow as a route, but '
          'this placement shows a single screen inline. Point this placement '
          'at a single screen inline, or mount the surface from a placement '
          'that shows a flow. See '
          '$docs/delivery/placements#present-a-placement-as-a-route');
      expect(
          token(SurfaceFitFailureCodeV1.deliveryModeMismatch,
              r'$.flowBoundary.deliveryMode', 'general', 'typed'),
          'deliveryModeMismatch@general;typed');
      expect(
          describeFitTokens(['deliveryModeMismatch@general;typed'],
              published: published),
          'the published message `spring-sale` r7 is a general flow, but this '
          'build declares it typed. $republish Setting `delivery: '
          'FlowDeliveryMode.general` on its `@FlowGraph` and releasing the '
          'app fixes the flow mode alone. See '
          '$docs/flows/overview#what-you-can-change-without-an-app-release');
    });

    test('contract gaps name the field, event or action', () {
      expect(
          token(SurfaceFitFailureCodeV1.incompatibleHostField,
              r'$.requiredContext.user.age', {
            'kind': 'int'
          }, {
            'kind': 'nullable',
            'value': {'kind': 'string'},
          }),
          'incompatibleHostField:user.age@int;string?');
      expect(
          token(
              SurfaceFitFailureCodeV1.actionMismatch,
              r'$.flowBoundary.actions.openPaywall',
              {'contractVersion': 2},
              {'contractVersion': 1}),
          'actionMismatch:openPaywall@2;1');
      expect(
          token(SurfaceFitFailureCodeV1.resultMismatch,
              r'$.flowBoundary.outbound.terminalResult', {
            'plan': 'string',
            'trialDays': 'int',
          }, {
            'plan': 'string',
          }),
          'resultMismatch:trialDays');
      expect(
          describeFitTokens([
            'published@7',
            'missingHostField:user.name',
            'unhandledEvent:dismiss',
            'actionMismatch:openPaywall@2;1',
          ],
              published: const PublishedSurfaceLabel(
                  type: 'message', slug: 'spring-sale')),
          'the published message `spring-sale` r7 reads `user.name` from host '
          "data, which this placement doesn't pass. The published message "
          '`spring-sale` r7 sends the event `dismiss`, which this placement '
          "doesn't handle. The published message `spring-sale` r7 calls the "
          'host action `openPaywall` v2; this build provides v1. $republish '
          'See $docs/authoring/host-data'
          '#declare-the-data-as-constructor-parameters and '
          '$docs/flows/overview#screens-and-events and '
          '$docs/flows/host-actions#when-an-action-doesnt-match');
    });

    test('an action with the same version names what differs', () {
      expect(
          describeFitTokens(['actionMismatch:openPaywall@2;2/args,idempotent'],
              published: published),
          'the published message `spring-sale` r7 calls the host action '
          "`openPaywall` v2, whose arguments and idempotency differ from this "
          "build's v2. $republish See "
          '$docs/flows/host-actions#when-an-action-doesnt-match');
      expect(
          describeFitTokens(['actionMismatch:openPaywall@2;2'],
              published: published),
          startsWith('the published message `spring-sale` r7 calls the host '
              "action `openPaywall` v2, whose contract differs from this "
              "build's v2."));
    });

    test('a signal is fired by the flow and handled by the build', () {
      expect(
          describeFitTokens(['signalMismatch:checkoutDone'],
              published: published),
          'the published message `spring-sale` r7 fires the signal '
          "`checkoutDone`, which this build has no handler for. $republish "
          'See $docs/flows/overview#what-you-can-change-without-an-app-release');
    });

    test('a shared fix is printed once', () {
      final text = describeFitTokens(
          ['deliveryModeMismatch@general;typed', 'missingHostField:user.name'],
          published: published);
      expect(
          RegExp('Push and publish it again').allMatches(text), hasLength(1));
      expect(
          text,
          'the published message `spring-sale` r7 is a general flow, but this '
          'build declares it typed. The published message `spring-sale` r7 '
          "reads `user.name` from host data, which this placement doesn't "
          'pass. $republish Setting `delivery: FlowDeliveryMode.general` on '
          'its `@FlowGraph` and releasing the app fixes the flow mode alone. '
          'See '
          '$docs/flows/overview#what-you-can-change-without-an-app-release and '
          '$docs/authoring/host-data#declare-the-data-as-constructor-parameters');
    });

    test('a presentation-only gap names how to show it', () {
      expect(
          describeFitTokens(['hostingMismatch@single/presented;single/inline'],
              published: published),
          'the published message `spring-sale` r7 can only be shown as a '
          'route, but this placement shows it inline. Open this placement '
          'with `Restage.presentPlacement`, or change `presentation:` on its '
          'source annotation, then push and publish it again. See '
          '$docs/delivery/placements#present-a-placement-as-a-route');
      expect(
          describeFitTokens(['hostingMismatch@single/inline;single/presented'],
              published: published),
          startsWith('the published message `spring-sale` r7 can only be '
              'shown inline, but this placement shows it as a route. Mount '
              'this placement inline in a widget tree, or change '
              '`presentation:`'));
    });

    test('a library gap without this build\'s side names no version', () {
      expect(
          describeFitTokens(['oldLibrary:acme.ui@3/2'], published: published),
          'the published message `spring-sale` r7 needs `acme.ui` v3 with '
          "generated code v2, newer than this build's. Update the package "
          'that provides `acme.ui` and restage_codegen, then run `dart run '
          'build_runner build`. See $libraryDocs');
    });

    test('a bare widget token gives a general sentence', () {
      expect(
          describeFitTokens(['missingWidget'], published: published),
          'the published message `spring-sale` r7 draws a widget this build '
          "doesn't have. Install the full catalog, or draw it once in a "
          '`@Screen` and run `dart run build_runner build`. See $docs'
          '/delivery/app-size#when-a-surface-uses-a-widget-you-dont-have');
    });

    test('empty tokens fall back to the no-details sentence', () {
      const noDetails = "the published message `spring-sale` r7 doesn't fit "
          'this build, and the service sent no details. See '
          '$docs/delivery/hosted-delivery#when-a-version-cant-be-shown';
      expect(describeFitTokens([], published: published), noDetails);
      expect(
          describeFitTokens(['', 'published@7', ''],
              published: const PublishedSurfaceLabel(
                  type: 'message', slug: 'spring-sale')),
          noDetails);
      expect(
          describeFitTokens(['', 'missingHostField:user.name'],
              published: published),
          startsWith('the published message `spring-sale` r7 reads '
              '`user.name`'));
      debugLogPlacementFallback(key, PlacementBatchRefusalReasonV1.incompatible,
          detail: 'published@7', published: published);
      expect(lines.single, '$prefix (incompatible:published@7): $noDetails');
    });

    test('a malformed escape is shown as sent', () {
      expect(describeFitTokens(['missingIcon:My%FF@0x41']),
          startsWith('the published version uses the My%FF glyph 0x41'));
      expect(describeFitTokens(['missingIcon:My%ZZ@0x41']),
          startsWith('the published version uses the My%ZZ glyph 0x41'));
    });

    test('subjects escape the token separators', () {
      expect(
          token(SurfaceFitFailureCodeV1.missingIcon,
              r'$.requiredVocabulary.iconCodePoints.My Icons;2', 0x41),
          'missingIcon:My%20Icons%3B2@0x41');
      expect(describeFitTokens(['missingIcon:My%20Icons%3B2@0x41']),
          startsWith('the published version uses the My Icons;2 glyph 0x41'));
    });

    test('an incompatible decision names the surface and version', () {
      debugLogPlacementFallback(key, PlacementBatchRefusalReasonV1.incompatible,
          detail: 'published@7 oldLibrary:acme.ui@3;2/1',
          published: const PublishedSurfaceLabel(
              type: 'message', slug: 'spring-sale'));
      expect(
          lines.single,
          '$prefix (incompatible:published@7 oldLibrary:acme.ui@3;2/1): the '
          'published message `spring-sale` r7 needs `acme.ui` v3; this '
          'build has v2. Update the package that provides `acme.ui` to the '
          'release with capability version 3, then run `dart run '
          'build_runner build`. See $libraryDocs');
    });

    test('capability tokens name each unmet library', () {
      expect(
          capabilityFitTokens(
              CapabilityManifest(builtInFloor: 1, requiredLibraries: const [
                LibraryRequirement(
                    namespace: 'acme.ui', minVersion: 2, minGenerated: 2),
              ]),
              InstalledCapability(
                  builtInCatalogVersion: 1, installedLibraries: const [])),
          ['missingLibrary:acme.ui@2/2']);
    });
  });
}
