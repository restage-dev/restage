import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage/src/resolver/surface_canonical_carrier_provider.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';

import '../support/hosted_artifact_delivery.dart';

/// Canonical base64url of a short document, minted the way the wire mints it.
String _carrier(String text) =>
    base64UrlEncode(utf8.encode(text)).replaceAll('=', '');

void main() {
  final delivery = HostedArtifactFixture();

  Map<String, Object?> body({Object? assignment}) => <String, Object?>{
        ...delivery.describeRaw(
          surfaceType: Surface.paywall,
          surfaceSlug: 'pro_upgrade',
          version: 1,
          publishedAt: DateTime.utc(2026),
          content: const [1, 2, 3],
        ),
        if (assignment != null) 'assignment': assignment,
      };

  RestageRpcClient clientFor(MockClient mock) => RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        httpClient: mock,
      );

  tearDown(SurfaceCanonicalCarrierProvider.clear);

  group('the carriers a hosted surface request sends', () {
    test('sends both when this build holds both', () async {
      final observations = _carrier('{"platform":"ios"}');
      final held = _carrier('{"armId":"arm-1"}');
      SurfaceCanonicalCarrierProvider.installBuiltIns(() => observations);
      SurfaceCanonicalCarrierProvider.installHeldAssignment(() => held);
      final sent = <Map<String, dynamic>>[];

      for (final surfaceType in const ['paywall', 'general']) {
        await clientFor(
          delivery.client((request) async {
            sent.add((jsonDecode(request.body) as Map).cast());
            return http.Response(jsonEncode(body()), 200);
          }),
        ).fetchSurface(surfaceType: surfaceType, surfaceSlug: 'pro_upgrade');
      }

      expect(sent, hasLength(2));
      for (final request in sent) {
        expect(request['sdkBuiltInsCanonicalBase64'], observations);
        expect(request['assignmentCanonicalBase64'], held);
      }
    });

    test('omits the assignment this build does not hold', () async {
      SurfaceCanonicalCarrierProvider.installBuiltIns(
        () => _carrier('{"platform":"ios"}'),
      );
      late Map<String, dynamic> sent;

      await clientFor(
        delivery.client((request) async {
          sent = (jsonDecode(request.body) as Map).cast();
          return http.Response(jsonEncode(body()), 200);
        }),
      ).fetchSurface(surfaceType: 'paywall', surfaceSlug: 'pro_upgrade');

      expect(sent.containsKey('sdkBuiltInsCanonicalBase64'), isTrue);
      expect(sent.containsKey('assignmentCanonicalBase64'), isFalse);
    });

    test(
        'sends neither carrier, and no retired negotiation member, when '
        'nothing supplies one', () async {
      late Map<String, dynamic> sent;

      await clientFor(
        delivery.client((request) async {
          sent = (jsonDecode(request.body) as Map).cast();
          return http.Response(jsonEncode(body()), 200);
        }),
      ).fetchSurface(surfaceType: 'paywall', surfaceSlug: 'pro_upgrade');

      expect(sent, {'surfaceType': 'paywall', 'surfaceSlug': 'pro_upgrade'});
    });

    test('never sends a carrier that is not canonical base64url', () async {
      SurfaceCanonicalCarrierProvider.installBuiltIns(() => 'not base64!');
      SurfaceCanonicalCarrierProvider.installHeldAssignment(() => 'AAAA=');
      late Map<String, dynamic> sent;

      await clientFor(
        delivery.client((request) async {
          sent = (jsonDecode(request.body) as Map).cast();
          return http.Response(jsonEncode(body()), 200);
        }),
      ).fetchSurface(surfaceType: 'paywall', surfaceSlug: 'pro_upgrade');

      expect(sent.containsKey('sdkBuiltInsCanonicalBase64'), isFalse);
      expect(sent.containsKey('assignmentCanonicalBase64'), isFalse);
    });

    test('a provider that throws leaves the request carrying nothing',
        () async {
      SurfaceCanonicalCarrierProvider.installBuiltIns(
        () => throw StateError('no observations'),
      );
      late Map<String, dynamic> sent;

      await clientFor(
        delivery.client((request) async {
          sent = (jsonDecode(request.body) as Map).cast();
          return http.Response(jsonEncode(body()), 200);
        }),
      ).fetchSurface(surfaceType: 'paywall', surfaceSlug: 'pro_upgrade');

      expect(sent.containsKey('sdkBuiltInsCanonicalBase64'), isFalse);
    });
  });

  group('the retired negotiation is gone from the wire', () {
    test('a re-fetch under revalidation uploads nothing', () async {
      final sent = <Map<String, dynamic>>[];
      final client = clientFor(
        delivery.client((request) async {
          sent.add((jsonDecode(request.body) as Map).cast());
          return http.Response(jsonEncode(body()), 200);
        }),
      );

      for (var attempt = 0; attempt < 2; attempt++) {
        await client.fetchSurface(
          surfaceType: 'onboarding',
          surfaceSlug: 'first_run',
          publicationGuard: () => true,
        );
      }

      expect(sent, hasLength(2));
      for (final request in sent) {
        expect(request, {
          'surfaceType': 'onboarding',
          'surfaceSlug': 'first_run',
        });
      }
    });

    test('a delivery that still claims the retired signals changes nothing',
        () async {
      final claiming = await clientFor(
        delivery.serving({
          ...body(),
          'contractRequired': true,
          'flowContractRequired': true,
        }),
      ).fetchSurface(surfaceType: 'paywall', surfaceSlug: 'pro_upgrade');
      final plain = await clientFor(
        delivery.serving(body()),
      ).fetchSurface(surfaceType: 'paywall', surfaceSlug: 'pro_upgrade');

      // Identical outcomes: nothing reads those keys now, so a service that
      // still sent them could not hold the artifact back.
      expect(claiming, isNotNull);
      expect(
        claiming!.artifact.runtimeType,
        plain!.artifact.runtimeType,
      );
    });
  });

  group('what the delivery says about its assignment', () {
    test('reads the committed assignment from the slot the service writes',
        () async {
      final assignment = CanonicalSurfaceExperimentAssignmentV1(
        experimentId: ExperimentPublicIdV1('experiment.checkout'),
        experimentRevisionId: ExperimentPublicRevisionIdV1('revision.1'),
        experimentEpochId: ExperimentPublicEpochIdV1('epoch.1'),
        armId: ExperimentPublicArmIdV1('arm-1'),
        outcomeLinkCarrier: _carrier('carrier'),
      );

      final result = await clientFor(
        delivery.serving(body(assignment: assignment.toJson())),
      ).fetchSurface(surfaceType: 'paywall', surfaceSlug: 'pro_upgrade');

      expect(result!.canonicalExperimentAssignment, assignment);
      expect(result.assignmentDiagnostic, isNull);
    });

    test('reads the diagnostic beside content it still serves', () async {
      final result = await clientFor(
        delivery.serving(
          body(assignment: const {'result': 'assignmentNotPresented'}),
        ),
      ).fetchSurface(surfaceType: 'paywall', surfaceSlug: 'pro_upgrade');

      expect(
        result!.assignmentDiagnostic,
        SurfaceAssignmentDiagnostic.assignmentNotPresented,
      );
      expect(result.canonicalExperimentAssignment, isNull);
    });

    test('a refused delivery is unavailable, whatever it refused for',
        () async {
      for (final cause in const [
        'authorityUnavailable',
        'populationUnavailable',
        'assignmentDisagrees',
        'notDelivered',
      ]) {
        final result = await clientFor(
          MockClient(
            (_) async => http.Response(
              jsonEncode({
                'error': 'unavailable',
                'assignment': {'result': cause},
              }),
              404,
            ),
          ),
        ).fetchSurface(surfaceType: 'paywall', surfaceSlug: 'pro_upgrade');

        expect(result, isNull, reason: cause);
      }
    });
  });

  group('the closed cause vocabulary', () {
    test('reads every cause the service names', () {
      const causes = {
        'authorityUnavailable':
            SurfaceAssignmentDiagnostic.authorityUnavailable,
        'populationUnavailable':
            SurfaceAssignmentDiagnostic.populationUnavailable,
        'assignmentDisagrees': SurfaceAssignmentDiagnostic.assignmentDisagrees,
        'notDelivered': SurfaceAssignmentDiagnostic.notDelivered,
        'assignmentNotPresented':
            SurfaceAssignmentDiagnostic.assignmentNotPresented,
      };
      for (final entry in causes.entries) {
        expect(
          surfaceAssignmentDiagnosticFrom({'result': entry.key}),
          entry.value,
          reason: entry.key,
        );
      }
      expect(causes.length, SurfaceAssignmentDiagnostic.values.length);
    });

    test('reads nothing from a cause this build does not know', () {
      expect(surfaceAssignmentDiagnosticFrom({'result': 'invented'}), isNull);
      expect(surfaceAssignmentDiagnosticFrom({'result': 7}), isNull);
      expect(surfaceAssignmentDiagnosticFrom('assignmentDisagrees'), isNull);
      expect(surfaceAssignmentDiagnosticFrom(null), isNull);
    });
  });
}
