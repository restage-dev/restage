import 'package:restage_shared/restage_shared.dart' show kAssignmentSdkApiLevel;

import 'surface_delivery_observations.dart';

/// Assignment request API level compiled into the SDK.
const int assignmentSdkApiLevel = kAssignmentSdkApiLevel;

/// Reads fixed platform and installed-build observations for hosted assignment.
Future<String?> readSurfaceAssignmentBuiltIns() async {
  final observations = await readSurfaceDeliveryObservations();
  return observations.canonicalBuiltInsBase64();
}
