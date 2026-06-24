import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_shared/restage_shared.dart'
    show kBaselineCatalogVersion;

void main() {
  test('OnboardingSource stores id, version, and the baseline default floor',
      () {
    const source = OnboardingSource(id: 'welcome');

    expect(source.id, 'welcome');
    expect(source.version, 1);
    // The default capability floor is the baseline catalog version: an
    // authored screen requires nothing above baseline unless the author
    // overrides it (the screen-derived floor is a tracked follow-up).
    expect(source.minClient, kBaselineCatalogVersion);
  });

  test('OnboardingFlow stores id, version, and min-client', () {
    const flow = OnboardingFlow(id: 'first_run', version: 1, minClient: 3);

    expect(flow.id, 'first_run');
    expect(flow.version, 1);
    expect(flow.minClient, 3);
  });
}
