import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';

CanonicalSurfaceExperimentAssignmentV1 canonicalAssignmentFixture({
  String arm = 'arm-a',
  String carrier = 'YWJj',
}) =>
    CanonicalSurfaceExperimentAssignmentV1(
      experimentId: ExperimentPublicIdV1('experiment-a'),
      experimentRevisionId: ExperimentPublicRevisionIdV1('revision-a'),
      experimentEpochId: ExperimentPublicEpochIdV1('epoch-a'),
      armId: ExperimentPublicArmIdV1(arm),
      outcomeLinkCarrier: carrier,
    );
