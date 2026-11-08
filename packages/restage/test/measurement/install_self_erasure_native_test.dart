import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/runtime/native_facts.dart';
import 'package:restage/src/resolver/surface_assignment_key_provider.dart';
import 'package:restage/src/resolver/surface_assignment_persistence.dart';
import 'package:restage/src/resolver/surface_metering_key_provider.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Exercise the production channel path; its test bypass checks the binding name.
class _ChannelBinding extends AutomatedTestWidgetsFlutterBinding {}

void main() {
  final binding = _ChannelBinding();
  const channel = MethodChannel('restage/early_request');
  late SharedPreferences prefs;
  late _Transport transport;

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await Restage.debugResetAndWait();
    NativeFacts.reset();
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    transport = _Transport();
    http.runWithClient(
      () => Restage.configure(
        apiKey: 'rs_pk_erasure',
        baseUrl: 'https://sdk.example.com',
        governedMeasurementTransport: transport,
      ),
      () => MockClient((_) async => http.Response('', 503)),
    );
  });

  tearDown(() async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await SurfaceAssignmentPersistence.ready.catchError((Object _) {});
    SurfaceAssignmentPersistence.debugRestart();
    await Restage.debugResetAndWait();
    NativeFacts.reset();
    debugDefaultTargetPlatformOverride = null;
  });

  Future<void> confirm() async {
    final lease = await SurfaceAssignmentKeyProvider.captureLease();
    final now = DateTime.now().microsecondsSinceEpoch;
    expect(
        await lease.confirmRegistration!(lease.registration!, now,
            'ic1.${'a' * 64}', now + Duration.microsecondsPerDay, now),
        isTrue);
  }

  List<String> pendingRecords() => prefs
      .getKeys()
      .where((key) => key.startsWith('restage.installErasure.'))
      .map((key) => prefs.getString(key)!)
      .toList();

  final oldNativeTuple = <String, Object?>{
    'registrationNonce':
        base64UrlEncode(List<int>.filled(32, 1)).replaceAll('=', ''),
    'registrationCreatedAtMicros': 100,
  };
  final newNativeTuple = <String, Object?>{
    'registrationNonce':
        base64UrlEncode(List<int>.filled(32, 2)).replaceAll('=', ''),
    'registrationCreatedAtMicros': 200,
  };

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final stage in ['read', 'reset']) {
      test(
          'native channel $stage refusal keeps SDK erasure retryable${platform == TargetPlatform.android ? ' on Android' : ''}',
          () async {
        debugDefaultTargetPlatformOverride = platform;
        var refusing = false;
        var rotated = false;
        final calls = <String>[];
        binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
            (call) async {
          calls.add(call.method);
          if (call.method == 'facts' || call.method == 'registration') {
            if (refusing && stage == 'read') {
              throw PlatformException(code: 'registration_unavailable');
            }
            return rotated ? newNativeTuple : oldNativeTuple;
          }
          if (call.method == 'resetRegistration') {
            if (refusing && stage == 'reset') {
              throw PlatformException(code: 'registration_unavailable');
            }
            rotated = true;
            return newNativeTuple;
          }
          // Startup invalidation and identity writes acknowledge independently.
          return null;
        });
        await confirm();
        final metering = await SurfaceMeteringKeyProvider.currentKey();
        expect(metering, isNotNull);
        NativeFacts.reset();
        calls.clear();
        refusing = true;
        expect((await Restage.privacy.request()).status,
            RestagePrivacyCoordinatorStatus.failed);
        expect(rotated, isFalse);
        final pending = jsonDecode(pendingRecords().single) as Map;
        expect(pending['finalized'], isNot(true));
        expect(calls, contains('invalidateStartup'));
        expect(calls, isNot(contains('setIdentity')));
        expect(calls.contains('resetRegistration'), stage == 'reset');
        expect((await SurfaceAssignmentKeyProvider.captureLease()).registration,
            isNull);
        final original = transport.requests.single.canonicalBytes;
        final actor = prefs.getString('restage.analytics.anonymous_id');
        refusing = false;
        expect((await Restage.privacy.request()).status,
            RestagePrivacyCoordinatorStatus.completed);
        expect(rotated, isTrue);
        expect(calls, contains('setIdentity'));
        expect(transport.requests.last.canonicalBytes, original);
        expect(prefs.getString('restage.analytics.anonymous_id'), actor);
        expect(pendingRecords(), isEmpty);
        expect(await SurfaceMeteringKeyProvider.currentKey(), metering);
        expect((await NativeFacts.registration())!.nonce,
            newNativeTuple['registrationNonce']);
      });
    }
  }
}

MeasurementInstallErasureRequestV1 _operation(
  RestagePrivacyRequestV1 request,
) =>
    MeasurementInstallErasureRequestV1.fromCanonicalBytes(
      request.authorities.single.requestCanonicalBytes,
    );

RestagePrivacyReceiptV1 _completed(
  RestagePrivacyRequestV1 request, {
  String? operationId,
}) {
  final operation = _operation(request);
  final receipt = MeasurementInstallErasureReceiptV1(
    operationId: operationId ?? operation.operationId,
    target: TargetCoordinate(
      organizationId: OrganizationId(1),
      appId: ApplicationId(2),
      environmentTargetId: EnvironmentTargetId(3),
      namedEnvironmentId: NamedEnvironmentId(4),
      runtimePlane: RuntimePlane.live,
    ),
    completedAtServerTimeMicros: 100,
  );
  return RestagePrivacyReceiptV1(
    targets: request.targets,
    action: request.action,
    correlationId: request.correlationId,
    status: RestagePrivacyCoordinatorStatus.completed,
    domainResults: [
      RestagePrivacyDomainResult.withReceipt(
        RestagePrivacyDomainReceipt(
          domain: RestagePrivacyDomain.measurement,
          action: RestagePrivacyAction.delete,
          status: RestagePrivacyDomainStatus.completed,
          operationId: operation.operationId,
          receiptCanonicalBytes: receipt.canonicalBytes,
        ),
      ),
    ],
  );
}

final class _Transport implements RestageGovernedMeasurementTransport {
  final requests = <RestagePrivacyRequestV1>[];
  Future<RestagePrivacyReceiptV1> Function(RestagePrivacyRequestV1) onRequest =
      (request) async => _completed(request);

  @override
  Future<RestagePrivacyReceiptV1> requestPrivacy(
    RestagePrivacyRequestV1 request,
  ) {
    requests.add(request);
    return onRequest(request);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected governed operation');
}
