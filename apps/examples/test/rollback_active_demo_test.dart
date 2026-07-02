// This dev-only de-risk test reaches the resolver's internal active-arm seam
// (`resolveActiveRoot`) directly — hosts trigger it via `active: true` +
// `RestageOnboarding`, but driving the full controller in a widget test hangs
// the fake-async clock, so the test resolves the arm directly.
// ignore_for_file: invalid_use_of_internal_member

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_example/main_rollback_active_demo.dart';
import 'package:restage_example/main_server_onboarding_active_demo.dart'
    show FakeSurfaceServer;
import 'package:restage_example/onboarding/flows/first_run.dart';

/// De-risks the dev-only rollback smoke entrypoint against the REAL bundled
/// first-run flow asset. After an operator rolls the active pointer to a
/// re-pointed version, the active arm serves whatever the pointer names, gated
/// against the app's own bundled contract:
///  - a re-pointed version with an unchanged contract resolves to that ACTIVE
///    version (the re-point reached the client);
///  - a re-pointed version with a raised capability floor fails closed to the
///    bundled version (the gate still applies to a rolled-back target).
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
    'a compatible re-pointed version resolves to the ACTIVE version (the '
    'rollback re-point reached the client)',
    (tester) async {
      final envelope = await buildRolledBackSurfaceEnvelope(compatible: true);
      final resolved = await resolverFor(
        envelope,
      ).resolveActiveRoot(FirstRunFlowDescriptor.ref);

      // The active arm served the re-pointed version (v2), gate-accepted against
      // the app's bundled v1 — not the bundled fallback.
      expect(resolved.document.flow, 'first_run');
      expect(resolved.document.version, 2);
      expect(
        resolved.screenBlobs.keys.toSet(),
        resolved.document.screenArtifacts.keys.toSet(),
      );
    },
  );

  testWidgets(
    'a contract-changed re-pointed version (raised floor) fails closed to the '
    'BUNDLED version',
    (tester) async {
      final envelope = await buildRolledBackSurfaceEnvelope(compatible: false);
      final resolved = await resolverFor(
        envelope,
      ).resolveActiveRoot(FirstRunFlowDescriptor.ref);

      // The incompatible re-pointed version was rejected by the retained
      // capability-floor backstop; the app's own bundled version (v1) resolves.
      expect(resolved.document.version, 1);
    },
  );
}
