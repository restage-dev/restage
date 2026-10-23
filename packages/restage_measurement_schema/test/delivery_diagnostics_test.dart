import 'dart:typed_data';

import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:test/test.dart';

final _target = TargetCoordinate(
  organizationId: OrganizationId(1),
  appId: ApplicationId(2),
  environmentTargetId: EnvironmentTargetId(3),
  namedEnvironmentId: NamedEnvironmentId(4),
  runtimePlane: RuntimePlane.sandbox,
);

const _floor = 5;

MeasurementDeliveryDiagnosticsV1 _read({
  TargetCoordinate? target,
  int? contractVersion = 3,
  int disclosureFloor = _floor,
  int frozen = 5,
}) =>
    MeasurementDeliveryDiagnosticsV1(
      target: target ?? _target,
      surfaceType: MeasurementDeliveryDiagnosticsSurfaceTypeV1.paywall,
      surfaceSlug: 'upgrade',
      contractVersion: contractVersion,
      windowStartDayUtc: measurementDeliveryDiagnosticsDayMicros,
      windowEndDayExclusiveUtc: measurementDeliveryDiagnosticsDayMicros * 2,
      disclosureFloor: disclosureFloor,
      servedDefaults: MeasurementDeliveryDiagnosticsSectionV1(
        population: MeasurementDeliveryDiagnosticsPopulationV1
            .servedDefaultPresentations,
        coverage: MeasurementDeliveryDiagnosticsCoverageV1
            .observedAdmittedPresentations,
        availability:
            MeasurementDeliveryDiagnosticsAvailabilityV1.partiallyHeld,
        reasons: [
          MeasurementDeliveryDiagnosticsReasonCountV1(
            reason: 'frozen',
            observedCount: frozen,
          ),
          MeasurementDeliveryDiagnosticsReasonCountV1(reason: 'futureDefault'),
        ],
      ),
      recordedRefusals: MeasurementDeliveryDiagnosticsSectionV1(
        population:
            MeasurementDeliveryDiagnosticsPopulationV1.recordedServerRefusals,
        coverage: MeasurementDeliveryDiagnosticsCoverageV1
            .observedRecordedServerRefusals,
        availability: MeasurementDeliveryDiagnosticsAvailabilityV1.held,
        reasons: [
          MeasurementDeliveryDiagnosticsReasonCountV1(
            reason: 'audienceUndecided',
          ),
        ],
      ),
    );

