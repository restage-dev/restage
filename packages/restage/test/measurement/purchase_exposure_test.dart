import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/measurement/measurement_resolved_publication_provenance.dart';
import 'package:restage/src/measurement/restage_measurement.dart'
    show attachPurchaseExposure;
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:restage/src/resolver/surface_delivery_observations.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rfw/formats.dart';

import 'admitted_bundled_publication_fixture.dart';
import 'measurement_host_construction_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<Map<String, dynamic>> reports;
  late AdmittedBundledPublicationFixture fixture;
  late int status;
  late String responseBody;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Restage.debugReset();
    PackageInfo.setMockInitialValues(
        appName: 'test',
        packageName: 'test',
        version: '1',
        buildNumber: '1',
        buildSignature: '');
    debugResetAppBuildOrdinal();
    debugSetOsVersion(34);
    Restage.configure(analyticsEnabled: true, measurementEnabled: true);
    reports = [];
    status = 200;
    responseBody = '{"accepted":true,"replayed":false}';
    fixture = AdmittedBundledPublicationFixture.build();
    Restage.debugRestageRpcClient = RestageRpcClient(
      baseUrl: 'https://example.test',
      apiKey: 'public-test-key',
      httpClient: MockClient((request) async {
        expectSync(request.url.path, '/sdk/v1/measurement/purchases');
        expectSync(request.headers['Authorization'], 'Bearer public-test-key');
        reports.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response(responseBody, status);
      }),
    );
  });
  tearDown(Restage.debugReset);

  PaywallCustomEvent event(
      {String nonce = 'a', Future<void> Function()? flush}) {
    final event = PaywallCustomEvent(
        paywallId: 'upgrade', eventName: 'revenuecat.purchase', args: const {});
    final binding = fixture.binding.reference;
    attachPurchaseExposure(event, prepare: () async {
      await flush?.call();
      return (
        captureSessionNonce: nonce * 43,
        publicationBindingReference: binding
      );
    });
    return event;
  }

  Future<bool> report(RestageEvent event) =>
      Restage.measurement.reportPurchase(event,
          packageIdentifier: 'holiday_annual', productIdentifier: 'annual_49');

  test('reporting requires a runtime event and enabled Measurement', () async {
    final unbound = PaywallCustomEvent(
        paywallId: 'upgrade', eventName: 'revenuecat.purchase', args: const {});
    expect(await report(unbound), isFalse);
    final bound = event();
    Restage.configure(measurementEnabled: false);
    expect(await report(bound), isFalse);
    expect(reports, isEmpty);
  });

  test('an event retains its original exposure after a replacement event',
      () async {
    final delivered = Completer<void>();
    final original = event(flush: () => delivered.future);
    event(nonce: 'c');
    final pending = report(original);
    await Future<void>.delayed(Duration.zero);
    expect(reports, isEmpty);
    delivered.complete();
    expect(await pending, isTrue);
    final sent = reports.single;
    expect(sent['exposure'], {
      'captureSessionNonce': 'a' * 43,
      'publicationBindingReference': fixture.binding.reference.toJson(),
    });
    expect(
        sent.keys,
        unorderedEquals([
          'exposure',
          'eventId',
          'packageIdentifier',
          'productIdentifier',
          'reportedOccurredAtMicros',
        ]));
    expect(
        sent['eventId'],
        matches(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'));
    expect(sent['packageIdentifier'], 'holiday_annual');
    expect(sent['productIdentifier'], 'annual_49');
    expect(sent['reportedOccurredAtMicros'], isPositive);
  });

  test('an event reports once, including concurrent and different identifiers',
      () async {
    final original = event();
    expect(
        await Future.wait([report(original), report(original)]), [true, true]);
    expect(
        await Restage.measurement.reportPurchase(original,
            packageIdentifier: 'another', productIdentifier: 'annual_59'),
        isTrue);
    expect(reports, hasLength(1));
    expect(reports.single['packageIdentifier'], 'holiday_annual');
    expect(reports.single['productIdentifier'], 'annual_49');
  });

  test('emitted snapshots share the original purchase report state', () async {
    final original = event();
    final streamed = Restage.events.first;
    Restage.fireEvent(original);
    final emitted = await streamed;
    expect(emitted, isNot(same(original)));
    expect(
        await Future.wait([report(original), report(emitted)]), [true, true]);
    expect(reports, hasLength(1));
    expect(emitted.analyticsProperties.keys,
        isNot(contains(anyOf('exposure', 'restage_exposure'))));
    expect(emitted.toMap().keys, isNot(contains('exposure')));
  });

  test('an event keeps its first refused result without another request',
      () async {
    final original = event();
    status = 422;
    expect(await report(original), isFalse);
    status = 200;
    expect(await report(original), isFalse);
    expect(reports, hasLength(1));
  });

  test(
      'reset prevents reporting both unreported and previously reported events',
      () async {
    final unreported = event();
    final reported = event(nonce: 'c');
    expect(await report(reported), isTrue);
    Restage.reset();
    expect(await report(unreported), isFalse);
    expect(await report(reported), isFalse);
    expect(reports, hasLength(1));
  });

  test('identical event values have independent reports', () async {
    final first = event();
    final second = event();
    expect(await Future.wait([report(first), report(second)]), [true, true]);
    expect(reports, hasLength(2));
    expect(reports.first['eventId'], isNot(reports.last['eventId']));
  });

  test('reset or reconfigure while flushing prevents the report', () async {
    for (final reset in <void Function()>[
      Restage.reset,
      () => Restage.configure(measurementEnabled: true),
    ]) {
      final delivered = Completer<void>();
      final original = event(flush: () => delivered.future);
      final pending = report(original);
      reset();
      delivered.complete();
      expect(await pending, isFalse);
    }
    expect(reports, isEmpty);
  });

  test('malformed, refused and failed responses are unavailable', () async {
    for (final response in [
      (500, '{}'),
      (200, '{}'),
      (200, 'invalid'),
      (200, '{"accepted":false}')
    ]) {
      (status, responseBody) = response;
      expect(await report(event()), isFalse);
    }
    final original = event(flush: () async => throw StateError('offline'));
    expect(await report(original), isFalse);
    expect(reports, hasLength(4));
  });

  test('invalid identifiers do not send a report', () async {
    for (final value in ['', 'x' * 257, '\u0000', 'é' * 129]) {
      final original = event();
      expect(
          await Restage.measurement.reportPurchase(original,
              packageIdentifier: value, productIdentifier: 'annual'),
          isFalse);
      expect(
          await Restage.measurement.reportPurchase(original,
              packageIdentifier: 'annual', productIdentifier: value),
          isFalse);
    }
    expect(reports, isEmpty);
  });

  testWidgets('a raw rendered paywall retains its session after unmount',
      (tester) async {
    final bytes = encodeLibraryBlob(parseLibraryFile('''
import restage.core;
import restage.material;
widget Paywall = TextButton(
  onPressed: event "revenuecat.purchase" {packageIdentifier: "holiday_annual"},
  child: Text(text: "Buy annual"),
);
'''));
    fixture = AdmittedBundledPublicationFixture.build(artifact: bytes);
    final harness = AdmittedConstructionOwnerHostTestHarness.install(
      publicationContext: fixture.publicationContextRef,
      hostedBindingReadPortLookup: () => _BindingReadPort(fixture),
    );
    addTearDown(harness.close);
    final resolved = ResolvedVariant(
        bytes: bytes, paywallId: 'upgrade', surfaceVersion: 'selected');
    attachMeasurementPublicationBindingReference(
        resolved, fixture.binding.reference);
    RestageEvent? purchaseEvent;
    final streamed =
        Restage.events.where((event) => event is PaywallCustomEvent).first;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RestagePaywall(
          id: 'upgrade',
          resolver: _Resolver(resolved),
          onEvent: (event) {
            if (event is PaywallCustomEvent) {
              purchaseEvent = event;
            }
          },
        ),
      ),
    ));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }
    await tester.tap(find.text('Buy annual'));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(purchaseEvent, isNotNull);
    final reporting = report(purchaseEvent!);
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }
    expect(harness.worker.registrations, hasLength(1));
    expect(await reporting, isTrue);
    final streamEvent = await streamed;
    expect(streamEvent, same(purchaseEvent));
    expect(await report(streamEvent), isTrue);
    expect(reports, hasLength(1));
    expect(reports.single['exposure']['captureSessionNonce'],
        harness.worker.registrations.single.captureSessionNonce);
    expect(harness.worker.checkpointCalls, 1);
  });
}

final class _Resolver extends VariantResolver {
  _Resolver(this.resolved);
  final ResolvedVariant resolved;

  @override
  Future<ResolvedVariant> resolve(String id,
          {String? placementId, Locale? locale}) async =>
      resolved;
}

final class _BindingReadPort implements MeasurementPublicationBindingReadPort {
  _BindingReadPort(this.fixture);
  final AdmittedBundledPublicationFixture fixture;

  @override
  Future<MeasurementPublicationBindingReadResult> readExact(
          MeasurementPublicationBindingReferenceV1 reference) async =>
      MeasurementPublicationBindingReadAccepted(
          reference: fixture.binding.reference,
          binding: fixture.binding,
          registeredPublicationAttestation:
              fixture.entry.registeredPublicationAttestation);
}
