import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/measurement/measurement_assignment_diagnostics.dart';
import 'package:restage/src/measurement/measurement_assignment_transport.dart';

void main() {
  group('MeasurementAssignmentTransport', () {
    test('retains one exact typed request across retries', () async {
      final request = _request();
      final adapter = _RecordingAdapter(
        () => const _IttResult.committed(
          MeasurementAssignmentCandidateDeliveryDiagnostic.rendered,
        ),
      );
      final transport =
          MeasurementAssignmentTransport<_IttRequest, _IttResult>.adapter(
        adapter,
      );

      final first = await transport.deliver(request);
      final retry = await transport.deliver(request);

      expect(first, isA<MeasurementAssignmentDeliveryAssigned>());
      expect(retry, isA<MeasurementAssignmentDeliveryAssigned>());
      expect(adapter.requests, orderedEquals([request, request]));
      expect(
        (first as MeasurementAssignmentDeliveryAssigned).candidateDelivery,
        MeasurementAssignmentCandidateDeliveryDiagnostic.rendered,
      );
    });

    test('keeps outside-audience and ineligible distinct', () async {
      final request = _request();

      final outside =
          await MeasurementAssignmentTransport<_IttRequest, _IttResult>.adapter(
        _RecordingAdapter(
          () => const _IttResult.outsideAudience(),
        ),
      ).deliver(request);
      final ineligible =
          await MeasurementAssignmentTransport<_IttRequest, _IttResult>.adapter(
        _RecordingAdapter(() => const _IttResult.ineligible()),
      ).deliver(request);

      expect(outside, isA<MeasurementAssignmentDeliveryOutsideAudience>());
      expect(ineligible, isA<MeasurementAssignmentDeliveryIneligible>());
      expect(outside, isNot(isA<MeasurementAssignmentDeliveryIneligible>()));
      expect(
        ineligible,
        isNot(isA<MeasurementAssignmentDeliveryOutsideAudience>()),
      );
    });

    test('preserves unresolved-population inference unavailability', () async {
      final outcome =
          await MeasurementAssignmentTransport<_IttRequest, _IttResult>.adapter(
        _RecordingAdapter(
          () => const _IttResult.inferenceUnavailable(
            MeasurementInferenceUnavailableReason.eligiblePopulationUnresolved,
          ),
        ),
      ).deliver(_request());

      expect(
        outcome,
        isA<MeasurementAssignmentDeliveryInferenceUnavailable>().having(
          (value) => value.reason,
          'reason',
          MeasurementInferenceUnavailableReason.eligiblePopulationUnresolved,
        ),
      );
      expect(outcome, isNot(isA<MeasurementAssignmentDeliveryAssigned>()));
    });

    test('maps typed transport unavailability without a false assignment',
        () async {
      final outcome =
          await MeasurementAssignmentTransport<_IttRequest, _IttResult>.adapter(
        _RecordingAdapter(
          () => const _IttResult.unavailable(
            MeasurementAssignmentUnavailableReason.policyUnavailable,
          ),
        ),
      ).deliver(_request());

      expect(
        outcome,
        isA<MeasurementAssignmentDeliveryUnavailable>().having(
          (value) => value.reason,
          'reason',
          MeasurementAssignmentUnavailableReason.policyUnavailable,
        ),
      );
      expect(outcome, isNot(isA<MeasurementAssignmentDeliveryAssigned>()));
    });

    test('disabled and no-adapter transports never call an adapter', () async {
      final adapter = _RecordingAdapter(
        () => const _IttResult.committed(
          MeasurementAssignmentCandidateDeliveryDiagnostic.rendered,
        ),
      );
      final request = _request();

      final disabled = await const MeasurementAssignmentTransport<_IttRequest,
              _IttResult>.disabled()
          .deliver(request);
      final noAdapter = await const MeasurementAssignmentTransport<_IttRequest,
              _IttResult>.noAdapter()
          .deliver(request);

      expect(adapter.requests, isEmpty);
      expect(
        disabled,
        isA<MeasurementAssignmentDeliveryUnavailable>().having(
          (value) => value.reason,
          'reason',
          MeasurementAssignmentUnavailableReason.disabled,
        ),
      );
      expect(
        noAdapter,
        isA<MeasurementAssignmentDeliveryUnavailable>().having(
          (value) => value.reason,
          'reason',
          MeasurementAssignmentUnavailableReason.noAdapter,
        ),
      );
    });

    test('adapter exceptions become transport failure', () async {
      final outcome =
          await MeasurementAssignmentTransport<_IttRequest, _IttResult>.adapter(
        _ThrowingAdapter(),
      ).deliver(_request());

      expect(
        outcome,
        isA<MeasurementAssignmentDeliveryUnavailable>().having(
          (value) => value.reason,
          'reason',
          MeasurementAssignmentUnavailableReason.transportFailure,
        ),
      );
    });

    test('exposure remains distinct from assignment delivery', () {
      expect(
        const MeasurementExposureDiagnostic.exposed().isExposed,
        isTrue,
      );
      expect(
        const MeasurementExposureDiagnostic.notAttempted().isExposed,
        isFalse,
      );
      expect(
        const MeasurementExposureDiagnostic.renderFailed().isExposed,
        isFalse,
      );
      expect(
        const MeasurementExposureDiagnostic.fallback().isExposed,
        isFalse,
      );

      const unavailable = MeasurementExposureDiagnostic.unavailable(
        reason: MeasurementInferenceUnavailableReason.integrityUnprovable,
      );
      expect(unavailable.state, MeasurementExposureDiagnosticState.unavailable);
      expect(
        unavailable.unavailableReason,
        MeasurementInferenceUnavailableReason.integrityUnprovable,
      );
    });
  });

  test('the SDK seam carries no identity, Flutter key, or production wiring',
      () {
    final source = _restageFile(
      'lib/src/measurement/measurement_assignment_transport.dart',
    ).readAsStringSync();
    final diagnosticsSource = _restageFile(
      'lib/src/measurement/measurement_assignment_diagnostics.dart',
    ).readAsStringSync();
    final combined = '$source\n$diagnosticsSource';

    for (final forbidden in const [
      'restricted_randomized_units.dart',
      'RestageRpcClient',
      'Restage.configure',
      'userId',
      'accountId',
      'customerId',
      'installationId',
      'UniqueKey',
      'ValueKey',
      'Carrier',
      'base64',
      'opaqueResponse',
    ]) {
      expect(combined, isNot(contains(forbidden)), reason: forbidden);
    }
  });
}

