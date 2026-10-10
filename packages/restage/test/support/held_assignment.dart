import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/resolver/surface_assignment_key_provider.dart';
import 'package:restage/src/resolver/surface_canonical_carrier_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Retains served assignments under [key], and lets a stored delivery read
/// the same key back as the one this device holds.
void holdAssignmentsUnder(String key) {
  SharedPreferences.setMockInitialValues({});
  SurfaceAssignmentKeyProvider.current = () => key;
  SurfaceAssignmentKeyProvider.local = () => key;
  SurfaceCanonicalCarrierProvider.enableAssignmentRetention('test-scope');
  addTearDown(() {
    SurfaceAssignmentKeyProvider.clear();
    SurfaceCanonicalCarrierProvider.clear();
  });
}
