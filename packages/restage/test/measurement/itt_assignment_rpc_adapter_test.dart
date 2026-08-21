import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage/src/measurement/measurement_assignment_diagnostics.dart';
import 'package:restage/src/measurement/itt_assignment_rpc_adapter.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';

void main() {
  group('IttAssignmentRpcAdapter', () {
    test('posts the exact target-free authenticated ITT carrier', () async {
      late http.Request seen;
      final adapter = IttAssignmentRpcAdapter(
        RestageRpcClient(
          baseUrl: 'https://example.com',
          apiKey: 'rs_pk_test',
          httpClient: MockClient((request) async {
            seen = request;
            return http.Response(
              '{"result":"assigned","candidateDelivery":"rendered"}',
              200,
            );
          }),
        ),
      );

      final outcome = await adapter.deliver(_request());
      final diagnostic = adapter.diagnosticFor(outcome);

      expect(seen.method, 'POST');
      expect(seen.url.path, '/sdk/v1/measurement-assignment');
      expect(seen.url.query, isEmpty);
      expect(seen.headers['Authorization'], 'Bearer rs_pk_test');
      expect(seen.headers['Content-Type'], contains('application/json'));
      expect(seen.body, _request().canonicalJson);
      expect(
        diagnostic,
        isA<MeasurementAssignmentDeliveryAssigned>().having(
          (value) => value.candidateDelivery,
          'candidate delivery',
          MeasurementAssignmentCandidateDeliveryDiagnostic.rendered,
        ),
      );
    });

    test('maps exact ITT no-admission and unavailable diagnostics closedly',
        () async {
      final cases = <String, Type>{
        '{"result":"outsideAudience"}':
            MeasurementAssignmentDeliveryOutsideAudience,
        '{"result":"ineligible"}': MeasurementAssignmentDeliveryIneligible,
        '{"result":"authorityUnavailable"}':
            MeasurementAssignmentDeliveryUnavailable,
        '{"result":"populationUnavailable"}':
            MeasurementAssignmentDeliveryInferenceUnavailable,
      };

      for (final entry in cases.entries) {
        final adapter = IttAssignmentRpcAdapter(
          RestageRpcClient(
            baseUrl: 'https://example.com',
            apiKey: 'rs_pk_test',
            httpClient: MockClient((_) async => http.Response(entry.key, 200)),
          ),
        );

        final diagnostic =
            adapter.diagnosticFor(await adapter.deliver(_request()));

        expect(diagnostic.runtimeType, entry.value, reason: entry.key);
      }
    });

    test('rejects malformed success bodies and preserves auth/fault outcomes',
        () async {
      final malformed = IttAssignmentRpcAdapter(
        RestageRpcClient(
          baseUrl: 'https://example.com',
          apiKey: 'rs_pk_test',
          httpClient: MockClient(
            (_) async => http.Response(
              '{"result":"assigned","candidateDelivery":"forged"}',
              200,
            ),
          ),
        ),
      );
      final unauthorized = IttAssignmentRpcAdapter(
        RestageRpcClient(
          baseUrl: 'https://example.com',
          apiKey: 'rs_pk_test',
          httpClient: MockClient((_) async => http.Response('', 401)),
        ),
      );
      final unavailable = IttAssignmentRpcAdapter(
        RestageRpcClient(
          baseUrl: 'https://example.com',
          apiKey: 'rs_pk_test',
          httpClient: MockClient((_) async => http.Response('', 503)),
        ),
      );

      final malformedDiagnostic = malformed.diagnosticFor(
        await malformed.deliver(_request()),
      );
      final unauthorizedDiagnostic = unauthorized.diagnosticFor(
        await unauthorized.deliver(_request()),
      );
      final unavailableDiagnostic = unavailable.diagnosticFor(
        await unavailable.deliver(_request()),
      );

      expect(
        malformedDiagnostic,
        isA<MeasurementAssignmentDeliveryUnavailable>().having(
          (value) => value.reason,
          'reason',
          MeasurementAssignmentUnavailableReason.malformedResponse,
        ),
      );
      expect(
        unauthorizedDiagnostic,
        isA<MeasurementAssignmentDeliveryUnavailable>().having(
          (value) => value.reason,
          'reason',
          MeasurementAssignmentUnavailableReason.unauthenticated,
        ),
      );
      expect(
        unavailableDiagnostic,
        isA<MeasurementAssignmentDeliveryUnavailable>().having(
          (value) => value.reason,
          'reason',
          MeasurementAssignmentUnavailableReason.serviceUnavailable,
        ),
      );
    });

    test('does not permit raw credential or target transport fields', () {
      final source = _restageFile(
        'lib/src/measurement/itt_assignment_rpc_adapter.dart',
      ).readAsStringSync();
      final rpcSource = _restageFile(
        'lib/src/restage_rpc_client/restage_rpc_client.dart',
      ).readAsStringSync();
      final joined = '$source\n$rpcSource';

      for (final forbidden in const [
        'rawCredential',
        'credentialBytes',
        'targetCanonical',
        'tenantCanonical',
        'assignmentArm',
        'allocationPseudonym',
      ]) {
        expect(joined, isNot(contains(forbidden)), reason: forbidden);
      }
    });
  });
}

IttAssignmentRpcRequest _request() => const IttAssignmentRpcRequest(
      acceptedReceiptCanonicalBase64: 'AQ',
      credentialHandle: 'handle.itt.0001',
      sdkBuiltInsCanonicalBase64: 'Ag',
      assignmentContextCanonicalBase64: 'Aw',
    );

File _restageFile(String relativePath) {
  for (final prefix in ['', 'packages/restage/']) {
    final candidate = File('$prefix$relativePath');
    if (candidate.existsSync()) return candidate;
  }
  throw StateError('Could not locate packages/restage/$relativePath');
}
