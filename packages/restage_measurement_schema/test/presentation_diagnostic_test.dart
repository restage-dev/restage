import 'dart:convert';

import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:test/test.dart';

String _base64(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

const _diagnostic = MeasurementPresentationDiagnosticV1(
  rootPresentationReports: MeasurementRootPresentationReportsV1.none,
  stepObserved: false,
  finishReason: MeasurementPresentationFinishReasonV1.paintFailed,
  captureIncomplete: true,
);

void main() {
  group('MeasurementBreakdownPointV1', () {
    for (final kind in MeasurementBreakdownPointKindV1.values) {
      for (final order in [null, 0, kMaximumPortableJsonInteger]) {
        test('${kind.name} with authored order $order round-trips', () {
          final point = MeasurementBreakdownPointV1(
            kindV1: kind,
            reference: 'point.1',
            label: 'First point',
            authoredOrder: order,
          );
          final read = MeasurementBreakdownPointV1.fromJson(
            decodeCanonicalObject(point.canonicalBytes),
          );
          expect(read.canonicalBytes, orderedEquals(point.canonicalBytes));
          expect(read.kindV1, kind);
          expect(read.authoredOrder, order);
          expect(point.toJson().containsKey('authoredOrder'), order != null);
        });
      }
    }
    test('rejects unknown keys, kinds and invalid bounds', () {
      final valid = MeasurementBreakdownPointV1(
        kindV1: MeasurementBreakdownPointKindV1.question,
        reference: 'question.1',
        label: 'Question',
      ).toJson();
      for (final change in <Map<String, Object?>>[
        {'unknown': true},
        {'kindV1': 'unknown'},
        {'reference': ''},
        {'reference': 'r' * 129},
        {'label': ''},
        {'label': 'l' * 129},
        {'authoredOrder': -1},
        {'authoredOrder': kMaximumPortableJsonInteger + 1},
      ]) {
        expect(
            () => MeasurementBreakdownPointV1.fromJson({...valid, ...change}),
            throwsA(anything),
            reason: '$change');
      }
    });
  });

  group('MeasurementOrderedCaptureRouteV1', () {
    for (final withPoint in [false, true]) {
      test('route with breakdown point $withPoint preserves canonical bytes',
          () {
        final document = <String, Object?>{
          'channels': ['presentation'],
          'lineageId': 'lineage.point',
          'occurrenceId': 'a' * 64,
          if (withPoint)
            'breakdownPointV1': {
              'authoredOrder': 0,
              'kindV1': 'pageIndex',
              'label': 'First page',
              'reference': '0',
            },
        };
        final bytes = CanonicalJsonCodec.encode(document);
        final route = MeasurementOrderedCaptureRouteV1.fromJson(
            decodeCanonicalObject(bytes));
        expect(route.canonicalBytes, orderedEquals(bytes));
        expect(route.toJson().containsKey('breakdownPointV1'), withPoint);
        if (withPoint) {
          expect(route.breakdownPointV1!.reference, '0');
        } else {
          expect(route.breakdownPointV1, isNull);
        }
      });
    }
  });

  group('MeasurementPresentationDiagnosticV1', () {
    for (final reports in MeasurementRootPresentationReportsV1.values) {
      for (final reason in MeasurementPresentationFinishReasonV1.values) {
        test('${reports.name} and ${reason.name} round-trip', () {
          final diagnostic = MeasurementPresentationDiagnosticV1(
            rootPresentationReports: reports,
            finishReason: reason,
            stepObserved: true,
            captureIncomplete: false,
          );
          final read = MeasurementPresentationDiagnosticV1.fromCanonicalBytes(
              diagnostic.canonicalBytes);
          expect(read.canonicalBytes, orderedEquals(diagnostic.canonicalBytes));
          expect(read.rootPresentationReports, reports);
          expect(read.finishReason, reason);
        });
      }
    }
    test('rejects unknown, missing and invalid members', () {
      final valid = _diagnostic.toJson();
      final invalid = <Map<String, Object?>>[
        {...valid, 'unknown': true},
        {...valid, 'rootPresentationReports': 'two'},
        {...valid, 'finishReason': 'finished'},
        {...valid, 'kind': 'measurementPresentationContext'},
        {...valid, 'schemaVersion': 2},
        {...valid, 'stepObserved': 1},
        {...valid, 'captureIncomplete': 'true'},
        for (final key in valid.keys) Map.of(valid)..remove(key),
      ];
      for (final document in invalid) {
        expect(
            () => MeasurementPresentationDiagnosticV1.fromCanonicalBytes(
                CanonicalJsonCodec.encode(document)),
            throwsA(anything));
      }
    });
  });

  group('MeasurementPresentationDiagnosticRequestV1', () {
    final nonce = 'a' * 64;
    final bindingReference = MeasurementPublicationBindingReferenceV1(
      publicationAuthorityReference: RegisteredPublicationAuthorityReferenceV1(
        authorityId: MeasurementPublicationAuthorityId('authority.sdk.ingest'),
        externalPublicationAuthorityRef: 'mpa1.${'A' * 32}',
        candidateReference: MeasurementPublicationCandidateReferenceV1(
          candidateDigest: CanonicalDigest('d' * 64),
          selectedPublicationManifestDigest: CanonicalDigest('e' * 64),
          declaredArtifactBytesDigest: CanonicalDigest('f' * 64),
          assembledPublicationUploadDigest: CanonicalDigest('1' * 64),
          measurementPublicationDraftDigest: CanonicalDigest('2' * 64),
        ),
        immutablePublicationDigest: CanonicalDigest('3' * 64),
        declaredArtifactBytesDigest: CanonicalDigest('f' * 64),
      ),
      bindingDigest: CanonicalDigest('4' * 64),
    );
    final context = _base64(
        MeasurementPresentationContextV1(platform: 'web').canonicalBytes);
    final optionSets = <Map<String, String>>[
      {},
      {'sdkRuntimeSessionNonce': nonce},
      {'sdkRuntimeSessionNonce': nonce, 'reportedSdkVersion': '2.0.0'},
      {'presentationContextCanonicalBase64': context},
      {'routingSelectionReceipt': 'opaque-receipt'},
      {
        'sdkRuntimeSessionNonce': nonce,
        'reportedSdkVersion': '2.0.0',
        'presentationContextCanonicalBase64': context,
        'routingSelectionReceipt': 'opaque-receipt'
      },
    ];
    for (var index = 0; index < optionSets.length; index++) {
      test('optional combination $index round-trips', () {
        final options = optionSets[index];
        final request =
            MeasurementPresentationDiagnosticRequestV1.fromDiagnostic(
          _diagnostic,
          captureSessionNonce: nonce,
          publicationBindingReference: bindingReference,
          sequence: 7,
          sdkRuntimeSessionNonce: options['sdkRuntimeSessionNonce'],
          reportedSdkVersion: options['reportedSdkVersion'],
          presentationContextCanonicalBase64:
              options['presentationContextCanonicalBase64'],
          routingSelectionReceipt: options['routingSelectionReceipt'],
        );
        final document = <String, Object?>{
          'captureSessionNonce': nonce,
          'diagnosticCanonicalBase64': _base64(_diagnostic.canonicalBytes),
          'kind': 'authenticatedMeasurementPresentationDiagnosticRequest',
          'publicationBindingReference': bindingReference.toJson(),
          'schemaVersion': 1,
          'sequence': 7,
          ...options,
        };
        expect(request.canonicalBytes,
            orderedEquals(CanonicalJsonCodec.encode(document)));
        for (final read in [
          MeasurementPresentationDiagnosticRequestV1.fromBase64(
              request.canonicalRequestBase64),
          MeasurementPresentationDiagnosticRequestV1.fromCanonicalBytes(
              request.canonicalBytes),
        ]) {
          expect(read.canonicalBytes, orderedEquals(request.canonicalBytes));
          expect(read.toJson(), document);
          expect(read.requestSha256, request.requestSha256);
          expect(read.diagnostic, _diagnostic);
          expect(read.captureSessionNonce, nonce);
          expect(read.publicationBindingReference.canonicalBytes,
              orderedEquals(bindingReference.canonicalBytes));
          expect(read.sequence, 7);
        }
      });
    }
    test('rejects unknown, missing, wrong-kind and invalid metadata', () {
      final valid = MeasurementPresentationDiagnosticRequestV1.fromDiagnostic(
        _diagnostic,
        captureSessionNonce: nonce,
        publicationBindingReference: bindingReference,
        sequence: 7,
      ).toJson();
      for (final document in <Map<String, Object?>>[
        {...valid, 'unknown': true},
        Map.of(valid)..remove('diagnosticCanonicalBase64'),
        Map.of(valid)..remove('captureSessionNonce'),
        Map.of(valid)..remove('publicationBindingReference'),
        Map.of(valid)..remove('sequence'),
        {...valid, 'kind': 'authenticatedMeasurementIngestRequest'},
        {...valid, 'schemaVersion': 2},
        {...valid, 'diagnosticCanonicalBase64': 'bad='},
        {...valid, 'reportedSdkVersion': '2.0.0'},
        {...valid, 'sdkRuntimeSessionNonce': 'A' * 64},
        {...valid, 'sdkRuntimeSessionNonce': nonce, 'reportedSdkVersion': ''},
        {...valid, 'presentationContextCanonicalBase64': 1},
        {...valid, 'routingSelectionReceipt': 1},
      ]) {
        final bytes = CanonicalJsonCodec.encode(document);
        expect(
            () => MeasurementPresentationDiagnosticRequestV1.fromCanonicalBytes(
                bytes),
            throwsA(isA<MeasurementIngestCodecException>()));
        expect(
            () => MeasurementPresentationDiagnosticRequestV1.fromBase64(
                _base64(bytes)),
            throwsA(isA<MeasurementIngestCodecException>()));
      }
    });
  });
}
