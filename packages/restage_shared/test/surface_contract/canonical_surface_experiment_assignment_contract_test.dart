import 'dart:io';

import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

const _outcomeLinkCarrier = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';

const _canonicalJson = '{"schemaVersion":1,'
    '"experimentId":"experiment.checkout",'
    '"experimentRevisionId":"revision.checkout.1",'
    '"experimentEpochId":"epoch.checkout.1",'
    '"armId":"arm.treatment",'
    '"outcomeLinkCarrier":"$_outcomeLinkCarrier"}';

Map<String, Object?> _canonicalMap() => <String, Object?>{
      'schemaVersion': 1,
      'experimentId': 'experiment.checkout',
      'experimentRevisionId': 'revision.checkout.1',
      'experimentEpochId': 'epoch.checkout.1',
      'armId': 'arm.treatment',
      'outcomeLinkCarrier': _outcomeLinkCarrier,
    };

CanonicalSurfaceExperimentAssignmentV1 _assignment() =>
    CanonicalSurfaceExperimentAssignmentV1(
      experimentId: ExperimentPublicIdV1('experiment.checkout'),
      experimentRevisionId: ExperimentPublicRevisionIdV1('revision.checkout.1'),
      experimentEpochId: ExperimentPublicEpochIdV1('epoch.checkout.1'),
      armId: ExperimentPublicArmIdV1('arm.treatment'),
      outcomeLinkCarrier: _outcomeLinkCarrier,
    );