void main() {
  test('a read states the floor it carries and holds counts under it', () {
    final exact = _read(disclosureFloor: 1, frozen: 1);
    expect(
      MeasurementDeliveryDiagnosticsV1.fromCanonicalBytes(exact.canonicalBytes)
          .servedDefaults
          .reasons
          .first
          .observedCount,
      1,
    );
    expect(_read().disclosureFloor, _floor);
    expect(() => _read(disclosureFloor: 0), throwsArgumentError);
    expect(() => _read(frozen: _floor - 1), throwsArgumentError);
  });

  group('MeasurementDeliveryDiagnosticsV1', () {
    test('round-trips distinct populations and preserves unknown reasons', () {
      final read = _read();
      final decoded = MeasurementDeliveryDiagnosticsV1.fromCanonicalBytes(
        read.canonicalBytes,
      );

      expect(decoded.canonicalBytes, orderedEquals(read.canonicalBytes));
      expect(
        decoded.servedDefaults.population,
        MeasurementDeliveryDiagnosticsPopulationV1.servedDefaultPresentations,
      );
      expect(
        decoded.recordedRefusals.population,
        MeasurementDeliveryDiagnosticsPopulationV1.recordedServerRefusals,
      );
      expect(decoded.servedDefaults.reasons[0].reason, 'frozen');
      expect(decoded.servedDefaults.reasons[1].reason, 'futureDefault');
      expect(decoded.servedDefaults.reasons[1].observedCount, isNull);
      expect(decoded.recordedRefusals.reasons.single.observedCount, isNull);
    });

    test('round-trips a general scope with no contract-version field', () {
      final read = _read(contractVersion: null);
      expect(read.toJson(), isNot(contains('contractVersion')));

      final decoded = MeasurementDeliveryDiagnosticsV1.fromCanonicalBytes(
        read.canonicalBytes,
      );

      expect(decoded.contractVersion, isNull);
      expect(decoded.canonicalBytes, orderedEquals(read.canonicalBytes));
    });

    test('rejects a present null or invalid contract version', () {
      final json = _read().toJson();

      expect(
        () => MeasurementDeliveryDiagnosticsV1.fromJson({
          ...json,
          'contractVersion': null,
        }),
        throwsA(isA<CanonicalFormatException>()),
      );
      expect(
        () => MeasurementDeliveryDiagnosticsV1.fromJson({
          ...json,
          'contractVersion': 0,
        }),
        throwsArgumentError,
      );
    });

    test(
        'rejects a low stated count, incorrect coverage, and an unretained window',
        () {
      expect(
        () => _read(frozen: _floor - 1),
        throwsArgumentError,
      );
      expect(
        () => MeasurementDeliveryDiagnosticsReasonCountV1(
          reason: 'frozen',
          observedCount: 0,
        ),
        throwsArgumentError,
      );
      expect(
        () => MeasurementDeliveryDiagnosticsSectionV1(
          population: MeasurementDeliveryDiagnosticsPopulationV1
              .servedDefaultPresentations,
          coverage: MeasurementDeliveryDiagnosticsCoverageV1
              .observedRecordedServerRefusals,
          availability:
              MeasurementDeliveryDiagnosticsAvailabilityV1.unavailable,
          reasons: const [],
        ),
        throwsArgumentError,
      );
      expect(
        () => MeasurementDeliveryDiagnosticsV1(
          target: _target,
          surfaceType: MeasurementDeliveryDiagnosticsSurfaceTypeV1.paywall,
          surfaceSlug: 'upgrade',
          contractVersion: null,
          windowStartDayUtc: measurementDeliveryDiagnosticsDayMicros,
          windowEndDayExclusiveUtc: measurementDeliveryDiagnosticsDayMicros +
              measurementDeliveryDiagnosticsRetentionWindowMicros +
              measurementDeliveryDiagnosticsDayMicros,
          disclosureFloor: _floor,
          servedDefaults: MeasurementDeliveryDiagnosticsSectionV1(
            population: MeasurementDeliveryDiagnosticsPopulationV1
                .servedDefaultPresentations,
            coverage: MeasurementDeliveryDiagnosticsCoverageV1
                .observedAdmittedPresentations,
            availability:
                MeasurementDeliveryDiagnosticsAvailabilityV1.unavailable,
            reasons: const [],
          ),
          recordedRefusals: MeasurementDeliveryDiagnosticsSectionV1(
            population: MeasurementDeliveryDiagnosticsPopulationV1
                .recordedServerRefusals,
            coverage: MeasurementDeliveryDiagnosticsCoverageV1
                .observedRecordedServerRefusals,
            availability:
                MeasurementDeliveryDiagnosticsAvailabilityV1.unavailable,
            reasons: const [],
          ),
        ),
        throwsArgumentError,
      );
    });

    test('rejects a protocol that changes the two fixed sections', () {
      final json = _read().toJson();
      final served = Map<String, Object?>.from(
        json['servedDefaults']! as Map<String, Object?>,
      )..['population'] = 'recordedServerRefusals';
      expect(
        () => MeasurementDeliveryDiagnosticsV1.fromJson({
          ...json,
          'servedDefaults': served,
        }),
        throwsA(anything),
      );
    });

    test('rejects an oversized canonical response before decoding it', () {
      final bytes = Uint8List(
        measurementDeliveryDiagnosticsMaximumCanonicalBytes + 1,
      );
      expect(
        () => MeasurementDeliveryDiagnosticsV1.fromCanonicalBytes(bytes),
        throwsA(
          isA<CanonicalFormatException>().having(
            (error) => error.toString(),
            'message',
            contains(
              '$measurementDeliveryDiagnosticsMaximumCanonicalBytes canonical bytes',
            ),
          ),
        ),
      );
    });
  });
}
