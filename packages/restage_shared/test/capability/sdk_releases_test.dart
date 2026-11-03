import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

void main() {
  test('a level names the first release that reports it', () {
    expect(restageReleaseRequirement(3), 'restage 3.0 or later');
    expect(restageReleaseRequirement(4), 'restage 3.0 or later');
    expect(restageReleaseRequirement(1), 'restage 3.0 or later');
  });

  test('a level no release reports yet names no release', () {
    expect(restageReleaseRequirement(newestSdkLevel + 1),
        'a newer Restage SDK release');
  });

  test('a release listed for several levels is offered once', () {
    expect([for (final r in sdkReleasesByLabel) r.label], ['3.0']);
    expect(sdkReleasesByLabel.single.level, 3);
  });

  test('platforms read as people name them', () {
    expect(sdkPlatformName('ios'), 'iOS');
    expect(sdkPlatformName('android'), 'Android');
    expect(sdkPlatformName('web'), 'web');
  });
}