void main() {
  group('CanonicalSurfaceExperimentAssignmentV1', () {
    test('freezes the strict V1 shape and canonical codec', () {
      final assignment = _assignment();

      expect(
        CanonicalSurfaceExperimentAssignmentV1Codec.encode(assignment),
        _canonicalMap(),
      );
      expect(
        CanonicalSurfaceExperimentAssignmentV1Codec.encodeCanonicalJson(
          assignment,
        ),
        _canonicalJson,
      );

      final decoded = CanonicalSurfaceExperimentAssignmentV1Codec.decodeJson(
          _canonicalJson);
      expect(decoded.experimentId.value, 'experiment.checkout');
      expect(decoded.experimentRevisionId.value, 'revision.checkout.1');
      expect(decoded.experimentEpochId.value, 'epoch.checkout.1');
      expect(decoded.armId.value, 'arm.treatment');
      expect(decoded.outcomeLinkCarrier, _outcomeLinkCarrier);
      expect(
        CanonicalSurfaceExperimentAssignmentV1Codec.encodeCanonicalJson(
            decoded),
        _canonicalJson,
      );
    });

    test('the epoch identity is a string, never an integer', () {
      expect(_assignment().experimentEpochId, isA<ExperimentPublicEpochIdV1>());
      expect(
        () => CanonicalSurfaceExperimentAssignmentV1Codec.decode(
          <String, Object?>{..._canonicalMap(), 'experimentEpochId': 17},
        ),
        throwsFormatException,
      );
    });

    test('rejects unknown, missing, and wrong-typed members', () {
      final canonical = _canonicalMap();

      for (final field in canonical.keys) {
        expect(
          () => CanonicalSurfaceExperimentAssignmentV1Codec.decode(
            Map<String, Object?>.from(canonical)..remove(field),
          ),
          throwsFormatException,
          reason: 'missing $field',
        );
        expect(
          () => CanonicalSurfaceExperimentAssignmentV1Codec.decode(
            <String, Object?>{...canonical, field: null},
          ),
          throwsFormatException,
          reason: 'null $field',
        );
      }

      expect(
        () => CanonicalSurfaceExperimentAssignmentV1Codec.decode(
          <String, Object?>{...canonical, 'future': true},
        ),
        throwsFormatException,
      );

      for (final version in <Object?>[0, 2, 1.0, '1']) {
        expect(
          () => CanonicalSurfaceExperimentAssignmentV1Codec.decode(
            <String, Object?>{...canonical, 'schemaVersion': version},
          ),
          throwsFormatException,
          reason: 'schemaVersion $version',
        );
      }

      expect(
        () => CanonicalSurfaceExperimentAssignmentV1Codec.decodeJson('[]'),
        throwsFormatException,
      );
    });

    test('holds every identity member to the canonical identifier law', () {
      final canonical = _canonicalMap();

      for (final field in const <String>[
        'experimentId',
        'experimentRevisionId',
        'experimentEpochId',
        'armId',
      ]) {
        for (final value in <Object?>[
          7,
          true,
          '',
          ' value',
          'value ',
          'Arm.Treatment',
          'ARM',
          'arm/treatment',
          'arm treatment',
          '.leading',
          'x' * 129,
        ]) {
          expect(
            () => CanonicalSurfaceExperimentAssignmentV1Codec.decode(
              <String, Object?>{...canonical, field: value},
            ),
            throwsFormatException,
            reason: '$field value $value',
          );
        }
      }
    });

    test('the identifier law is the one Measurement already enforces', () {
      for (final accepted in const <String>['a', 'arm.treatment', 'a-b_c:d1']) {
        expect(
          ExperimentPublicArmIdV1(accepted).value,
          accepted,
          reason: accepted,
        );
        expect(
          CanonicalSurfaceExperimentAssignmentV1Codec.decode(
            <String, Object?>{..._canonicalMap(), 'armId': accepted},
          ).armId.value,
          accepted,
        );
      }
      for (final refused in const <String>[
        'ARM',
        'arm/treatment',
        '.leading'
      ]) {
        expect(
          () => ExperimentPublicArmIdV1(refused),
          throwsArgumentError,
          reason: refused,
        );
      }
    });

    test('bounds the opaque carrier and requires canonical base64url', () {
      final canonical = _canonicalMap();

      for (final value in <Object?>[
        7,
        true,
        '',
        'not+canonical',
        'padded=',
        ' $_outcomeLinkCarrier',
        'A' * 4097,
      ]) {
        expect(
          () => CanonicalSurfaceExperimentAssignmentV1Codec.decode(
            <String, Object?>{...canonical, 'outcomeLinkCarrier': value},
          ),
          throwsFormatException,
          reason: 'outcomeLinkCarrier $value',
        );
      }
    });

    test('refuses noncanonical raw keys without a deleted type', () {
      for (final rawKey in const <String>[
        'revisionId',
        'epochId',
        'experimentEpoch',
        'variantId',
        'outcomeLinkToken',
      ]) {
        expect(
          () => CanonicalSurfaceExperimentAssignmentV1Codec.decode(
            <String, Object?>{..._canonicalMap(), rawKey: 'not-canonical'},
          ),
          throwsFormatException,
          reason: rawKey,
        );
      }
    });

    test('publishes exactly the six current wire fields, in order', () {
      expect(
        CanonicalSurfaceExperimentAssignmentV1Codec.encode(_assignment()).keys,
        orderedEquals(<String>[
          'schemaVersion',
          'experimentId',
          'experimentRevisionId',
          'experimentEpochId',
          'armId',
          'outcomeLinkCarrier',
        ]),
      );
    });

    test('compares by value and separates a differing member', () {
      expect(_assignment(), _assignment());
      expect(_assignment().hashCode, _assignment().hashCode);
      expect(
        CanonicalSurfaceExperimentAssignmentV1Codec.decode(
          <String, Object?>{..._canonicalMap(), 'armId': 'arm.control'},
        ),
        isNot(_assignment()),
      );
    });

    test('the deleted assignment and integer epoch stay absent in source', () {
      final source = File(
        'lib/src/surface_contract/surface_publication_contract.dart',
      ).readAsStringSync();

      for (final retired in const <String>[
        'SurfaceExperimentAssignment',
        'FlowAssignment',
        'experimentEpoch',
        'variantId',
      ]) {
        expect(
          RegExp('\\b${RegExp.escape(retired)}\\b').hasMatch(source),
          isFalse,
          reason: 'the surface publication contract still names $retired',
        );
      }
    });
  });
}
