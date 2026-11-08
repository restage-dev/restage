import 'dart:convert';

import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:test/test.dart';

void main() {
  final request = MeasurementInstallErasureRequestV1(
    operationId: 'erase.install.1',
    assignmentKey: 'ic1.${'a' * 64}',
  );
  final receipt = MeasurementInstallErasureReceiptV1(
    operationId: request.operationId,
    target: TargetCoordinate(
      organizationId: OrganizationId(1),
      appId: ApplicationId(2),
      environmentTargetId: EnvironmentTargetId(3),
      namedEnvironmentId: NamedEnvironmentId(4),
      runtimePlane: RuntimePlane.live,
    ),
    completedAtServerTimeMicros: 100,
  );

  test('install erasure concrete wire roundtrip', () {
    expect(
      utf8.decode(request.canonicalBytes),
      '{"assignmentKey":"ic1.${'a' * 64}",'
      '"kind":"measurementInstallErasureRequest",'
      '"operationId":"erase.install.1","schemaVersion":1}',
    );
    final decoded = MeasurementInstallErasureRequestV1.fromCanonicalBytes(
      request.canonicalBytes,
    );
    expect(decoded.operationId, 'erase.install.1');
    expect(decoded.assignmentKey, 'ic1.${'a' * 64}');
    expect(
      MeasurementInstallErasureRequestV1.fromJson(request.toJson()),
      request,
    );
    final completed = MeasurementInstallErasureReceiptV1.fromCanonicalBytes(
      receipt.canonicalBytes,
    );
    expect(completed.toJson(), {
      'kind': 'measurementInstallErasureReceipt',
      'schemaVersion': 1,
      'operationId': 'erase.install.1',
      'target': receipt.target.toJson(),
      'scope': 'currentInstall',
      'categories': ['assignmentLinks', 'assignments', 'pseudonyms'],
      'completedAtServerTimeMicros': 100,
    });
  });

  test(
      'install erasure refuses malformed authorities '
      'and closed-field violations', () {
    for (final key in [
      '',
      'ic1.${'A' * 64}',
      'ic1.${'a' * 63}',
      'ic1.${'a' * 65}',
      'secret',
      'ic1.${'a' * 64}\n',
    ]) {
      expect(
        () => MeasurementInstallErasureRequestV1.fromJson(
          {...request.toJson(), 'assignmentKey': key},
        ),
        throwsA(isA<CanonicalFormatException>()),
      );
    }
    for (final operationId in ['', 'a' * 129, 'contains space']) {
      expect(
        () => MeasurementInstallErasureRequestV1(
          operationId: operationId,
          assignmentKey: request.assignmentKey,
        ),
        throwsA(isA<CanonicalFormatException>()),
      );
    }
    for (final patch in [
      {'extra': request.assignmentKey},
      {'schemaVersion': 2},
      {'kind': 'other'},
    ]) {
      expect(
        () => MeasurementInstallErasureRequestV1.fromJson(
          {...request.toJson(), ...patch},
        ),
        throwsA(isA<CanonicalFormatException>()),
      );
    }
    for (final patch in [
      {'extra': true},
      {'scope': 'all'},
      {
        'categories': ['assignments', 'assignmentLinks', 'pseudonyms'],
      },
      {
        'categories': [
          'assignmentLinks',
          'assignments',
          'pseudonyms',
          'pseudonyms',
        ],
      },
      {'completedAtServerTimeMicros': 0},
      {'completedAtServerTimeMicros': kMaximumPortableJsonInteger + 1},
    ]) {
      expect(
        () => MeasurementInstallErasureReceiptV1.fromJson(
          {...receipt.toJson(), ...patch},
        ),
        throwsA(isA<CanonicalFormatException>()),
      );
    }
  });

  test(
      'install erasure refuses duplicate and noncanonical bytes '
      'without authority disclosure', () {
    for (final source in [
      ' ${utf8.decode(request.canonicalBytes)}',
      utf8.decode(request.canonicalBytes).replaceFirst(
            '"schemaVersion":1',
            '"schemaVersion":1,"schemaVersion":1',
          ),
      '{"assignmentKey":"${request.assignmentKey}",',
    ]) {
      try {
        MeasurementInstallErasureRequestV1.fromCanonicalBytes(
          utf8.encode(source),
        );
        fail('accepted invalid bytes');
      } on CanonicalFormatException catch (error) {
        expect(error.toString(), isNot(contains(request.assignmentKey)));
      }
    }
    expect(
      () => MeasurementInstallErasureReceiptV1.fromCanonicalBytes(
        utf8.encode('${utf8.decode(receipt.canonicalBytes)}\n'),
      ),
      throwsA(isA<CanonicalFormatException>()),
    );
  });
}
