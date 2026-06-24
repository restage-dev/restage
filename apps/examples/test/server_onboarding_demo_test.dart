import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_example/main_server_onboarding_demo.dart';
import 'package:restage_example/onboarding/flows/first_run.dart';

/// De-risks the dev-only server-delivery demo entrypoint: the bundled first-run
/// flow, re-packaged as a surface envelope and served by the in-app
/// [FakeSurfaceServer], resolves cleanly back through a real [ServerFlowResolver]
/// — so the founder device smoke renders the flow rather than the fail-closed
/// fallback.
void main() {
  setUp(Restage.debugReset);

  testWidgets('the fake surface server delivers the bundled first-run flow',
      (tester) async {
    final envelope = await buildFirstRunSurfaceEnvelope();
    final resolver = ServerFlowResolver(
      baseUrl: 'https://fake-surfaces.local',
      apiKey: 'rs_pk_demo',
      httpClient: FakeSurfaceServer(envelope),
    );

    // A successful resolve means the served envelope decoded, validated, and
    // content-hash-verified every screen blob against its manifest.
    final resolved = await resolver.resolve(FirstRunFlowDescriptor.ref);

    expect(resolved.document.flow, 'first_run');
    expect(resolved.document.version, 1);
    expect(resolved.screenBlobs, isNotEmpty);
    // Every screen artifact has its blob (the isomorphism the resolver
    // enforces), so the flow renders rather than failing closed.
    expect(
      resolved.screenBlobs.keys.toSet(),
      resolved.document.screenArtifacts.keys.toSet(),
    );
  });
}