const _requestValue = _IttRequest(17);

_IttRequest _request() => _requestValue;

File _restageFile(String relativePath) {
  for (final prefix in ['', 'packages/restage/']) {
    final candidate = File('$prefix$relativePath');
    if (candidate.existsSync()) return candidate;
  }
  throw StateError('Could not locate packages/restage/$relativePath');
}

final class _RecordingAdapter
    implements MeasurementAssignmentTypedAdapter<_IttRequest, _IttResult> {
  _RecordingAdapter(this._next);

  final _IttResult Function() _next;
  final requests = <_IttRequest>[];

  @override
  Future<_IttResult> deliver(_IttRequest request) async {
    requests.add(request);
    return _next();
  }

  @override
  MeasurementAssignmentDeliveryDiagnostic diagnosticFor(_IttResult result) =>
      result.diagnostic;
}

final class _ThrowingAdapter
    implements MeasurementAssignmentTypedAdapter<_IttRequest, _IttResult> {
  @override
  Future<_IttResult> deliver(_IttRequest request) async =>
      throw StateError('assignment transport unavailable');

  @override
  MeasurementAssignmentDeliveryDiagnostic diagnosticFor(_IttResult result) =>
      throw StateError('unreachable');
}

final class _IttRequest {
  const _IttRequest(this.revision);

  final int revision;
}

sealed class _IttResult {
  const _IttResult();

  const factory _IttResult.committed(
    MeasurementAssignmentCandidateDeliveryDiagnostic candidateDelivery,
  ) = _IttCommitted;

  const factory _IttResult.outsideAudience() = _IttOutsideAudience;

  const factory _IttResult.ineligible() = _IttIneligible;

  const factory _IttResult.unavailable(
    MeasurementAssignmentUnavailableReason reason,
  ) = _IttUnavailable;

  const factory _IttResult.inferenceUnavailable(
    MeasurementInferenceUnavailableReason reason,
  ) = _IttInferenceUnavailable;

  MeasurementAssignmentDeliveryDiagnostic get diagnostic;
}

final class _IttCommitted extends _IttResult {
  const _IttCommitted(this.candidateDelivery);

  final MeasurementAssignmentCandidateDeliveryDiagnostic candidateDelivery;

  @override
  MeasurementAssignmentDeliveryDiagnostic get diagnostic =>
      MeasurementAssignmentDeliveryAssigned(
        candidateDelivery: candidateDelivery,
      );
}

final class _IttOutsideAudience extends _IttResult {
  const _IttOutsideAudience();

  @override
  MeasurementAssignmentDeliveryDiagnostic get diagnostic =>
      const MeasurementAssignmentDeliveryOutsideAudience();
}

final class _IttIneligible extends _IttResult {
  const _IttIneligible();

  @override
  MeasurementAssignmentDeliveryDiagnostic get diagnostic =>
      const MeasurementAssignmentDeliveryIneligible();
}

final class _IttUnavailable extends _IttResult {
  const _IttUnavailable(this.reason);

  final MeasurementAssignmentUnavailableReason reason;

  @override
  MeasurementAssignmentDeliveryDiagnostic get diagnostic =>
      MeasurementAssignmentDeliveryUnavailable(reason);
}

final class _IttInferenceUnavailable extends _IttResult {
  const _IttInferenceUnavailable(this.reason);

  final MeasurementInferenceUnavailableReason reason;

  @override
  MeasurementAssignmentDeliveryDiagnostic get diagnostic =>
      MeasurementAssignmentDeliveryInferenceUnavailable(reason);
}
