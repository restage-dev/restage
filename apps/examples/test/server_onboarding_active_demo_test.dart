// This dev-only de-risk test reaches the resolver's internal active-arm seam
// (`resolveActiveRoot`) directly — hosts trigger it via `active: true` +
// `RestageOnboarding`, but driving the full controller in a widget test hangs
// the fake-async clock, so the test resolves the arm directly.
// ignore_for_file: invalid_use_of_internal_member

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_example/main_server_onboarding_active_demo.dart';
import 'package:restage_example/onboarding/flows/first_run.dart';

/// De-risks the dev-only active-arm demo entrypoint against the REAL bundled
/// first-run flow asset (loaded from the test root bundle, exactly as the device
/// smoke loads it). The active arm gates the server's active version against the
/// app's own bundled contract:
///  - a compatible newer version resolves to the ACTIVE version (the OTA path);
///  - a breaking version fails closed to the bundled version.
void main() {
  setUp(Restage.debugReset);

  ServerFlowResolver resolverFor(Uint8List envelope) {
    return ServerFlowResolver(
      baseUrl: 'https://fake-surfaces.local',
      apiKey: 'rs_pk_demo',
      active: true,
      httpClient: FakeSurfaceServer(envelope),
    );
  }

  testWidgets(
      'compatible active (newer version, same contract) resolves to the ACTIVE '
      'version', (tester) async {
    final envelope = await buildActiveSurfaceEnvelope(compatible: true);
    final resolved = await resolverFor(envelope)
        .resolveActiveRoot(FirstRunFlowDescriptor.ref);

    // The active arm served the newer version (v2), gate-accepted against the
    // app's bundled v1 — not the bundled fallback.
    expect(resolved.document.flow, 'first_run');
    expect(resolved.document.version, 2);
    // Every screen artifact has its blob (the isomorphism the resolver enforces).
    expect(
      resolved.screenBlobs.keys.toSet(),
      resolved.document.screenArtifacts.keys.toSet(),
    );
  });

  testWidgets(
      'breaking active (raised floor) fails closed to the BUNDLED version',
      (tester) async {
    final envelope = await buildActiveSurfaceEnvelope(compatible: false);
    final resolved = await resolverFor(envelope)
        .resolveActiveRoot(FirstRunFlowDescriptor.ref);

    // The incompatible active was rejected by the retained capability-floor
    // backstop; the app's own bundled version (v1) resolves instead.
    expect(resolved.document.version, 1);
  });
}
