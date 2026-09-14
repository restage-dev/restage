import 'surface_delivery_observations.dart';

/// Assignment request API level compiled into the SDK.
const int assignmentSdkApiLevel = 3;

/// Reads fixed platform and installed-build observations for hosted assignment.
Future<String?> readSurfaceAssignmentBuiltIns() async {
  final observations = await readSurfaceDeliveryObservations();
  return observations.canonicalBuiltInsBase64();
}
