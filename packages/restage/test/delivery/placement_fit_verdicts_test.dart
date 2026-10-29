import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/delivery/placement_fit_verdicts.dart';
import 'package:restage_shared/restage_shared.dart';

import '../support/placement_delivery_fixture.dart';

void main() {
  final fixture = readPlacementDeliveryFixture();
  final decision =
      fixture.response.decisions.first as PlacementBatchAvailableV1;
  final build = fixture.request.buildContract;
  final host = build.contractsByHash[decision.descriptor.hostContractHash]!;
  final installed = build.installedCapability;

  test('a fit is judged once per host and installed runtime', () {
    final requirement = decision.publicDelivery.fitRequirement;
    final first = placementFitVerdict(
        host: host, requirement: requirement, installed: installed);
    expect(
        placementFitVerdict(
            host: host, requirement: requirement, installed: installed),
        same(first));
  });

  test('a verdict judged in the read ahead is used without judging again', () {
    final requirement =
        (PlacementBatchEntryV1.fromCanonicalBytes(decision.canonicalBytes)
                as PlacementBatchAvailableV1)
            .publicDelivery
            .fitRequirement;
    // Judging again would build a new verdict; only the noted one is the same.
    final noted = SurfaceFitVerdictV1.doesNotFit([
      SurfaceFitFailureV1(
          code: SurfaceFitFailureCodeV1.hostingMismatch,
          path: r'$.hosting',
          required: 'presented',
          available: 'inline'),
    ]);
    notePlacementFitVerdict(
        requirement, host.contentHash, installed.contentHash, noted);
    expect(
        placementFitVerdict(
            host: host, requirement: requirement, installed: installed),
        same(noted));
  });
}
